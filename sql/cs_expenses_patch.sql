-- ═══════════════════════════════════════════════════════════════
-- Expenses Patch – cs_expenses + cs_expense_shares + RPC
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1. Tables (idempotent)
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cs_expenses (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id        uuid        NOT NULL REFERENCES public.cs_matches(id) ON DELETE CASCADE,
  team_id         uuid        NOT NULL REFERENCES public.cs_teams(id)   ON DELETE CASCADE,
  title           text        NOT NULL,
  amount_cents    int         NOT NULL CHECK (amount_cents > 0),
  currency        text        NOT NULL DEFAULT 'CHF',
  paid_by_user_id uuid        NOT NULL REFERENCES auth.users(id)        ON DELETE RESTRICT,
  note            text        NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cs_expenses_match
  ON public.cs_expenses (match_id);
CREATE INDEX IF NOT EXISTS idx_cs_expenses_team
  ON public.cs_expenses (team_id);
CREATE INDEX IF NOT EXISTS idx_cs_expenses_paid_by
  ON public.cs_expenses (paid_by_user_id);

CREATE TABLE IF NOT EXISTS public.cs_expense_shares (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id  uuid        NOT NULL REFERENCES public.cs_expenses(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES auth.users(id)         ON DELETE CASCADE,
  share_cents int         NOT NULL CHECK (share_cents >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (expense_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_cs_expense_shares_expense
  ON public.cs_expense_shares (expense_id);
CREATE INDEX IF NOT EXISTS idx_cs_expense_shares_user
  ON public.cs_expense_shares (user_id);

-- ─────────────────────────────────────────────
-- 2. updated_at trigger for cs_expenses
-- ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cs_expenses_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cs_expenses_updated_at ON public.cs_expenses;
CREATE TRIGGER trg_cs_expenses_updated_at
  BEFORE UPDATE ON public.cs_expenses
  FOR EACH ROW
  EXECUTE FUNCTION public.cs_expenses_set_updated_at();

-- ─────────────────────────────────────────────
-- 3. Enable RLS
-- ─────────────────────────────────────────────

ALTER TABLE public.cs_expenses       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_expenses       FORCE  ROW LEVEL SECURITY;
ALTER TABLE public.cs_expense_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_expense_shares FORCE  ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- 4. RLS Policies – cs_expenses
-- ─────────────────────────────────────────────

-- SELECT: Team members can read all expenses
DROP POLICY IF EXISTS cs_expenses_select ON public.cs_expenses;
CREATE POLICY cs_expenses_select ON public.cs_expenses
  FOR SELECT
  USING (public.is_team_member(team_id));

-- INSERT: Team members can create expenses (paid_by = self)
DROP POLICY IF EXISTS cs_expenses_insert ON public.cs_expenses;
CREATE POLICY cs_expenses_insert ON public.cs_expenses
  FOR INSERT
  WITH CHECK (
    public.is_team_member(team_id)
    AND paid_by_user_id = auth.uid()
  );

-- UPDATE: Only the person who paid can update
DROP POLICY IF EXISTS cs_expenses_update ON public.cs_expenses;
CREATE POLICY cs_expenses_update ON public.cs_expenses
  FOR UPDATE
  USING (paid_by_user_id = auth.uid())
  WITH CHECK (paid_by_user_id = auth.uid());

-- DELETE: Only the person who paid (or team admin)
DROP POLICY IF EXISTS cs_expenses_delete ON public.cs_expenses;
CREATE POLICY cs_expenses_delete ON public.cs_expenses
  FOR DELETE
  USING (
    paid_by_user_id = auth.uid()
    OR public.is_team_admin(team_id)
  );

-- ─────────────────────────────────────────────
-- 5. RLS Policies – cs_expense_shares
-- ─────────────────────────────────────────────

-- SELECT: Team members can read shares (via expense's team_id)
DROP POLICY IF EXISTS cs_expense_shares_select ON public.cs_expense_shares;
CREATE POLICY cs_expense_shares_select ON public.cs_expense_shares
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.cs_expenses e
       WHERE e.id = expense_id
         AND public.is_team_member(e.team_id)
    )
  );

-- INSERT: Only via RPC / triggers (no direct client inserts)
-- We still need a policy so the RPC (running as the user) can insert.
DROP POLICY IF EXISTS cs_expense_shares_insert ON public.cs_expense_shares;
CREATE POLICY cs_expense_shares_insert ON public.cs_expense_shares
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.cs_expenses e
       WHERE e.id = expense_id
         AND public.is_team_member(e.team_id)
    )
  );

-- DELETE: Cascade from expense delete handles this; explicit policy for safety
DROP POLICY IF EXISTS cs_expense_shares_delete ON public.cs_expense_shares;
CREATE POLICY cs_expense_shares_delete ON public.cs_expense_shares
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.cs_expenses e
       WHERE e.id = expense_id
         AND (
           e.paid_by_user_id = auth.uid()
           OR public.is_team_admin(e.team_id)
         )
    )
  );

