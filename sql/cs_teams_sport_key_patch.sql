-- ═══════════════════════════════════════════════════════════════
-- Teams Sport Key Patch – add sport_key to cs_teams
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'cs_teams'
       AND column_name  = 'sport_key'
  ) THEN
    ALTER TABLE public.cs_teams
      ADD COLUMN sport_key text NULL;
  END IF;
END
$$;

-- Optional: verify
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_name = 'cs_teams' AND column_name = 'sport_key';
