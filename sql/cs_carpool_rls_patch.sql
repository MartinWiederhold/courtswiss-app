-- ═══════════════════════════════════════════════════════════════
-- Carpool RLS Patch – cs_carpool_offers & cs_carpool_passengers
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 0. Diagnostics (run these first to see current state)
-- ─────────────────────────────────────────────

-- Show RLS status for both tables:
-- SELECT relname, relrowsecurity
--   FROM pg_class
--  WHERE relname IN ('cs_carpool_offers','cs_carpool_passengers');

-- Show existing policies:
-- SELECT schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check
--   FROM pg_policies
--  WHERE tablename IN ('cs_carpool_offers','cs_carpool_passengers')
--  ORDER BY tablename, policyname;

-- ─────────────────────────────────────────────
-- 1. Enable RLS (idempotent)
-- ─────────────────────────────────────────────

ALTER TABLE public.cs_carpool_offers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_carpool_passengers   ENABLE ROW LEVEL SECURITY;

-- Force RLS even for table owner (optional safety):
ALTER TABLE public.cs_carpool_offers       FORCE ROW LEVEL SECURITY;
ALTER TABLE public.cs_carpool_passengers   FORCE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- 2. cs_carpool_offers Policies
-- ─────────────────────────────────────────────

-- SELECT: Any team member can read all offers for their team's matches
DROP POLICY IF EXISTS cs_carpool_offers_select ON public.cs_carpool_offers;
CREATE POLICY cs_carpool_offers_select ON public.cs_carpool_offers
  FOR SELECT
  USING (public.is_team_member(team_id));

-- INSERT: Any team member can create an offer (they become the driver)
DROP POLICY IF EXISTS cs_carpool_offers_insert ON public.cs_carpool_offers;
CREATE POLICY cs_carpool_offers_insert ON public.cs_carpool_offers
  FOR INSERT
  WITH CHECK (
    public.is_team_member(team_id)
    AND driver_user_id = auth.uid()
  );

-- UPDATE: Only the driver can update their own offer
DROP POLICY IF EXISTS cs_carpool_offers_update ON public.cs_carpool_offers;
CREATE POLICY cs_carpool_offers_update ON public.cs_carpool_offers
  FOR UPDATE
  USING (driver_user_id = auth.uid())
  WITH CHECK (driver_user_id = auth.uid());

-- DELETE: Only the driver (or team admin) can delete an offer
DROP POLICY IF EXISTS cs_carpool_offers_delete ON public.cs_carpool_offers;
CREATE POLICY cs_carpool_offers_delete ON public.cs_carpool_offers
  FOR DELETE
  USING (
    driver_user_id = auth.uid()
    OR public.is_team_admin(team_id)
  );

-- ─────────────────────────────────────────────
-- 3. cs_carpool_passengers Policies
-- ─────────────────────────────────────────────

-- SELECT: Any team member can see passengers (via the offer's team_id)
DROP POLICY IF EXISTS cs_carpool_passengers_select ON public.cs_carpool_passengers;
CREATE POLICY cs_carpool_passengers_select ON public.cs_carpool_passengers
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.cs_carpool_offers o
       WHERE o.id = offer_id
         AND public.is_team_member(o.team_id)
    )
  );

-- INSERT: A team member can add themselves as passenger
DROP POLICY IF EXISTS cs_carpool_passengers_insert ON public.cs_carpool_passengers;
CREATE POLICY cs_carpool_passengers_insert ON public.cs_carpool_passengers
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.cs_carpool_offers o
       WHERE o.id = offer_id
         AND public.is_team_member(o.team_id)
    )
  );

-- DELETE: A passenger can remove themselves, or the driver/admin can remove anyone
DROP POLICY IF EXISTS cs_carpool_passengers_delete ON public.cs_carpool_passengers;
CREATE POLICY cs_carpool_passengers_delete ON public.cs_carpool_passengers
  FOR DELETE
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cs_carpool_offers o
       WHERE o.id = offer_id
         AND (
           o.driver_user_id = auth.uid()
           OR public.is_team_admin(o.team_id)
         )
    )
  );

-- ─────────────────────────────────────────────
-- 4. Verify (run after applying)
-- ─────────────────────────────────────────────

-- SELECT relname, relrowsecurity
--   FROM pg_class
--  WHERE relname IN ('cs_carpool_offers','cs_carpool_passengers');

-- SELECT schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check
--   FROM pg_policies
--  WHERE tablename IN ('cs_carpool_offers','cs_carpool_passengers')
--  ORDER BY tablename, policyname;
