-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Sub-Request Timeout (30 min default)            ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                 ║
-- ║                                                               ║
-- ║  Adds:                                                        ║
-- ║  1. expires_at column + backfill                              ║
-- ║  2. BEFORE INSERT trigger to set default expires_at           ║
-- ║  3. cs_expire_sub_requests() function                         ║
-- ║  4. pg_cron schedule (or manual alternative)                  ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. ADD COLUMN  expires_at
-- ═══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'cs_sub_requests'
      AND column_name  = 'expires_at'
  ) THEN
    ALTER TABLE public.cs_sub_requests
      ADD COLUMN expires_at timestamptz;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
--  2. BACKFILL  existing pending rows
-- ═══════════════════════════════════════════════════════════════════

UPDATE public.cs_sub_requests
SET expires_at = created_at + interval '30 minutes'
WHERE expires_at IS NULL;

-- ═══════════════════════════════════════════════════════════════════
--  3. INDEX  for expire job performance
-- ═══════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_cs_sub_requests_expire
  ON public.cs_sub_requests (status, expires_at)
  WHERE status = 'pending';

-- ═══════════════════════════════════════════════════════════════════
--  4. TRIGGER  set default expires_at on INSERT
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_sub_request_set_expires_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.expires_at IS NULL THEN
    NEW.expires_at := now() + interval '30 minutes';
  END IF;
  RETURN NEW;
END;
$$;

-- Drop + create to ensure idempotency
DROP TRIGGER IF EXISTS trg_cs_sub_request_set_expires_at
  ON public.cs_sub_requests;

CREATE TRIGGER trg_cs_sub_request_set_expires_at
  BEFORE INSERT ON public.cs_sub_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.cs_sub_request_set_expires_at();

-- ═══════════════════════════════════════════════════════════════════
--  5. FUNCTION  cs_expire_sub_requests
--     Idempotent: marks overdue pending requests as 'expired'.
--     Returns the number of rows affected.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_expire_sub_requests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.cs_sub_requests
  SET status       = 'expired',
      responded_at = now()
  WHERE status     = 'pending'
    AND expires_at IS NOT NULL
    AND expires_at < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Log if any rows were expired (visible in Supabase logs)
  IF v_count > 0 THEN
    RAISE LOG 'cs_expire_sub_requests: expired % request(s)', v_count;
  END IF;

  RETURN v_count;
END;
$$;

-- Grant execute so it can be called from the app or cron
GRANT EXECUTE ON FUNCTION public.cs_expire_sub_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cs_expire_sub_requests() TO service_role;

-- ═══════════════════════════════════════════════════════════════════
--  6. UPDATE cs_list_my_sub_requests to also check expiry
--     If the cron hasn't run yet, client-side we still want to
--     exclude expired-by-time requests from pending list.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_list_my_sub_requests()
RETURNS SETOF public.cs_sub_requests
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT *
  FROM public.cs_sub_requests
  WHERE substitute_user_id = auth.uid()
    AND status = 'pending'
    AND (expires_at IS NULL OR expires_at > now())
  ORDER BY created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.cs_list_my_sub_requests() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  7. pg_cron SCHEDULE  (requires pg_cron extension)
--     Run every 2 minutes to expire timed-out requests.
--
--     NOTE: pg_cron may not be available on all Supabase plans.
--     If this block fails, the function can be called manually or
--     via a Supabase Edge Function on a scheduled trigger:
--
--       // Edge Function (Deno/TypeScript):
--       // Schedule: every 2 minutes via Supabase Dashboard → Functions → Schedules
--       // Body:
--       //   import { createClient } from '@supabase/supabase-js'
--       //   const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
--       //   await sb.rpc('cs_expire_sub_requests')
--
-- ═══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  -- Only attempt if pg_cron extension is available
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Remove old job if it exists
    PERFORM cron.unschedule('cs_expire_sub_requests')
    WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'cs_expire_sub_requests'
    );

    -- Schedule: every 2 minutes
    PERFORM cron.schedule(
      'cs_expire_sub_requests',
      '*/2 * * * *',
      'SELECT public.cs_expire_sub_requests()'
    );

    RAISE NOTICE 'pg_cron job cs_expire_sub_requests scheduled (every 2 min)';
  ELSE
    RAISE NOTICE 'pg_cron not available – call cs_expire_sub_requests() '
                 'manually or via Edge Function scheduled trigger.';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
--  8. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
