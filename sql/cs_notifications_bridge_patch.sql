-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Notifications Bridge & Missing Triggers         ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                 ║
-- ║                                                                ║
-- ║  Adds:                                                         ║
-- ║  1. cs_notifications table (if not exists)                     ║
-- ║  2. Bridge trigger: cs_event_deliveries INSERT → cs_notifications║
-- ║     So NotificationService Realtime subscription picks up      ║
-- ║     ALL business events (availability, dinner, carpool, etc.)  ║
-- ║  3. Sub-request declined → captain notification event          ║
-- ║  4. Sub-request declined → next candidate auto-request         ║
-- ║                                                                ║
-- ║  Depends on:                                                   ║
-- ║  - cs_events_patch.sql                                         ║
-- ║  - cs_push_pipeline_patch.sql                                  ║
-- ║  - cs_business_notifications_patch.sql                         ║
-- ║  - cs_business_notifications_v2_patch.sql                      ║
-- ║  - cs_sub_requests_patch.sql                                   ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  1. ENSURE cs_notifications TABLE EXISTS
--     (may already exist from earlier migrations)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_notifications (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at        timestamptz NOT NULL    DEFAULT now(),
  recipient_user_id uuid        NOT NULL    REFERENCES auth.users(id) ON DELETE CASCADE,
  type              text,
  title             text,
  body              text,
  payload           jsonb       NOT NULL    DEFAULT '{}'::jsonb,
  match_id          uuid                    REFERENCES public.cs_matches(id) ON DELETE SET NULL,
  team_id           uuid                    REFERENCES public.cs_teams(id)   ON DELETE SET NULL,
  read_at           timestamptz
);

