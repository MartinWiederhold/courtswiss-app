-- ═══════════════════════════════════════════════════════════════
-- Expenses V2 Patch – Dinner-YES split + paid status
-- Idempotent – safe to run multiple times.
-- Depends on: cs_expenses_patch.sql + cs_dinner_rsvps_patch.sql
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1. Add columns to cs_expense_shares (idempotent)
-- ─────────────────────────────────────────────

DO $$
BEGIN
  -- is_paid
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'cs_expense_shares'
       AND column_name  = 'is_paid'
  ) THEN
    ALTER TABLE public.cs_expense_shares
      ADD COLUMN is_paid boolean NOT NULL DEFAULT false;
  END IF;

  -- paid_at
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'cs_expense_shares'
       AND column_name  = 'paid_at'
  ) THEN
    ALTER TABLE public.cs_expense_shares
      ADD COLUMN paid_at timestamptz NULL;
  END IF;
END
$$;

-- ─────────────────────────────────────────────
-- 2. UPDATE policy on cs_expense_shares
-- ─────────────────────────────────────────────
-- Own share can be toggled by the user themselves.
-- The expense payer (paid_by_user_id) or team admin can toggle any share.

DROP POLICY IF EXISTS cs_expense_shares_update ON public.cs_expense_shares;
CREATE POLICY cs_expense_shares_update ON public.cs_expense_shares
  FOR UPDATE
  USING (
    -- Own share
    user_id = auth.uid()
    OR
    -- Payer or admin of the expense's team
    EXISTS (
      SELECT 1 FROM public.cs_expenses e
       WHERE e.id = expense_id
         AND (
           e.paid_by_user_id = auth.uid()
           OR public.is_team_admin(e.team_id)
         )
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR
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
-- 3. RPC: cs_mark_expense_share_paid
-- ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cs_mark_expense_share_paid(
  p_share_id uuid,
  p_paid     boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  UPDATE public.cs_expense_shares
     SET is_paid = p_paid,
         paid_at = CASE WHEN p_paid THEN now() ELSE NULL END
   WHERE id = p_share_id;

  -- RLS UPDATE policy enforces permission (own share / payer / admin)
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Share not found or not permitted: %', p_share_id;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────
-- 4. Updated RPC: cs_create_expense_equal_split
-- ─────────────────────────────────────────────
-- Now splits ONLY among users who have dinner RSVP = 'yes'.
-- Falls back with an error if no dinner-yes participants exist.

CREATE OR REPLACE FUNCTION public.cs_create_expense_equal_split(
  p_match_id     uuid,
  p_title        text,
  p_amount_cents int,
  p_note         text DEFAULT NULL
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

  -- 3. Count dinner-yes participants
  SELECT count(*) INTO v_member_count
    FROM public.cs_team_members tm
    JOIN public.cs_dinner_rsvps r
      ON r.match_id = p_match_id
     AND r.user_id  = tm.user_id
     AND r.status   = 'yes'
   WHERE tm.team_id = v_team_id
     AND tm.user_id IS NOT NULL;

  IF v_member_count = 0 THEN
    RAISE EXCEPTION 'Keine Dinner-Teilnehmer (Ja) – bitte zuerst Essen zusagen.';
  END IF;

  -- 4. Create expense
  INSERT INTO public.cs_expenses (match_id, team_id, title, amount_cents, paid_by_user_id, note)
  VALUES (p_match_id, v_team_id, p_title, p_amount_cents, auth.uid(), p_note)
  RETURNING id INTO v_expense_id;

  -- 5. Calculate equal split
  v_base_share := p_amount_cents / v_member_count;
  v_remainder  := p_amount_cents - (v_base_share * v_member_count);

  -- 6. Insert shares (only for dinner-yes users)
  FOR v_member IN
    SELECT tm.user_id
      FROM public.cs_team_members tm
      JOIN public.cs_dinner_rsvps r
        ON r.match_id = p_match_id
       AND r.user_id  = tm.user_id
       AND r.status   = 'yes'
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

  -- 7. Auto-mark payer's share as paid (they already fronted the money)
  UPDATE public.cs_expense_shares
     SET is_paid = true,
         paid_at = now()
   WHERE expense_id = v_expense_id
     AND user_id    = auth.uid();

  RETURN v_expense_id;
END;
$$;

-- ─────────────────────────────────────────────
-- 5. Verify (run after applying)
-- ─────────────────────────────────────────────

-- Check new columns:
-- SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--  WHERE table_name = 'cs_expense_shares'
--    AND column_name IN ('is_paid','paid_at');

-- Check policies:
-- SELECT policyname, cmd, qual, with_check
--   FROM pg_policies
--  WHERE tablename = 'cs_expense_shares'
--  ORDER BY policyname;

-- Check RPCs:
-- SELECT routine_name FROM information_schema.routines
--  WHERE routine_name IN ('cs_create_expense_equal_split','cs_mark_expense_share_paid');
