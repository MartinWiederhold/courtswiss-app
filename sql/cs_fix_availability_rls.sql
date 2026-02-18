-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX 2: RLS-Policies für cs_match_availability                 ║
-- ║  ERST ausführen NACHDEM cs_fix_triggers_only.sql erfolgreich   ║
-- ║  war und Push-Benachrichtigungen wieder funktionieren!          ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- Helper-Funktionen sicherstellen
CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cs_team_members
    WHERE team_id = p_team_id AND user_id = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO anon;

-- RLS für cs_match_availability
ALTER TABLE public.cs_match_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_match_availability_select ON public.cs_match_availability;
CREATE POLICY cs_match_availability_select ON public.cs_match_availability
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.cs_matches m
            WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_insert ON public.cs_match_availability;
CREATE POLICY cs_match_availability_insert ON public.cs_match_availability
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m
                WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_update ON public.cs_match_availability;
CREATE POLICY cs_match_availability_update ON public.cs_match_availability
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m
                WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_delete ON public.cs_match_availability;
CREATE POLICY cs_match_availability_delete ON public.cs_match_availability
  FOR DELETE USING (user_id = auth.uid());

-- Diagnose
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_match_availability';
  RAISE NOTICE 'cs_match_availability hat jetzt % RLS-Policies (sollte 4 sein)', v_count;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