CREATE INDEX IF NOT EXISTS idx_cs_notifications_recipient_created
  ON public.cs_notifications (recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cs_notifications_recipient_unread
  ON public.cs_notifications (recipient_user_id)
  WHERE read_at IS NULL;

-- RLS
ALTER TABLE public.cs_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_notifications_select ON public.cs_notifications;
CREATE POLICY cs_notifications_select ON public.cs_notifications
  FOR SELECT USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS cs_notifications_update ON public.cs_notifications;
CREATE POLICY cs_notifications_update ON public.cs_notifications
  FOR UPDATE USING (recipient_user_id = auth.uid());

-- RPC: mark_notification_read (idempotent)
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cs_notifications
  SET read_at = now()
  WHERE id = p_notification_id
    AND recipient_user_id = auth.uid()
    AND read_at IS NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  2. BRIDGE TRIGGER: cs_event_deliveries INSERT → cs_notifications
--
--     When a new delivery row is inserted with status='pending',
--     create a matching cs_notifications row so the Realtime
--     subscription in the Flutter app picks it up immediately.
--
--     This bridges the push pipeline (cs_events→cs_event_deliveries)
--     with the in-app Realtime notification system (cs_notifications).
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_bridge_delivery_to_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event record;
BEGIN
  -- Only bridge pending deliveries (not skipped)
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  -- Load the source event
  SELECT e.event_type, e.title, e.body, e.payload,
         e.match_id, e.team_id
  INTO v_event
  FROM public.cs_events e
  WHERE e.id = NEW.event_id;

  IF v_event IS NULL THEN
    RETURN NEW;
  END IF;

  -- Insert into cs_notifications for Realtime pickup
  INSERT INTO public.cs_notifications
    (recipient_user_id, type, title, body, payload, match_id, team_id)
  VALUES (
    NEW.user_id,
    v_event.event_type,
    v_event.title,
    v_event.body,
    v_event.payload,
    v_event.match_id,
    v_event.team_id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bridge_delivery_to_notification ON public.cs_event_deliveries;
CREATE TRIGGER trg_bridge_delivery_to_notification
  AFTER INSERT ON public.cs_event_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION fn_bridge_delivery_to_notification();


-- ═══════════════════════════════════════════════════════════════════
--  3. UPDATED: cs_respond_sub_request
--     Now also:
--     a) Creates a captain notification when substitute DECLINES
--     b) Automatically creates the next sub_request for the next
--        available candidate when declined (chain logic)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_respond_sub_request(
  p_request_id uuid,
  p_response   text   -- 'accepted' or 'declined'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req              record;
  v_slot_id          uuid;
  v_sub_name         text;
  v_original_name    text;
  v_captain_uid      uuid;
  v_next_candidate   uuid;
  v_next_name        text;
  v_next_request_id  uuid;
BEGIN
  IF p_response NOT IN ('accepted', 'declined') THEN
    RAISE EXCEPTION 'Invalid response: %. Must be accepted or declined.', p_response;
  END IF;

  -- 1. Load and lock the request
  SELECT * INTO v_req
  FROM public.cs_sub_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Sub request not found: %', p_request_id;
  END IF;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'not_pending',
      'message', 'Anfrage ist nicht mehr offen (Status: ' || v_req.status || ')'
    );
  END IF;

  -- Verify the caller is the substitute
  IF v_req.substitute_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the substitute can respond to this request';
  END IF;

  -- Resolve names
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_sub_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_req.team_id AND tp.claimed_by = v_req.substitute_user_id
  LIMIT 1;

  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_original_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_req.team_id AND tp.claimed_by = v_req.original_user_id
  LIMIT 1;

  -- 2. Update the request status
  UPDATE public.cs_sub_requests
  SET status       = p_response,
      responded_at = now()
  WHERE id = p_request_id;

  -- 3. Find captain for notifications
  SELECT tm.user_id INTO v_captain_uid
  FROM public.cs_team_members tm
  WHERE tm.team_id = v_req.team_id
    AND tm.role = 'captain'
  LIMIT 1;

  IF v_captain_uid IS NULL THEN
    SELECT t.created_by INTO v_captain_uid
    FROM public.cs_teams t
    WHERE t.id = v_req.team_id;
  END IF;

  IF p_response = 'accepted' THEN
    -- ── ACCEPTED ──────────────────────────────────────────────
    -- Find the slot of the original user (starter)
    SELECT ls.id INTO v_slot_id
    FROM public.cs_match_lineup_slots ls
    WHERE ls.match_id = v_req.match_id
      AND ls.user_id  = v_req.original_user_id
    LIMIT 1;

    IF v_slot_id IS NOT NULL THEN
      -- Swap the user in the lineup slot
      UPDATE public.cs_match_lineup_slots
      SET user_id = v_req.substitute_user_id
      WHERE id = v_slot_id;
    END IF;

    -- Broadcast event: substitute accepted
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by,
       recipient_filter)
    VALUES (
      v_req.team_id,
      v_req.match_id,
      'sub_accepted',
      'Ersatz bestätigt',
      coalesce(v_sub_name, '?') || ' ersetzt ' || coalesce(v_original_name, '?'),
      jsonb_build_object(
        'team_id', v_req.team_id,
        'match_id', v_req.match_id,
        'request_id', p_request_id,
        'substitute_user_id', v_req.substitute_user_id,
        'original_user_id', v_req.original_user_id,
        'substitute_name', coalesce(v_sub_name, '?'),
        'original_name', coalesce(v_original_name, '?')
      ),
      auth.uid(),
      'captain'
    );

    RETURN jsonb_build_object(
      'success', true,
      'action', 'accepted',
      'slot_updated', v_slot_id IS NOT NULL
    );

  ELSE
    -- ── DECLINED ──────────────────────────────────────────────

    -- 4a. Notify captain about the decline
    IF v_captain_uid IS NOT NULL THEN
      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload,
         created_by, recipient_user_id, recipient_filter)
      VALUES (
        v_req.team_id,
        v_req.match_id,
        'sub_declined',
        'Ersatz abgelehnt',
        coalesce(v_sub_name, '?') || ' hat die Ersatzanfrage abgelehnt'
          || ' (für ' || coalesce(v_original_name, '?') || ')',
        jsonb_build_object(
          'team_id', v_req.team_id,
          'match_id', v_req.match_id,
          'request_id', p_request_id,
          'substitute_user_id', v_req.substitute_user_id,
          'original_user_id', v_req.original_user_id,
          'substitute_name', coalesce(v_sub_name, '?'),
          'original_name', coalesce(v_original_name, '?')
        ),
        auth.uid(),
        v_captain_uid,
        'captain'
      );
    END IF;

    -- 4b. Auto-find next substitute candidate
    SELECT tp.claimed_by INTO v_next_candidate
    FROM public.cs_team_players tp
    JOIN public.cs_team_members tm
      ON tm.team_id = v_req.team_id AND tm.user_id = tp.claimed_by
    WHERE tp.team_id = v_req.team_id
      AND tp.claimed_by IS NOT NULL
      AND tp.claimed_by <> v_req.original_user_id
      -- Not already a starter in this match
      AND NOT EXISTS (
        SELECT 1 FROM public.cs_match_lineup_slots ls
        WHERE ls.match_id = v_req.match_id
          AND ls.user_id  = tp.claimed_by
          AND ls.slot_type = 'starter'
      )
      -- Not already asked (pending/accepted) or the current decliner
      AND NOT EXISTS (
        SELECT 1 FROM public.cs_sub_requests sr
        WHERE sr.match_id           = v_req.match_id
          AND sr.substitute_user_id = tp.claimed_by
          AND sr.status IN ('pending', 'accepted', 'declined')
      )
      -- Has availability 'yes' or has not responded yet
      AND (
        EXISTS (
          SELECT 1 FROM public.cs_match_availability ma
          WHERE ma.match_id = v_req.match_id
            AND ma.user_id  = tp.claimed_by
            AND ma.status   = 'yes'
        )
        OR NOT EXISTS (
          SELECT 1 FROM public.cs_match_availability ma
          WHERE ma.match_id = v_req.match_id
            AND ma.user_id  = tp.claimed_by
        )
      )
    ORDER BY tp.ranking ASC NULLS LAST
    LIMIT 1;

    IF v_next_candidate IS NOT NULL THEN
      -- Get next candidate name
      SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_next_name
      FROM public.cs_team_players tp
      WHERE tp.team_id = v_req.team_id AND tp.claimed_by = v_next_candidate
      LIMIT 1;

      -- Create the next sub request
      INSERT INTO public.cs_sub_requests
        (match_id, team_id, original_user_id, substitute_user_id, status)
      VALUES
        (v_req.match_id, v_req.team_id, v_req.original_user_id, v_next_candidate, 'pending')
      RETURNING id INTO v_next_request_id;

      -- Notify the next substitute candidate
      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload,
         recipient_user_id, created_by)
      VALUES (
        v_req.team_id,
        v_req.match_id,
        'sub_request',
        'Ersatzanfrage',
        'Du wurdest als Ersatz angefragt für ' || coalesce(v_original_name, '?'),
        jsonb_build_object(
          'team_id', v_req.team_id,
          'match_id', v_req.match_id,
          'request_id', v_next_request_id,
          'original_user_id', v_req.original_user_id,
          'original_name', coalesce(v_original_name, '?')
        ),
        v_next_candidate,
        auth.uid()
      );

      -- Notify captain about auto-chain
      IF v_captain_uid IS NOT NULL THEN
        INSERT INTO public.cs_events
          (team_id, match_id, event_type, title, body, payload,
           created_by, recipient_user_id, recipient_filter)
        VALUES (
          v_req.team_id,
          v_req.match_id,
          'sub_chain_next',
          'Nächster Ersatz angefragt',
          coalesce(v_next_name, '?') || ' wurde als nächster Ersatz angefragt'
            || ' (für ' || coalesce(v_original_name, '?') || ')',
          jsonb_build_object(
            'team_id', v_req.team_id,
            'match_id', v_req.match_id,
            'next_substitute_name', coalesce(v_next_name, '?'),
            'original_name', coalesce(v_original_name, '?'),
            'declined_name', coalesce(v_sub_name, '?')
          ),
          auth.uid(),
          v_captain_uid,
          'captain'
        );
      END IF;

      RETURN jsonb_build_object(
        'success', true,
        'action', 'declined',
        'next_candidate', v_next_candidate,
        'next_candidate_name', coalesce(v_next_name, '?'),
        'next_request_id', v_next_request_id,
        'message', coalesce(v_sub_name, '?') || ' hat abgelehnt. '
                   || coalesce(v_next_name, '?') || ' wurde automatisch angefragt.'
      );
    ELSE
      -- No more candidates available
      IF v_captain_uid IS NOT NULL THEN
        INSERT INTO public.cs_events
          (team_id, match_id, event_type, title, body, payload,
           created_by, recipient_user_id, recipient_filter)
        VALUES (
          v_req.team_id,
          v_req.match_id,
          'no_reserve_available',
          'Kein Ersatz verfügbar',
          coalesce(v_sub_name, '?') || ' hat abgelehnt – kein weiterer Ersatz verfügbar'
            || ' (für ' || coalesce(v_original_name, '?') || ')',
          jsonb_build_object(
            'team_id', v_req.team_id,
            'match_id', v_req.match_id,
            'absent_name', coalesce(v_original_name, '?'),
            'declined_name', coalesce(v_sub_name, '?')
          ),
          auth.uid(),
          v_captain_uid,
          'captain'
        );
      END IF;

      RETURN jsonb_build_object(
        'success', true,
        'action', 'declined',
        'message', 'Ersatzanfrage wurde abgelehnt. Kein weiterer Ersatzspieler verfügbar.'
      );
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cs_respond_sub_request(uuid, text) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  4. ENABLE SUPABASE REALTIME on tables used by Flutter Realtime
--     subscriptions. Without this, onPostgresChanges() won't fire.
--
--     Required for:
--       cs_notifications       → NotificationService.subscribe()
--       cs_match_lineups       → auto-refresh lineup status (draft→published)
--       cs_match_lineup_slots  → auto-refresh lineup slots
--       cs_match_availability  → auto-refresh availability changes
--       cs_carpool_offers      → auto-refresh carpool offers
--       cs_carpool_passengers  → auto-refresh carpool passengers
--       cs_dinner_rsvps        → auto-refresh dinner RSVPs
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'cs_notifications',
    'cs_match_lineups',
    'cs_match_lineup_slots',
    'cs_match_availability',
    'cs_carpool_offers',
    'cs_carpool_passengers',
    'cs_dinner_rsvps'
  ]
  LOOP
    -- Only add if not already in the publication
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname   = 'supabase_realtime'
         AND tablename = t
         AND schemaname = 'public'
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t
      );
      RAISE NOTICE 'Added %.% to supabase_realtime publication', 'public', t;
    END IF;
  END LOOP;
END
$$;


-- ═══════════════════════════════════════════════════════════════════
--  5. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