-- ─────────────────────────────────────────────
-- 6. RPC: cs_create_expense_equal_split
-- ─────────────────────────────────────────────
-- Creates an expense and distributes cost equally among team members.
-- Remainder cents are distributed 1 each to the first N members.

CREATE OR REPLACE FUNCTION public.cs_create_expense_equal_split(
  p_match_id    uuid,
  p_title       text,
  p_amount_cents int,
  p_note        text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_team_id       uuid;
  v_expense_id    uuid;
  v_member_count  int;
  v_base_share    int;
  v_remainder     int;
  v_member        record;
  v_idx           int := 0;
BEGIN
  -- 1. Resolve team_id from match
  SELECT m.team_id INTO v_team_id
    FROM public.cs_matches m
   WHERE m.id = p_match_id;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Match not found: %', p_match_id;
  END IF;

  -- 2. Verify caller is team member
  IF NOT public.is_team_member(v_team_id) THEN
    RAISE EXCEPTION 'Not a team member';
  END IF;

  -- 3. Create expense
  INSERT INTO public.cs_expenses (match_id, team_id, title, amount_cents, paid_by_user_id, note)
  VALUES (p_match_id, v_team_id, p_title, p_amount_cents, auth.uid(), p_note)
  RETURNING id INTO v_expense_id;

  -- 4. Count team members (only those with a user_id = joined)
  SELECT count(*) INTO v_member_count
    FROM public.cs_team_members tm
   WHERE tm.team_id = v_team_id
     AND tm.user_id IS NOT NULL;

  IF v_member_count = 0 THEN
    RAISE EXCEPTION 'No team members found for team %', v_team_id;
  END IF;

  -- 5. Calculate equal split
  v_base_share := p_amount_cents / v_member_count;
  v_remainder  := p_amount_cents - (v_base_share * v_member_count);

  -- 6. Insert shares
  FOR v_member IN
    SELECT tm.user_id
      FROM public.cs_team_members tm
     WHERE tm.team_id = v_team_id
       AND tm.user_id IS NOT NULL
     ORDER BY tm.created_at ASC
  LOOP
    INSERT INTO public.cs_expense_shares (expense_id, user_id, share_cents)
    VALUES (
      v_expense_id,
      v_member.user_id,
      CASE WHEN v_idx < v_remainder
           THEN v_base_share + 1
           ELSE v_base_share
      END
    );
    v_idx := v_idx + 1;
  END LOOP;

  RETURN v_expense_id;
END;
$$;

-- ─────────────────────────────────────────────
-- 7. Verify (run after applying)
-- ─────────────────────────────────────────────

-- SELECT relname, relrowsecurity
--   FROM pg_class
--  WHERE relname IN ('cs_expenses','cs_expense_shares');

-- SELECT schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check
--   FROM pg_policies
--  WHERE tablename IN ('cs_expenses','cs_expense_shares')
--  ORDER BY tablename, policyname;
