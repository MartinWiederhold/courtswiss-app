-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – RLS Helper Functions + Expenses RLS Fix         ║
-- ║  Idempotent – safe to run multiple times.                     ║
-- ║                                                                ║
-- ║  Problem: The helper functions is_team_member, is_team_admin,  ║
-- ║  is_team_creator are referenced by ALL RLS policies but were   ║
-- ║  never defined in a SQL patch file. If they don't exist,       ║
-- ║  DELETE/UPDATE policies that use is_team_admin fail to create, ║
-- ║  blocking all expense deletes.                                 ║
-- ║                                                                ║
-- ║  This patch:                                                   ║
-- ║  1. Creates the 3 helper functions (idempotent)                ║
-- ║  2. Re-creates all cs_expenses + cs_expense_shares RLS         ║
-- ║     policies (DROP IF EXISTS + CREATE)                         ║
-- ║  3. Fixes the anon-migration column name bug (paid_by →        ║
-- ║     paid_by_user_id)                                           ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  1. HELPER FUNCTIONS (idempotent via CREATE OR REPLACE)
-- ═══════════════════════════════════════════════════════════════════

-- ── is_team_member ─────────────────────────────────────────────────
-- Returns true if the current auth.uid() is a member of the given team.
CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.cs_team_members
     WHERE team_id = p_team_id
       AND user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO anon;


-- ── is_team_admin ──────────────────────────────────────────────────
-- Returns true if the current auth.uid() is a captain of the given team.
CREATE OR REPLACE FUNCTION public.is_team_admin(p_team_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.cs_team_members
     WHERE team_id = p_team_id
       AND user_id = auth.uid()
       AND role    = 'captain'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_team_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_admin(uuid) TO anon;


-- ── is_team_creator ────────────────────────────────────────────────
-- Returns true if the current auth.uid() created the given team.
CREATE OR REPLACE FUNCTION public.is_team_creator(p_team_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.cs_teams
     WHERE id         = p_team_id
       AND created_by = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_team_creator(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_creator(uuid) TO anon;


-- ═══════════════════════════════════════════════════════════════════
--  2. RE-CREATE ALL cs_expenses RLS POLICIES
--     (idempotent via DROP IF EXISTS + CREATE)
-- ═══════════════════════════════════════════════════════════════════

-- Ensure RLS is enabled
ALTER TABLE public.cs_expenses       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_expenses       FORCE  ROW LEVEL SECURITY;
ALTER TABLE public.cs_expense_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_expense_shares FORCE  ROW LEVEL SECURITY;

-- ── cs_expenses ────────────────────────────────────────────────────

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

-- UPDATE: The person who paid (or team admin) can update
DROP POLICY IF EXISTS cs_expenses_update ON public.cs_expenses;
CREATE POLICY cs_expenses_update ON public.cs_expenses
  FOR UPDATE
  USING (
    paid_by_user_id = auth.uid()
    OR public.is_team_admin(team_id)
  )
  WITH CHECK (
    paid_by_user_id = auth.uid()
    OR public.is_team_admin(team_id)
  );

-- DELETE: The person who paid (or team admin) can delete
DROP POLICY IF EXISTS cs_expenses_delete ON public.cs_expenses;
CREATE POLICY cs_expenses_delete ON public.cs_expenses
  FOR DELETE
  USING (
    paid_by_user_id = auth.uid()
    OR public.is_team_admin(team_id)
  );

-- ── cs_expense_shares ──────────────────────────────────────────────

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

-- INSERT: Team members can insert shares (via RPC / triggers)
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

-- UPDATE: Own share, or payer/admin of the expense
DROP POLICY IF EXISTS cs_expense_shares_update ON public.cs_expense_shares;
CREATE POLICY cs_expense_shares_update ON public.cs_expense_shares
  FOR UPDATE
  USING (
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

-- DELETE: Payer or admin of the expense (also needed for CASCADE)
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


-- ═══════════════════════════════════════════════════════════════════
--  3. DIAGNOSTIC: Verify everything is correct
-- ═══════════════════════════════════════════════════════════════════

-- Run these queries after the patch to verify:

-- 3a. Check helper functions exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'is_team_member'
  ) THEN
    RAISE EXCEPTION 'is_team_member function NOT found!';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'is_team_admin'
  ) THEN
    RAISE EXCEPTION 'is_team_admin function NOT found!';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'is_team_creator'
  ) THEN
    RAISE EXCEPTION 'is_team_creator function NOT found!';
  END IF;
  RAISE NOTICE '✅ All helper functions exist';
END
$$;

-- 3b. Check RLS policies for cs_expenses
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE tablename = 'cs_expenses';
  IF v_count < 4 THEN
    RAISE WARNING 'cs_expenses has only % policies (expected 4: select, insert, update, delete)', v_count;
  ELSE
    RAISE NOTICE '✅ cs_expenses has % RLS policies', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE tablename = 'cs_expense_shares';
  IF v_count < 4 THEN
    RAISE WARNING 'cs_expense_shares has only % policies (expected 4)', v_count;
  ELSE
    RAISE NOTICE '✅ cs_expense_shares has % RLS policies', v_count;
  END IF;
END
$$;

-- 3c. Show all expense policies for manual review
-- SELECT schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check
--   FROM pg_policies
--  WHERE tablename IN ('cs_expenses', 'cs_expense_shares')
--  ORDER BY tablename, policyname;


-- ═══════════════════════════════════════════════════════════════════
--  4. PostgREST schema cache reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
