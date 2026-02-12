-- ═══════════════════════════════════════════════════════════════
-- Dinner RSVP Patch – cs_dinner_rsvps
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1. Create table (idempotent)
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cs_dinner_rsvps (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id   uuid        NOT NULL REFERENCES public.cs_matches(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id)        ON DELETE CASCADE,
  status     text        NOT NULL CHECK (status IN ('yes','no','maybe')),
  note       text        NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cs_dinner_rsvps_match
  ON public.cs_dinner_rsvps (match_id);
CREATE INDEX IF NOT EXISTS idx_cs_dinner_rsvps_user
  ON public.cs_dinner_rsvps (user_id);

-- ─────────────────────────────────────────────
-- 2. updated_at trigger (idempotent)
-- ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cs_dinner_rsvps_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cs_dinner_rsvps_updated_at ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_cs_dinner_rsvps_updated_at
  BEFORE UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION public.cs_dinner_rsvps_set_updated_at();

-- ─────────────────────────────────────────────
-- 3. Enable RLS
-- ─────────────────────────────────────────────

ALTER TABLE public.cs_dinner_rsvps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_dinner_rsvps FORCE  ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- 4. RLS Policies
-- ─────────────────────────────────────────────

-- SELECT: Team members of the match's team can read all RSVPs
DROP POLICY IF EXISTS cs_dinner_rsvps_select ON public.cs_dinner_rsvps;
CREATE POLICY cs_dinner_rsvps_select ON public.cs_dinner_rsvps
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.cs_matches m
       WHERE m.id = match_id
         AND public.is_team_member(m.team_id)
    )
  );

-- INSERT: Only the user themselves, and only if team member
DROP POLICY IF EXISTS cs_dinner_rsvps_insert ON public.cs_dinner_rsvps;
CREATE POLICY cs_dinner_rsvps_insert ON public.cs_dinner_rsvps
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.cs_matches m
       WHERE m.id = match_id
         AND public.is_team_member(m.team_id)
    )
  );

-- UPDATE: Only own RSVP, only if team member
DROP POLICY IF EXISTS cs_dinner_rsvps_update ON public.cs_dinner_rsvps;
CREATE POLICY cs_dinner_rsvps_update ON public.cs_dinner_rsvps
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.cs_matches m
       WHERE m.id = match_id
         AND public.is_team_member(m.team_id)
    )
  );

-- DELETE: Own RSVP only (optional, for completeness)
DROP POLICY IF EXISTS cs_dinner_rsvps_delete ON public.cs_dinner_rsvps;
CREATE POLICY cs_dinner_rsvps_delete ON public.cs_dinner_rsvps
  FOR DELETE
  USING (user_id = auth.uid());

-- ─────────────────────────────────────────────
-- 5. Verify (run after applying)
-- ─────────────────────────────────────────────

-- SELECT relname, relrowsecurity
--   FROM pg_class
--  WHERE relname = 'cs_dinner_rsvps';

-- SELECT schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check
--   FROM pg_policies
--  WHERE tablename = 'cs_dinner_rsvps'
--  ORDER BY policyname;
