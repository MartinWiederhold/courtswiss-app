-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Push-Ready Pipeline (DB-first, no actual push)  ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                 ║
-- ║                                                               ║
-- ║  1. cs_device_tokens   – FCM/APNs tokens per user/device     ║
-- ║  2. cs_notification_prefs – global + per-team push prefs      ║
-- ║  3. cs_event_deliveries   – fanout queue (pending/sent/…)     ║
-- ║  4. Fanout trigger on cs_events INSERT                        ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. cs_device_tokens
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_device_tokens (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   timestamptz NOT NULL    DEFAULT now(),
  updated_at   timestamptz NOT NULL    DEFAULT now(),
  user_id      uuid        NOT NULL    REFERENCES auth.users(id) ON DELETE CASCADE,
  platform     text        NOT NULL    CHECK (platform IN ('ios','android')),
  token        text        NOT NULL,
  device_id    text        NOT NULL,
  enabled      boolean     NOT NULL    DEFAULT true,
  last_seen_at timestamptz NOT NULL    DEFAULT now(),
  UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_cs_device_tokens_user
  ON public.cs_device_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_cs_device_tokens_token
  ON public.cs_device_tokens (token);

-- Auto-update updated_at on every change
CREATE OR REPLACE FUNCTION fn_cs_device_tokens_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cs_device_tokens_updated_at ON public.cs_device_tokens;
CREATE TRIGGER trg_cs_device_tokens_updated_at
  BEFORE UPDATE ON public.cs_device_tokens
  FOR EACH ROW
  EXECUTE FUNCTION fn_cs_device_tokens_updated_at();

-- RLS
ALTER TABLE public.cs_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_device_tokens_select ON public.cs_device_tokens;
CREATE POLICY cs_device_tokens_select ON public.cs_device_tokens
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_device_tokens_insert ON public.cs_device_tokens;
CREATE POLICY cs_device_tokens_insert ON public.cs_device_tokens
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS cs_device_tokens_update ON public.cs_device_tokens;
CREATE POLICY cs_device_tokens_update ON public.cs_device_tokens
  FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_device_tokens_delete ON public.cs_device_tokens;
CREATE POLICY cs_device_tokens_delete ON public.cs_device_tokens
  FOR DELETE USING (user_id = auth.uid());

-- RPC: cs_upsert_device_token
DROP FUNCTION IF EXISTS public.cs_upsert_device_token(text, text, text, boolean);
CREATE OR REPLACE FUNCTION public.cs_upsert_device_token(
  p_platform  text,
  p_token     text,
  p_device_id text,
  p_enabled   boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_device_tokens
    (user_id, platform, token, device_id, enabled, last_seen_at, updated_at)
  VALUES
    (auth.uid(), p_platform, p_token, p_device_id, p_enabled, now(), now())
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    token        = EXCLUDED.token,
    platform     = EXCLUDED.platform,
    enabled      = EXCLUDED.enabled,
    last_seen_at = now(),
    updated_at   = now();
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_upsert_device_token(text, text, text, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  2. cs_notification_prefs
--     Global row: team_id IS NULL
--     Team override: team_id = <uuid>
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_notification_prefs (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  team_id         uuid                 REFERENCES public.cs_teams(id) ON DELETE CASCADE,
  push_enabled    boolean     NOT NULL DEFAULT true,
  types_disabled  text[]      NOT NULL DEFAULT '{}'::text[]
);

-- Functional unique index – handles NULL team_id correctly
-- (Postgres UNIQUE constraint treats each NULL as distinct)
CREATE UNIQUE INDEX IF NOT EXISTS idx_cs_notification_prefs_user_team
  ON public.cs_notification_prefs (
    user_id,
    COALESCE(team_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

CREATE INDEX IF NOT EXISTS idx_cs_notification_prefs_user
  ON public.cs_notification_prefs (user_id);

CREATE INDEX IF NOT EXISTS idx_cs_notification_prefs_team
  ON public.cs_notification_prefs (team_id);

-- RLS
ALTER TABLE public.cs_notification_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_notification_prefs_select ON public.cs_notification_prefs;
CREATE POLICY cs_notification_prefs_select ON public.cs_notification_prefs
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_notification_prefs_insert ON public.cs_notification_prefs;
CREATE POLICY cs_notification_prefs_insert ON public.cs_notification_prefs
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS cs_notification_prefs_update ON public.cs_notification_prefs;
CREATE POLICY cs_notification_prefs_update ON public.cs_notification_prefs
  FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_notification_prefs_delete ON public.cs_notification_prefs;
CREATE POLICY cs_notification_prefs_delete ON public.cs_notification_prefs
  FOR DELETE USING (user_id = auth.uid());

-- RPC: cs_get_notification_prefs
-- Returns the prefs row for given team (or global when p_team_id is null).
-- Falls back to defaults if no row exists.
DROP FUNCTION IF EXISTS public.cs_get_notification_prefs(uuid);
CREATE OR REPLACE FUNCTION public.cs_get_notification_prefs(
  p_team_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
BEGIN
  SELECT jsonb_build_object(
    'user_id',        np.user_id,
    'team_id',        np.team_id,
    'push_enabled',   np.push_enabled,
    'types_disabled', np.types_disabled
  ) INTO v_row
  FROM public.cs_notification_prefs np
  WHERE np.user_id = auth.uid()
    AND (
      (p_team_id IS NULL     AND np.team_id IS NULL) OR
      (p_team_id IS NOT NULL AND np.team_id = p_team_id)
    );

  -- Return defaults if no row found
  IF v_row IS NULL THEN
    v_row := jsonb_build_object(
      'user_id',        auth.uid(),
      'team_id',        p_team_id,
      'push_enabled',   true,
      'types_disabled', '[]'::jsonb
    );
  END IF;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_get_notification_prefs(uuid) TO authenticated;

-- RPC: cs_set_notification_prefs
DROP FUNCTION IF EXISTS public.cs_set_notification_prefs(uuid, boolean, text[]);
CREATE OR REPLACE FUNCTION public.cs_set_notification_prefs(
  p_team_id         uuid     DEFAULT NULL,
  p_push_enabled    boolean  DEFAULT true,
  p_types_disabled  text[]   DEFAULT '{}'::text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_notification_prefs
    (user_id, team_id, push_enabled, types_disabled)
  VALUES
    (auth.uid(), p_team_id, p_push_enabled, p_types_disabled)
  ON CONFLICT (
    user_id,
    COALESCE(team_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) DO UPDATE SET
    push_enabled   = EXCLUDED.push_enabled,
    types_disabled = EXCLUDED.types_disabled;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_set_notification_prefs(uuid, boolean, text[]) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  3. cs_event_deliveries
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_event_deliveries (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   timestamptz NOT NULL    DEFAULT now(),
  event_id     uuid        NOT NULL    REFERENCES public.cs_events(id) ON DELETE CASCADE,
  user_id      uuid        NOT NULL    REFERENCES auth.users(id) ON DELETE CASCADE,
  channel      text        NOT NULL    DEFAULT 'push'
                                       CHECK (channel IN ('push')),
  status       text        NOT NULL    DEFAULT 'pending'
                                       CHECK (status IN ('pending','sent','failed','skipped')),
  attempts     int         NOT NULL    DEFAULT 0,
  last_error   text,
  processed_at timestamptz,
  UNIQUE (event_id, user_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_cs_event_deliveries_status_created
  ON public.cs_event_deliveries (status, created_at);

CREATE INDEX IF NOT EXISTS idx_cs_event_deliveries_user_status
  ON public.cs_event_deliveries (user_id, status);

-- RLS: read-only for the user (debug); no public insert/update
ALTER TABLE public.cs_event_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_event_deliveries_select ON public.cs_event_deliveries;
CREATE POLICY cs_event_deliveries_select ON public.cs_event_deliveries
  FOR SELECT USING (user_id = auth.uid());

-- No INSERT/UPDATE/DELETE policies → only service_role or triggers can write.

-- ═══════════════════════════════════════════════════════════════════
--  4. FANOUT TRIGGER – cs_events INSERT → cs_event_deliveries
--
--     For each new event, determines recipients and evaluates
--     their notification preferences to set delivery status
--     ('pending' or 'skipped').
--
--     - recipient_user_id set   → single user
--     - recipient_user_id null  → all team members with a user_id
--
--     Uses SECURITY DEFINER to bypass RLS on cs_event_deliveries.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_cs_event_fanout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user     record;
  v_prefs    record;
  v_status   text;
BEGIN
  -- Loop over recipients
  FOR v_user IN
    SELECT DISTINCT tm.user_id
    FROM public.cs_team_members tm
    WHERE tm.team_id = NEW.team_id
      AND tm.user_id IS NOT NULL
      AND (
        NEW.recipient_user_id IS NULL           -- broadcast
        OR tm.user_id = NEW.recipient_user_id   -- targeted
      )
      -- Skip the actor (created_by) – they don't need a push about
      -- their own action. Remove this line if self-notifications wanted.
      AND (NEW.created_by IS NULL OR tm.user_id <> NEW.created_by)
  LOOP
    -- Evaluate preferences: team-specific first, then global fallback
    SELECT np.push_enabled, np.types_disabled
    INTO v_prefs
    FROM public.cs_notification_prefs np
    WHERE np.user_id = v_user.user_id
      AND np.team_id = NEW.team_id;

    IF NOT FOUND THEN
      -- Global prefs
      SELECT np.push_enabled, np.types_disabled
      INTO v_prefs
      FROM public.cs_notification_prefs np
      WHERE np.user_id = v_user.user_id
        AND np.team_id IS NULL;
    END IF;

    -- Determine status
    IF v_prefs IS NOT NULL
       AND (
         v_prefs.push_enabled = false
         OR NEW.event_type = ANY(v_prefs.types_disabled)
       )
    THEN
      v_status := 'skipped';
    ELSE
      v_status := 'pending';
    END IF;

    -- Insert delivery row
    INSERT INTO public.cs_event_deliveries
      (event_id, user_id, channel, status)
    VALUES
      (NEW.id, v_user.user_id, 'push', v_status)
    ON CONFLICT (event_id, user_id, channel) DO NOTHING;

  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cs_event_fanout ON public.cs_events;
CREATE TRIGGER trg_cs_event_fanout
  AFTER INSERT ON public.cs_events
  FOR EACH ROW
  EXECUTE FUNCTION fn_cs_event_fanout();

-- ═══════════════════════════════════════════════════════════════════
--  5. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
