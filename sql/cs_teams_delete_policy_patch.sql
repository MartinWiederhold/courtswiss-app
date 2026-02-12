-- ═══════════════════════════════════════════════════════════════
-- cs_teams DELETE policy – allow creator to delete their own teams.
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════

-- Ensure RLS is enabled on cs_teams (idempotent).
ALTER TABLE public.cs_teams ENABLE ROW LEVEL SECURITY;

-- Drop + recreate to stay idempotent.
DROP POLICY IF EXISTS "cs_teams_delete_creator" ON public.cs_teams;

CREATE POLICY "cs_teams_delete_creator"
  ON public.cs_teams
  FOR DELETE
  USING (auth.uid() = created_by);

-- Also allow captains (team members with role = 'captain') to delete.
DROP POLICY IF EXISTS "cs_teams_delete_captain" ON public.cs_teams;

CREATE POLICY "cs_teams_delete_captain"
  ON public.cs_teams
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
        FROM public.cs_team_members
       WHERE cs_team_members.team_id = cs_teams.id
         AND cs_team_members.user_id = auth.uid()
         AND cs_team_members.role    = 'captain'
    )
  );
