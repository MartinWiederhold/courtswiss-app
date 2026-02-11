-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Match Events & Notification Inbox (DB-first)     ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                  ║
-- ║                                                                ║
-- ║  Test-Flow:                                                    ║
-- ║  1. Publish lineup → cs_events broadcast created automatically ║
-- ║  2. Open Inbox on other device → event visible, unread         ║
-- ║  3. Tap → marked as read (cs_event_reads row)                  ║
-- ║  4. Absage (availability 'no') → auto-promotion trigger fires  ║
-- ║     → cs_lineup_events row inserted → trigger mirrors to       ║
-- ║       cs_events (broadcast + targeted to promoted player)      ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. TABLES
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_events (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at        timestamptz NOT NULL    DEFAULT now(),
  team_id           uuid        NOT NULL    REFERENCES public.cs_teams(id) ON DELETE CASCADE,
  match_id          uuid                    REFERENCES public.cs_matches(id) ON DELETE CASCADE,
  event_type        text        NOT NULL,
  title             text        NOT NULL,
  body              text,
  payload           jsonb       NOT NULL    DEFAULT '{}'::jsonb,
  recipient_user_id uuid                    REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by        uuid                    REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.cs_event_reads (
  event_id  uuid        NOT NULL REFERENCES public.cs_events(id) ON DELETE CASCADE,
  user_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);

-- ═══════════════════════════════════════════════════════════════════
--  2. INDEXES
-- ═══════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_cs_events_team_created
  ON public.cs_events (team_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cs_events_match_created
  ON public.cs_events (match_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cs_events_recipient_created
  ON public.cs_events (recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cs_event_reads_user_read
  ON public.cs_event_reads (user_id, read_at DESC);

-- ═══════════════════════════════════════════════════════════════════
--  3. ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.cs_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_event_reads  ENABLE ROW LEVEL SECURITY;

-- ── cs_events ────────────────────────────────────────────────────

DROP POLICY IF EXISTS cs_events_select ON public.cs_events;
CREATE POLICY cs_events_select ON public.cs_events
  FOR SELECT USING (
    public.is_team_member(team_id)
    AND (recipient_user_id IS NULL OR recipient_user_id = auth.uid())
  );

DROP POLICY IF EXISTS cs_events_insert ON public.cs_events;
CREATE POLICY cs_events_insert ON public.cs_events
  FOR INSERT WITH CHECK (
    public.is_team_admin(team_id) OR public.is_team_creator(team_id)
  );

DROP POLICY IF EXISTS cs_events_delete ON public.cs_events;
CREATE POLICY cs_events_delete ON public.cs_events
  FOR DELETE USING (
    public.is_team_admin(team_id) OR public.is_team_creator(team_id)
  );

-- ── cs_event_reads ───────────────────────────────────────────────

DROP POLICY IF EXISTS cs_event_reads_select ON public.cs_event_reads;
CREATE POLICY cs_event_reads_select ON public.cs_event_reads
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_event_reads_insert ON public.cs_event_reads;
CREATE POLICY cs_event_reads_insert ON public.cs_event_reads
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.cs_events e
      WHERE e.id = event_id
        AND public.is_team_member(e.team_id)
        AND (e.recipient_user_id IS NULL OR e.recipient_user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS cs_event_reads_delete ON public.cs_event_reads;
CREATE POLICY cs_event_reads_delete ON public.cs_event_reads
  FOR DELETE USING (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════
--  4. RPCs
-- ═══════════════════════════════════════════════════════════════════

-- 4a. Mark a single event as read
DROP FUNCTION IF EXISTS public.cs_mark_event_read(uuid);
CREATE OR REPLACE FUNCTION public.cs_mark_event_read(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, read_at)
  VALUES (p_event_id, auth.uid(), now())
  ON CONFLICT (event_id, user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_mark_event_read(uuid) TO authenticated;

-- 4b. Mark ALL visible events as read (for "Alle gelesen" button)
DROP FUNCTION IF EXISTS public.cs_mark_all_events_read();
CREATE OR REPLACE FUNCTION public.cs_mark_all_events_read()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, read_at)
  SELECT e.id, auth.uid(), now()
  FROM public.cs_events e
  WHERE public.is_team_member(e.team_id)
    AND (e.recipient_user_id IS NULL OR e.recipient_user_id = auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.cs_event_reads er
      WHERE er.event_id = e.id AND er.user_id = auth.uid()
    )
  ON CONFLICT (event_id, user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_mark_all_events_read() TO authenticated;

-- 4c. Unread event count (used by badge)
DROP FUNCTION IF EXISTS public.cs_unread_event_count();
CREATE OR REPLACE FUNCTION public.cs_unread_event_count()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT count(*)::int
  FROM public.cs_events e
  WHERE public.is_team_member(e.team_id)
    AND (e.recipient_user_id IS NULL OR e.recipient_user_id = auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.cs_event_reads er
      WHERE er.event_id = e.id AND er.user_id = auth.uid()
    );
$$;
GRANT EXECUTE ON FUNCTION public.cs_unread_event_count() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  5. TRIGGERS – Automatic cs_events emission
--     (no existing RPCs are modified – zero-risk approach)
-- ═══════════════════════════════════════════════════════════════════

-- 5a. Lineup published → broadcast cs_events entry
--     Fires when cs_match_lineups.status transitions to 'published'.
CREATE OR REPLACE FUNCTION fn_emit_lineup_published_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opponent text;
BEGIN
  IF NEW.status = 'published'
     AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'published')
  THEN
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by)
    VALUES (
      NEW.team_id,
      NEW.match_id,
      'lineup_published',
      'Aufstellung veröffentlicht',
      'Die Aufstellung für ' || coalesce(v_opponent, '?') || ' ist online.',
      jsonb_build_object('match_id', NEW.match_id),
      NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_lineup_published_event ON public.cs_match_lineups;
CREATE TRIGGER trg_emit_lineup_published_event
  AFTER UPDATE ON public.cs_match_lineups
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_lineup_published_event();

-- 5b. Auto-promotion / no-reserve audit events → cs_events
--     Fires when a row is inserted into cs_lineup_events with
--     event_type = 'auto_promotion' or 'no_reserve'.
CREATE OR REPLACE FUNCTION fn_emit_lineup_event_to_cs_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opponent     text;
  v_promoted_uid uuid;
  v_captain_uid  uuid;
BEGIN
  SELECT m.opponent INTO v_opponent
  FROM public.cs_matches m
  WHERE m.id = NEW.match_id;

  IF NEW.event_type = 'auto_promotion' THEN
    -- Broadcast: "{promoted_name} ersetzt {absent_name}"
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by)
    VALUES (
      NEW.team_id, NEW.match_id,
      'replacement_promoted',
      'Ersatz ist nachgerückt',
      coalesce(NEW.payload->>'promoted_name', '?')
        || ' ersetzt '
        || coalesce(NEW.payload->>'absent_name', '?'),
      NEW.payload,
      NEW.created_by
    );

    -- Targeted event to the promoted player
    v_promoted_uid := (NEW.payload->>'to')::uuid;
    IF v_promoted_uid IS NOT NULL THEN
      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload,
         recipient_user_id, created_by)
      VALUES (
        NEW.team_id, NEW.match_id,
        'replacement_promoted',
        'Du bist nachgerückt',
        'Du spielst nun im Match vs ' || coalesce(v_opponent, '?'),
        NEW.payload,
        v_promoted_uid,
        NEW.created_by
      );
    END IF;

  ELSIF NEW.event_type = 'no_reserve' THEN
    -- Targeted event to captain
    SELECT user_id INTO v_captain_uid
    FROM public.cs_team_members
    WHERE team_id = NEW.team_id AND role = 'captain'
    LIMIT 1;

    IF v_captain_uid IS NULL THEN
      SELECT created_by INTO v_captain_uid
      FROM public.cs_teams WHERE id = NEW.team_id;
    END IF;

    -- Broadcast (team-wide)
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by)
    VALUES (
      NEW.team_id, NEW.match_id,
      'no_reserve_available',
      'Kein Ersatz verfügbar',
      coalesce(NEW.payload->>'absent_name', '?')
        || ' hat abgesagt – kein Ersatz!',
      NEW.payload,
      NEW.created_by
    );

    -- Targeted to captain
    IF v_captain_uid IS NOT NULL THEN
      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload,
         recipient_user_id, created_by)
      VALUES (
        NEW.team_id, NEW.match_id,
        'no_reserve_available',
        'Kein Ersatz verfügbar',
        coalesce(NEW.payload->>'absent_name', '?')
          || ' hat abgesagt – kein Ersatz verfügbar!',
        NEW.payload,
        v_captain_uid,
        NEW.created_by
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_lineup_event_to_cs_events ON public.cs_lineup_events;
CREATE TRIGGER trg_emit_lineup_event_to_cs_events
  AFTER INSERT ON public.cs_lineup_events
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_lineup_event_to_cs_events();

-- ═══════════════════════════════════════════════════════════════════
--  6. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
