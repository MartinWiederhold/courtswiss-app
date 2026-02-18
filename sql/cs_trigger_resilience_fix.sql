-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Trigger Resilience Fix                          ║
-- ║  Idempotent – safe to run multiple times.                     ║
-- ║                                                                ║
-- ║  Problem: When inserting/updating cs_match_availability or     ║
-- ║  cs_dinner_rsvps, AFTER triggers fire that INSERT into         ║
-- ║  cs_events → cs_event_deliveries → cs_notifications.           ║
-- ║  If any table in the chain is missing or a trigger fails,      ║
-- ║  the ENTIRE transaction is rolled back, blocking the original  ║
-- ║  availability/dinner operation.                                 ║
-- ║                                                                ║
-- ║  Fix:                                                          ║
-- ║  1. Ensure all required tables exist (CREATE TABLE IF NOT      ║
-- ║     EXISTS) so the trigger chain has valid targets.             ║
-- ║  2. Add EXCEPTION handlers to all notification trigger         ║
-- ║     functions so the core operation (availability, dinner)     ║
-- ║     always succeeds even if the notification pipeline fails.   ║
-- ║  3. Re-create cs_dinner_rsvps RLS policies (may have failed    ║
-- ║     previously when is_team_member() didn't exist).            ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  0a. CLEANUP: Remove old/conflicting triggers
--      The old cs_on_event_create_enqueue_push trigger on cs_events
--      tries to insert into cs_push_jobs with recipient_user_id.
--      Events using recipient_filter (like dinner/availability) have
--      recipient_user_id = NULL, which violates the NOT NULL constraint
--      on cs_push_jobs.user_id and causes the entire transaction to fail.
--      Our pipeline uses: cs_events → fn_cs_event_fanout → cs_event_deliveries
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_cs_events_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS trg_on_event_create_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS cs_on_event_create_enqueue_push ON public.cs_events;
DROP FUNCTION IF EXISTS public.cs_on_event_create_enqueue_push();

-- ═══════════════════════════════════════════════════════════════════
--  0b. PREREQUISITES: Ensure helper functions exist
--      (idempotent – same as cs_rls_helpers_and_expenses_fix.sql)
-- ═══════════════════════════════════════════════════════════════════

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
--  1. ENSURE ALL REQUIRED TABLES EXIST
--     These tables are needed by the trigger chain.
-- ═══════════════════════════════════════════════════════════════════

-- 1a. cs_events (core notification events table)
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
ALTER TABLE public.cs_events ENABLE ROW LEVEL SECURITY;

-- Ensure dedupe_key column exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'cs_events'
       AND column_name  = 'dedupe_key'
  ) THEN
    ALTER TABLE public.cs_events ADD COLUMN dedupe_key text;
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_cs_events_dedupe_key
  ON public.cs_events (dedupe_key)
  WHERE dedupe_key IS NOT NULL;

-- Ensure recipient_filter column exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'cs_events'
       AND column_name  = 'recipient_filter'
  ) THEN
    ALTER TABLE public.cs_events
      ADD COLUMN recipient_filter text NOT NULL DEFAULT 'team';
  END IF;
END
$$;

-- 1b. cs_notification_prefs
CREATE TABLE IF NOT EXISTS public.cs_notification_prefs (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at     timestamptz NOT NULL    DEFAULT now(),
  updated_at     timestamptz NOT NULL    DEFAULT now(),
  user_id        uuid        NOT NULL    REFERENCES auth.users(id) ON DELETE CASCADE,
  team_id        uuid                    REFERENCES public.cs_teams(id) ON DELETE CASCADE,
  push_enabled   boolean     NOT NULL    DEFAULT true,
  types_disabled text[]      NOT NULL    DEFAULT '{}',
  UNIQUE (user_id, team_id)
);
ALTER TABLE public.cs_notification_prefs ENABLE ROW LEVEL SECURITY;

-- 1c. cs_device_tokens
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
ALTER TABLE public.cs_device_tokens ENABLE ROW LEVEL SECURITY;

-- 1d. cs_event_deliveries
CREATE TABLE IF NOT EXISTS public.cs_event_deliveries (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   timestamptz NOT NULL    DEFAULT now(),
  event_id     uuid        NOT NULL    REFERENCES public.cs_events(id) ON DELETE CASCADE,
  user_id      uuid        NOT NULL    REFERENCES auth.users(id)       ON DELETE CASCADE,
  channel      text        NOT NULL    DEFAULT 'push',
  status       text        NOT NULL    DEFAULT 'pending',
  attempts     int         NOT NULL    DEFAULT 0,
  last_error   text,
  processed_at timestamptz,
  UNIQUE (event_id, user_id, channel)
);
ALTER TABLE public.cs_event_deliveries ENABLE ROW LEVEL SECURITY;

-- 1e. cs_notifications (for Realtime in-app notifications)
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
ALTER TABLE public.cs_notifications ENABLE ROW LEVEL SECURITY;

-- RLS for cs_notifications (idempotent)
DROP POLICY IF EXISTS cs_notifications_select ON public.cs_notifications;
CREATE POLICY cs_notifications_select ON public.cs_notifications
  FOR SELECT USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS cs_notifications_update ON public.cs_notifications;
CREATE POLICY cs_notifications_update ON public.cs_notifications
  FOR UPDATE USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS cs_notifications_insert ON public.cs_notifications;
CREATE POLICY cs_notifications_insert ON public.cs_notifications
  FOR INSERT WITH CHECK (true);  -- Trigger functions (SECURITY DEFINER) insert here

DROP POLICY IF EXISTS cs_notifications_delete ON public.cs_notifications;
CREATE POLICY cs_notifications_delete ON public.cs_notifications
  FOR DELETE USING (recipient_user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  2. RESILIENT TRIGGER: Availability Changed → cs_events
--     Now wraps the INSERT in an EXCEPTION handler so the
--     availability upsert always succeeds.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_emit_availability_changed_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id     uuid;
  v_opponent    text;
  v_player_name text;
  v_status_text text;
  v_title       text;
  v_body        text;
BEGIN
  -- No skip logic: captain gets notified on EVERY click,
  -- even if the status is the same as before.

  BEGIN
    -- Resolve team_id + opponent from the match
    SELECT m.team_id, m.opponent
    INTO v_team_id, v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    IF v_team_id IS NULL THEN
      RETURN NEW;
    END IF;

    -- Resolve player name
    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id
      AND tp.claimed_by = NEW.user_id
    LIMIT 1;

    -- Human-readable status
    v_status_text := CASE NEW.status
      WHEN 'yes'   THEN 'zugesagt'
      WHEN 'no'    THEN 'abgesagt'
      WHEN 'maybe' THEN 'unsicher'
      ELSE NEW.status
    END;

    v_title := 'Verfügbarkeit: ' || initcap(v_status_text);
    v_body  := coalesce(v_player_name, '?') || ' hat ' || v_status_text
               || CASE WHEN v_opponent IS NOT NULL
                    THEN ' (vs ' || v_opponent || ')'
                    ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_filter)
    VALUES (
      v_team_id,
      NEW.match_id,
      'availability_changed',
      v_title,
      v_body,
      jsonb_build_object(
        'team_id',     v_team_id,
        'match_id',    NEW.match_id,
        'user_id',     NEW.user_id,
        'status',      NEW.status,
        'player_name', coalesce(v_player_name, '?')
      ),
      NEW.user_id,
      'captain'
      -- No dedupe_key: captain gets notified on EVERY click
    );
  EXCEPTION WHEN OTHERS THEN
    -- Log but do NOT block the availability change
    RAISE WARNING 'fn_emit_availability_changed_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_availability_changed_event ON public.cs_match_availability;
CREATE TRIGGER trg_emit_availability_changed_event
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_availability_changed_event();


-- ═══════════════════════════════════════════════════════════════════
--  3. RESILIENT TRIGGER: Dinner RSVP → cs_events
--     Now wraps the INSERT in an EXCEPTION handler so the
--     dinner RSVP upsert always succeeds.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_emit_dinner_rsvp_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id     uuid;
  v_opponent    text;
  v_player_name text;
  v_status_text text;
  v_title       text;
  v_body        text;
BEGIN
  -- No skip logic: captain gets notified on EVERY click,
  -- even if the status is the same as before.

  BEGIN
    -- Resolve team_id + opponent from match
    SELECT m.team_id, m.opponent
    INTO v_team_id, v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    IF v_team_id IS NULL THEN
      RETURN NEW;
    END IF;

    -- Resolve player name
    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id
      AND tp.claimed_by = NEW.user_id
    LIMIT 1;

    -- Human-readable status
    v_status_text := CASE NEW.status
      WHEN 'yes'   THEN 'isst mit'
      WHEN 'no'    THEN 'isst nicht mit'
      WHEN 'maybe' THEN 'ist unsicher'
      ELSE NEW.status
    END;

    v_title := CASE NEW.status
      WHEN 'yes'   THEN 'Essen: Zusage'
      WHEN 'no'    THEN 'Essen: Absage'
      WHEN 'maybe' THEN 'Essen: Unsicher'
      ELSE 'Essen: ' || NEW.status
    END;

    v_body := coalesce(v_player_name, '?') || ' ' || v_status_text
              || CASE WHEN v_opponent IS NOT NULL
                   THEN ' (vs ' || v_opponent || ')'
                   ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_filter)
    VALUES (
      v_team_id,
      NEW.match_id,
      'dinner_rsvp',
      v_title,
      v_body,
      jsonb_build_object(
        'team_id',     v_team_id,
        'match_id',    NEW.match_id,
        'user_id',     NEW.user_id,
        'status',      NEW.status,
        'player_name', coalesce(v_player_name, '?')
      ),
      NEW.user_id,
      'captain'
      -- No dedupe_key: captain gets notified on EVERY click
    );
  EXCEPTION WHEN OTHERS THEN
    -- Log but do NOT block the dinner RSVP change
    RAISE WARNING 'fn_emit_dinner_rsvp_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_emit_dinner_rsvp_event
  AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_dinner_rsvp_event();


-- ═══════════════════════════════════════════════════════════════════
--  4. RESILIENT TRIGGER: Event Fanout (cs_events → cs_event_deliveries)
--     Adds EXCEPTION handler so cs_events INSERT succeeds even if
--     the delivery fanout fails.
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
  v_filter   text;
BEGIN
  BEGIN
    v_filter := coalesce(NEW.recipient_filter, 'team');

    FOR v_user IN
      SELECT DISTINCT x.user_id
      FROM (
        -- FILTER: lineup_starters
        SELECT ls.user_id
        FROM public.cs_match_lineup_slots ls
        WHERE v_filter = 'lineup_starters'
          AND NEW.match_id IS NOT NULL
          AND ls.match_id = NEW.match_id
          AND ls.slot_type = 'starter'
          AND ls.user_id IS NOT NULL

        UNION

        -- FILTER: team_no_reserves
        SELECT tm.user_id
        FROM public.cs_team_members tm
        WHERE v_filter = 'team_no_reserves'
          AND tm.team_id = NEW.team_id
          AND tm.user_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM public.cs_match_lineup_slots ls
            WHERE ls.match_id = NEW.match_id
              AND ls.user_id = tm.user_id
              AND ls.slot_type = 'reserve'
          )

        UNION

        -- FILTER: captain
        SELECT tm.user_id
        FROM public.cs_team_members tm
        WHERE v_filter = 'captain'
          AND tm.team_id = NEW.team_id
          AND tm.role = 'captain'
          AND tm.user_id IS NOT NULL

        UNION

        -- Captain fallback: team creator
        SELECT t.created_by
        FROM public.cs_teams t
        WHERE v_filter = 'captain'
          AND t.id = NEW.team_id
          AND t.created_by IS NOT NULL

        UNION

        -- FILTER: team (default)
        SELECT tm.user_id
        FROM public.cs_team_members tm
        WHERE v_filter = 'team'
          AND tm.team_id = NEW.team_id
          AND tm.user_id IS NOT NULL
      ) x
      WHERE (
        NEW.recipient_user_id IS NULL
        OR x.user_id = NEW.recipient_user_id
      )
      AND (NEW.created_by IS NULL OR x.user_id <> NEW.created_by)
    LOOP
      -- Evaluate preferences: team-specific first, then global fallback
      BEGIN
        SELECT np.push_enabled, np.types_disabled
        INTO v_prefs
        FROM public.cs_notification_prefs np
        WHERE np.user_id = v_user.user_id
          AND np.team_id = NEW.team_id;

        IF NOT FOUND THEN
          SELECT np.push_enabled, np.types_disabled
          INTO v_prefs
          FROM public.cs_notification_prefs np
          WHERE np.user_id = v_user.user_id
            AND np.team_id IS NULL;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_prefs := NULL;
      END;

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
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_cs_event_fanout failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Re-create trigger (idempotent)
DROP TRIGGER IF EXISTS trg_cs_event_fanout ON public.cs_events;
CREATE TRIGGER trg_cs_event_fanout
  AFTER INSERT ON public.cs_events
  FOR EACH ROW
  EXECUTE FUNCTION fn_cs_event_fanout();


-- ═══════════════════════════════════════════════════════════════════
--  5. RESILIENT TRIGGER: Bridge delivery → cs_notifications
--     Adds EXCEPTION handler so cs_event_deliveries INSERT succeeds
--     even if the notifications bridge fails.
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

  BEGIN
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
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_bridge_delivery_to_notification failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bridge_delivery_to_notification ON public.cs_event_deliveries;
CREATE TRIGGER trg_bridge_delivery_to_notification
  AFTER INSERT ON public.cs_event_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION fn_bridge_delivery_to_notification();


-- ═══════════════════════════════════════════════════════════════════
--  6. RESILIENT TRIGGER: Expense Created → cs_events
--     Same pattern: EXCEPTION handler to not block expense creation.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_emit_expense_created_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opponent text;
  v_payer_name text;
  v_amount_display text;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = NEW.team_id
      AND tp.claimed_by = NEW.paid_by_user_id
    LIMIT 1;

    v_amount_display := to_char(NEW.amount_cents / 100.0, 'FM999990.00')
                        || ' ' || NEW.currency;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_filter, dedupe_key)
    VALUES (
      NEW.team_id,
      NEW.match_id,
      'expense_added',
      'Neue Spese',
      coalesce(v_payer_name, '?') || ': '
        || NEW.title || ' – ' || v_amount_display,
      jsonb_build_object(
        'team_id',      NEW.team_id,
        'match_id',     NEW.match_id,
        'expense_id',   NEW.id,
        'title',        NEW.title,
        'amount_cents',  NEW.amount_cents,
        'currency',     NEW.currency,
        'payer_name',   coalesce(v_payer_name, '?')
      ),
      NEW.paid_by_user_id,
      'team',
      'expense_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_created_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_created_event ON public.cs_expenses;
CREATE TRIGGER trg_emit_expense_created_event
  AFTER INSERT ON public.cs_expenses
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_created_event();


-- ═══════════════════════════════════════════════════════════════════
--  7. RESILIENT TRIGGERS: Other business notification triggers
-- ═══════════════════════════════════════════════════════════════════

-- 7a. Carpool Passenger Joined → driver push
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_joined_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer        record;
  v_passenger_name text;
  v_opponent     text;
BEGIN
  BEGIN
    SELECT o.id, o.team_id, o.match_id, o.driver_user_id, o.seats_total
    INTO v_offer
    FROM public.cs_carpool_offers o
    WHERE o.id = NEW.offer_id;

    IF v_offer IS NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.passenger_user_id = v_offer.driver_user_id THEN
      RETURN NEW;
    END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_offer.team_id
      AND tp.claimed_by = NEW.passenger_user_id
    LIMIT 1;

    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_user_id, recipient_filter)
    VALUES (
      v_offer.team_id,
      v_offer.match_id,
      'carpool_passenger_joined',
      'Mitfahrer',
      coalesce(v_passenger_name, '?') || ' fährt mit'
        || CASE WHEN v_opponent IS NOT NULL
             THEN ' (vs ' || v_opponent || ')'
             ELSE '' END,
      jsonb_build_object(
        'team_id',        v_offer.team_id,
        'match_id',       v_offer.match_id,
        'offer_id',       v_offer.id,
        'passenger_name', coalesce(v_passenger_name, '?'),
        'user_id',        NEW.passenger_user_id
      ),
      NEW.passenger_user_id,
      v_offer.driver_user_id,
      'team'
      -- No dedupe_key: driver gets notified on EVERY join
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_joined_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_joined ON public.cs_carpool_passengers;
CREATE TRIGGER trg_emit_carpool_passenger_joined
  AFTER INSERT ON public.cs_carpool_passengers
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_carpool_passenger_joined_event();


-- 7a-2. Carpool Passenger Left → driver push
--       Fires on DELETE on cs_carpool_passengers.
--       Notifies the driver that someone left their ride.
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_left_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer          record;
  v_passenger_name text;
  v_opponent       text;
BEGIN
  BEGIN
    SELECT o.id, o.team_id, o.match_id, o.driver_user_id, o.seats_total
    INTO v_offer
    FROM public.cs_carpool_offers o
    WHERE o.id = OLD.offer_id;

    IF v_offer IS NULL THEN
      RETURN OLD;
    END IF;

    -- Don't notify if driver removes themselves (edge case)
    IF OLD.passenger_user_id = v_offer.driver_user_id THEN
      RETURN OLD;
    END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_offer.team_id
      AND tp.claimed_by = OLD.passenger_user_id
    LIMIT 1;

    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_user_id, recipient_filter)
    VALUES (
      v_offer.team_id,
      v_offer.match_id,
      'carpool_passenger_left',
      'Mitfahrer ausgestiegen',
      coalesce(v_passenger_name, '?') || ' fährt nicht mehr mit'
        || CASE WHEN v_opponent IS NOT NULL
             THEN ' (vs ' || v_opponent || ')'
             ELSE '' END,
      jsonb_build_object(
        'team_id',        v_offer.team_id,
        'match_id',       v_offer.match_id,
        'offer_id',       v_offer.id,
        'passenger_name', coalesce(v_passenger_name, '?'),
        'user_id',        OLD.passenger_user_id
      ),
      OLD.passenger_user_id,
      v_offer.driver_user_id,
      'team'
      -- No dedupe_key: driver gets notified on EVERY leave
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_left_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_left ON public.cs_carpool_passengers;
CREATE TRIGGER trg_emit_carpool_passenger_left
  AFTER DELETE ON public.cs_carpool_passengers
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_carpool_passenger_left_event();


-- 7b. Expense Share Paid → push to expense creator
CREATE OR REPLACE FUNCTION fn_emit_expense_share_paid_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expense    record;
  v_debtor_name text;
  v_amount_display text;
BEGIN
  IF NOT NEW.is_paid OR (OLD.is_paid IS NOT DISTINCT FROM true) THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id,
           e.amount_cents, e.currency
    INTO v_expense
    FROM public.cs_expenses e
    WHERE e.id = NEW.expense_id;

    IF v_expense IS NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.user_id = v_expense.paid_by_user_id THEN
      RETURN NEW;
    END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_debtor_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_expense.team_id
      AND tp.claimed_by = NEW.user_id
    LIMIT 1;

    v_amount_display := to_char(NEW.share_cents / 100.0, 'FM999990.00') || ' CHF';

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_user_id, recipient_filter, dedupe_key)
    VALUES (
      v_expense.team_id,
      v_expense.match_id,
      'expense_share_paid',
      'Spese bezahlt',
      coalesce(v_debtor_name, '?') || ' hat ' || v_amount_display
        || ' bezahlt (' || v_expense.title || ')',
      jsonb_build_object(
        'team_id',      v_expense.team_id,
        'match_id',     v_expense.match_id,
        'expense_id',   v_expense.id,
        'share_id',     NEW.id,
        'debtor_name',  coalesce(v_debtor_name, '?'),
        'share_cents',  NEW.share_cents,
        'expense_title', v_expense.title
      ),
      NEW.user_id,
      v_expense.paid_by_user_id,
      'team',
      'share_paid_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_paid_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_paid ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_paid
  AFTER UPDATE ON public.cs_expense_shares
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_share_paid_event();


-- 7c. Expense Share Created → push "du musst zahlen" to debtor
CREATE OR REPLACE FUNCTION fn_emit_expense_share_due_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expense    record;
  v_payer_name text;
  v_amount_display text;
BEGIN
  BEGIN
    SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id,
           e.amount_cents, e.currency
    INTO v_expense
    FROM public.cs_expenses e
    WHERE e.id = NEW.expense_id;

    IF v_expense IS NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.user_id = v_expense.paid_by_user_id THEN
      RETURN NEW;
    END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_expense.team_id
      AND tp.claimed_by = v_expense.paid_by_user_id
    LIMIT 1;

    v_amount_display := to_char(NEW.share_cents / 100.0, 'FM999990.00') || ' CHF';

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_user_id, recipient_filter, dedupe_key)
    VALUES (
      v_expense.team_id,
      v_expense.match_id,
      'expense_share_due',
      'Offene Spese',
      v_amount_display || ' an '
        || coalesce(v_payer_name, '?')
        || ' (' || v_expense.title || ')',
      jsonb_build_object(
        'team_id',       v_expense.team_id,
        'match_id',      v_expense.match_id,
        'expense_id',    v_expense.id,
        'share_id',      NEW.id,
        'payer_name',    coalesce(v_payer_name, '?'),
        'share_cents',   NEW.share_cents,
        'expense_title', v_expense.title
      ),
      v_expense.paid_by_user_id,
      NEW.user_id,
      'team',
      'share_due_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_due_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_due ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_due
  AFTER INSERT ON public.cs_expense_shares
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_share_due_event();


-- 7d. Lineup Published → cs_events (resilient)
--     Restored full payload (team_id, match_id, lineup_id) from
--     cs_events_payload_patch.sql + added EXCEPTION handler.
CREATE OR REPLACE FUNCTION fn_emit_lineup_published_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opponent text;
  v_payload  jsonb;
BEGIN
  IF NEW.status = 'published'
     AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'published')
  THEN
    BEGIN
      SELECT m.opponent INTO v_opponent
      FROM public.cs_matches m
      WHERE m.id = NEW.match_id;

      -- Build standardised payload (same as cs_events_payload_patch)
      v_payload := jsonb_build_object(
        'team_id',  NEW.team_id,
        'match_id', NEW.match_id
      );

      -- lineup_id: use NEW.id (cs_match_lineups PK)
      IF NEW.id IS NOT NULL THEN
        v_payload := v_payload || jsonb_build_object('lineup_id', NEW.id);
      END IF;

      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload, created_by)
      VALUES (
        NEW.team_id,
        NEW.match_id,
        'lineup_published',
        'Aufstellung veröffentlicht',
        'Die Aufstellung für ' || coalesce(v_opponent, '?') || ' ist online.',
        v_payload,
        NEW.created_by
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_emit_lineup_published_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
    END;
  END IF;
  RETURN NEW;
END;
$$;

-- Re-create trigger (idempotent)
DROP TRIGGER IF EXISTS trg_emit_lineup_published_event ON public.cs_match_lineups;
CREATE TRIGGER trg_emit_lineup_published_event
  AFTER UPDATE ON public.cs_match_lineups
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_lineup_published_event();


-- 7e. Lineup Event (auto-promotion / no-reserve) → cs_events (resilient)
--     Restored from cs_events_payload_patch.sql + added EXCEPTION handler.

-- Ensure helper function exists (DROP first to handle parameter name changes)
DROP FUNCTION IF EXISTS public.cs_event_payload_merge(jsonb, jsonb);
CREATE FUNCTION public.cs_event_payload_merge(
  base  jsonb,
  merge jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(base, '{}'::jsonb) || coalesce(merge, '{}'::jsonb);
$$;
GRANT EXECUTE ON FUNCTION public.cs_event_payload_merge(jsonb, jsonb) TO authenticated;

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
  v_payload      jsonb;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    -- Build enriched payload: always include team_id + match_id,
    -- then merge original cs_lineup_events.payload on top.
    v_payload := jsonb_build_object(
      'team_id',  NEW.team_id,
      'match_id', NEW.match_id
    );

    -- Merge original payload (preserves promoted_name, absent_name, to, etc.)
    IF NEW.payload IS NOT NULL AND jsonb_typeof(NEW.payload) = 'object' THEN
      v_payload := public.cs_event_payload_merge(v_payload, NEW.payload);
    END IF;

    -- Enrich with named keys if present in source payload
    IF NEW.payload ? 'promoted_name' THEN
      v_payload := v_payload || jsonb_build_object('in_name', NEW.payload->>'promoted_name');
    END IF;
    IF NEW.payload ? 'absent_name' THEN
      v_payload := v_payload || jsonb_build_object('out_name', NEW.payload->>'absent_name');
    END IF;
    IF NEW.payload ? 'to' THEN
      v_payload := v_payload || jsonb_build_object('in_member_id', NEW.payload->>'to');
    END IF;
    IF NEW.payload ? 'from' THEN
      v_payload := v_payload || jsonb_build_object('out_member_id', NEW.payload->>'from');
    END IF;
    IF NEW.created_by IS NOT NULL THEN
      v_payload := v_payload || jsonb_build_object('actor', NEW.created_by);
    END IF;

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
        v_payload,
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
          v_payload,
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
        v_payload,
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
          v_payload,
          v_captain_uid,
          NEW.created_by
        );
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_lineup_event_to_cs_events failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Re-create trigger (idempotent)
DROP TRIGGER IF EXISTS trg_emit_lineup_event_to_cs_events ON public.cs_lineup_events;
CREATE TRIGGER trg_emit_lineup_event_to_cs_events
  AFTER INSERT ON public.cs_lineup_events
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_lineup_event_to_cs_events();


-- ═══════════════════════════════════════════════════════════════════
--  8. FIX cs_dinner_rsvps RLS POLICIES
--     These may have failed to create if is_team_member() didn't
--     exist when cs_dinner_rsvps_patch.sql was originally run.
-- ═══════════════════════════════════════════════════════════════════

-- Ensure RLS is enabled
ALTER TABLE public.cs_dinner_rsvps ENABLE ROW LEVEL SECURITY;

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

-- DELETE: Own RSVP only
DROP POLICY IF EXISTS cs_dinner_rsvps_delete ON public.cs_dinner_rsvps;
CREATE POLICY cs_dinner_rsvps_delete ON public.cs_dinner_rsvps
  FOR DELETE
  USING (user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  9. ENSURE cs_match_availability RLS POLICIES EXIST
--     (may never have been explicitly created via a patch)
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.cs_match_availability ENABLE ROW LEVEL SECURITY;

-- SELECT: Team members can read all availability for their matches
DROP POLICY IF EXISTS cs_match_availability_select ON public.cs_match_availability;
CREATE POLICY cs_match_availability_select ON public.cs_match_availability
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.cs_matches m
       WHERE m.id = match_id
         AND public.is_team_member(m.team_id)
    )
  );

-- INSERT: Only for self, only if team member
DROP POLICY IF EXISTS cs_match_availability_insert ON public.cs_match_availability;
CREATE POLICY cs_match_availability_insert ON public.cs_match_availability
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.cs_matches m
       WHERE m.id = match_id
         AND public.is_team_member(m.team_id)
    )
  );

-- UPDATE: Only own availability, only if team member
DROP POLICY IF EXISTS cs_match_availability_update ON public.cs_match_availability;
CREATE POLICY cs_match_availability_update ON public.cs_match_availability
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

-- DELETE: Own availability only
DROP POLICY IF EXISTS cs_match_availability_delete ON public.cs_match_availability;
CREATE POLICY cs_match_availability_delete ON public.cs_match_availability
  FOR DELETE
  USING (user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  10. ENSURE cs_events RLS POLICIES EXIST
--      (may have failed previously when helper functions didn't exist)
-- ═══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS cs_events_select ON public.cs_events;
CREATE POLICY cs_events_select ON public.cs_events
  FOR SELECT USING (
    public.is_team_member(team_id)
    AND (recipient_user_id IS NULL OR recipient_user_id = auth.uid())
  );

DROP POLICY IF EXISTS cs_events_insert ON public.cs_events;
CREATE POLICY cs_events_insert ON public.cs_events
  FOR INSERT WITH CHECK (true);
  -- Allow trigger functions (SECURITY DEFINER) and admins to insert

DROP POLICY IF EXISTS cs_events_delete ON public.cs_events;
CREATE POLICY cs_events_delete ON public.cs_events
  FOR DELETE USING (
    public.is_team_admin(team_id) OR public.is_team_creator(team_id)
  );


-- ═══════════════════════════════════════════════════════════════════
--  11. ENSURE Supabase Realtime is enabled for key tables
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
--  12. RESILIENT TRIGGER: Carpool Offer Created → cs_events
--      (was missing from original fix – blocks carpool creation)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_emit_carpool_created_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_name text;
  v_opponent    text;
BEGIN
  BEGIN
    -- Resolve driver name
    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_driver_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = NEW.team_id
      AND tp.claimed_by = NEW.driver_user_id
    LIMIT 1;

    -- Resolve opponent from match
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, created_by, recipient_filter, dedupe_key)
    VALUES (
      NEW.team_id,
      NEW.match_id,
      'carpool_offered',
      'Neue Fahrgemeinschaft',
      coalesce(v_driver_name, '?') || ' bietet Fahrt an'
        || CASE WHEN v_opponent IS NOT NULL
             THEN ' (vs ' || v_opponent || ')'
             ELSE '' END,
      jsonb_build_object(
        'team_id',     NEW.team_id,
        'match_id',    NEW.match_id,
        'offer_id',    NEW.id,
        'driver_name', coalesce(v_driver_name, '?'),
        'seats_total', NEW.seats_total
      ),
      NEW.driver_user_id,
      'team_no_reserves',
      'carpool_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_created_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_created_event ON public.cs_carpool_offers;
CREATE TRIGGER trg_emit_carpool_created_event
  AFTER INSERT ON public.cs_carpool_offers
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_carpool_created_event();


-- ═══════════════════════════════════════════════════════════════════
--  13. FIX cs_carpool_offers RLS POLICIES
--      These may have failed to create if is_team_member() didn't
--      exist when cs_carpool_rls_patch.sql was originally run.
--      With FORCE ROW LEVEL SECURITY + no policies = all blocked!
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.cs_carpool_offers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_carpool_passengers ENABLE ROW LEVEL SECURITY;

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

-- ── cs_carpool_passengers ──────────────────────────────────────

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
    passenger_user_id = auth.uid()
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
    passenger_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.cs_carpool_offers o
       WHERE o.id = offer_id
         AND (
           o.driver_user_id = auth.uid()
           OR public.is_team_admin(o.team_id)
         )
    )
  );


-- ═══════════════════════════════════════════════════════════════════
--  14. ENSURE CARPOOL RPCs EXIST
--      These were never in a SQL patch file but are required by the
--      Flutter CarpoolService. CREATE OR REPLACE = safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- 14a. cs_upsert_carpool_offer
--      Creates or updates a carpool offer. Returns the offer UUID.
CREATE OR REPLACE FUNCTION public.cs_upsert_carpool_offer(
  p_team_id        uuid,
  p_match_id       uuid,
  p_seats_total    int,
  p_start_location text    DEFAULT NULL,
  p_note           text    DEFAULT NULL,
  p_depart_at      timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_offer_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check: user is team member
  IF NOT EXISTS (
    SELECT 1 FROM public.cs_team_members
    WHERE team_id = p_team_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'Not a team member';
  END IF;

  -- Upsert: one offer per driver per match
  INSERT INTO public.cs_carpool_offers
    (team_id, match_id, driver_user_id, seats_total,
     start_location, note, depart_at)
  VALUES
    (p_team_id, p_match_id, v_uid, p_seats_total,
     p_start_location, p_note, p_depart_at)
  ON CONFLICT (match_id, driver_user_id) DO UPDATE SET
    seats_total    = EXCLUDED.seats_total,
    start_location = EXCLUDED.start_location,
    note           = EXCLUDED.note,
    depart_at      = EXCLUDED.depart_at,
    updated_at     = now()
  RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_upsert_carpool_offer(uuid, uuid, int, text, text, timestamptz)
  TO authenticated;

-- Ensure unique constraint exists for upsert ON CONFLICT
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE tablename = 'cs_carpool_offers'
       AND indexdef LIKE '%match_id%driver_user_id%'
  ) THEN
    BEGIN
      ALTER TABLE public.cs_carpool_offers
        ADD CONSTRAINT uq_cs_carpool_offers_match_driver
        UNIQUE (match_id, driver_user_id);
    EXCEPTION WHEN duplicate_table THEN
      NULL; -- constraint already exists
    END;
  END IF;
END
$$;

-- 14b. cs_join_carpool
--      Add self as passenger to a carpool offer.
CREATE OR REPLACE FUNCTION public.cs_join_carpool(
  p_offer_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_offer  record;
  v_count  int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Load offer
  SELECT id, team_id, driver_user_id, seats_total
  INTO v_offer
  FROM public.cs_carpool_offers
  WHERE id = p_offer_id;

  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Offer not found: %', p_offer_id;
  END IF;

  -- Check: user is team member
  IF NOT EXISTS (
    SELECT 1 FROM public.cs_team_members
    WHERE team_id = v_offer.team_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'Not a team member';
  END IF;

  -- Check: not the driver
  IF v_uid = v_offer.driver_user_id THEN
    RAISE EXCEPTION 'Driver cannot join as passenger';
  END IF;

  -- Check: seats available
  SELECT count(*) INTO v_count
  FROM public.cs_carpool_passengers
  WHERE offer_id = p_offer_id;

  IF v_count >= v_offer.seats_total THEN
    RAISE EXCEPTION 'No seats available';
  END IF;

  -- Insert passenger (idempotent via ON CONFLICT)
  INSERT INTO public.cs_carpool_passengers (offer_id, passenger_user_id)
  VALUES (p_offer_id, v_uid)
  ON CONFLICT (offer_id, passenger_user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_join_carpool(uuid) TO authenticated;

-- 14c. cs_leave_carpool
--      Remove self as passenger from a carpool offer.
CREATE OR REPLACE FUNCTION public.cs_leave_carpool(
  p_offer_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM public.cs_carpool_passengers
  WHERE offer_id = p_offer_id
    AND passenger_user_id = v_uid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_leave_carpool(uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  14b. ENSURE cs_event_reads TABLE + RPCs EXIST
--       Required for "Alle gelesen" and "Alle löschen" in the inbox.
--       dismissed_at: when set, the event is hidden from the user.
-- ═══════════════════════════════════════════════════════════════════

-- Table for tracking which events a user has read / dismissed
CREATE TABLE IF NOT EXISTS public.cs_event_reads (
  event_id  uuid        NOT NULL REFERENCES public.cs_events(id) ON DELETE CASCADE,
  user_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at   timestamptz NOT NULL DEFAULT now(),
  dismissed_at timestamptz,
  PRIMARY KEY (event_id, user_id)
);

-- Add dismissed_at column if table already existed without it
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cs_event_reads'
      AND column_name = 'dismissed_at'
  ) THEN
    ALTER TABLE public.cs_event_reads ADD COLUMN dismissed_at timestamptz;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cs_event_reads_user_read
  ON public.cs_event_reads (user_id, read_at DESC);

ALTER TABLE public.cs_event_reads ENABLE ROW LEVEL SECURITY;

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
    )
  );

DROP POLICY IF EXISTS cs_event_reads_update ON public.cs_event_reads;
CREATE POLICY cs_event_reads_update ON public.cs_event_reads
  FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_event_reads_delete ON public.cs_event_reads;
CREATE POLICY cs_event_reads_delete ON public.cs_event_reads
  FOR DELETE USING (user_id = auth.uid());

-- RPC: Mark a single event as read (idempotent)
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
  ON CONFLICT (event_id, user_id) DO UPDATE SET read_at = COALESCE(cs_event_reads.read_at, now());
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_mark_event_read(uuid) TO authenticated;

-- RPC: Mark ALL visible events as read
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
  ON CONFLICT (event_id, user_id) DO UPDATE SET read_at = COALESCE(cs_event_reads.read_at, now());
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_mark_all_events_read() TO authenticated;

-- RPC: Dismiss (hide) a single event for the current user
DROP FUNCTION IF EXISTS public.cs_dismiss_event(uuid);
CREATE OR REPLACE FUNCTION public.cs_dismiss_event(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, read_at, dismissed_at)
  VALUES (p_event_id, auth.uid(), now(), now())
  ON CONFLICT (event_id, user_id) DO UPDATE SET dismissed_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_dismiss_event(uuid) TO authenticated;

-- RPC: Dismiss (hide) ALL visible events for the current user
DROP FUNCTION IF EXISTS public.cs_dismiss_all_events();
CREATE OR REPLACE FUNCTION public.cs_dismiss_all_events()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, read_at, dismissed_at)
  SELECT e.id, auth.uid(), now(), now()
  FROM public.cs_events e
  WHERE public.is_team_member(e.team_id)
    AND (e.recipient_user_id IS NULL OR e.recipient_user_id = auth.uid())
  ON CONFLICT (event_id, user_id) DO UPDATE SET dismissed_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_dismiss_all_events() TO authenticated;

-- RPC: Unread event count (for badge) – excludes dismissed
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
        AND (er.read_at IS NOT NULL OR er.dismissed_at IS NOT NULL)
    );
$$;
GRANT EXECUTE ON FUNCTION public.cs_unread_event_count() TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  15. DIAGNOSTIC: Verify everything
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count int;
  v_tbl   text;
BEGIN
  -- Check all required tables exist
  FOREACH v_tbl IN ARRAY ARRAY[
    'cs_events',
    'cs_event_deliveries',
    'cs_notification_prefs',
    'cs_device_tokens',
    'cs_notifications',
    'cs_match_availability',
    'cs_dinner_rsvps'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public'
         AND table_name   = v_tbl
    ) THEN
      RAISE WARNING 'TABLE % does NOT exist!', v_tbl;
    ELSE
      RAISE NOTICE 'OK: table % exists', v_tbl;
    END IF;
  END LOOP;

  -- Check helper functions
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_team_member') THEN
    RAISE WARNING 'is_team_member function NOT found!';
  ELSE
    RAISE NOTICE 'OK: is_team_member() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_team_admin') THEN
    RAISE WARNING 'is_team_admin function NOT found!';
  ELSE
    RAISE NOTICE 'OK: is_team_admin() exists';
  END IF;

  -- Check trigger functions
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emit_availability_changed_event') THEN
    RAISE WARNING 'fn_emit_availability_changed_event NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_emit_availability_changed_event() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emit_dinner_rsvp_event') THEN
    RAISE WARNING 'fn_emit_dinner_rsvp_event NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_emit_dinner_rsvp_event() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_cs_event_fanout') THEN
    RAISE WARNING 'fn_cs_event_fanout NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_cs_event_fanout() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_bridge_delivery_to_notification') THEN
    RAISE WARNING 'fn_bridge_delivery_to_notification NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_bridge_delivery_to_notification() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emit_lineup_published_event') THEN
    RAISE WARNING 'fn_emit_lineup_published_event NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_emit_lineup_published_event() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emit_lineup_event_to_cs_events') THEN
    RAISE WARNING 'fn_emit_lineup_event_to_cs_events NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_emit_lineup_event_to_cs_events() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_event_payload_merge') THEN
    RAISE WARNING 'cs_event_payload_merge NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_event_payload_merge() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emit_carpool_passenger_left_event') THEN
    RAISE WARNING 'fn_emit_carpool_passenger_left_event NOT found!';
  ELSE
    RAISE NOTICE 'OK: fn_emit_carpool_passenger_left_event() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_mark_event_read') THEN
    RAISE WARNING 'cs_mark_event_read RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_mark_event_read() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_mark_all_events_read') THEN
    RAISE WARNING 'cs_mark_all_events_read RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_mark_all_events_read() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_unread_event_count') THEN
    RAISE WARNING 'cs_unread_event_count RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_unread_event_count() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_dismiss_event') THEN
    RAISE WARNING 'cs_dismiss_event RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_dismiss_event() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_dismiss_all_events') THEN
    RAISE WARNING 'cs_dismiss_all_events RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_dismiss_all_events() exists';
  END IF;

  -- Check RLS policies for key tables
  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_match_availability';
  RAISE NOTICE 'cs_match_availability has % RLS policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_dinner_rsvps';
  RAISE NOTICE 'cs_dinner_rsvps has % RLS policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_events';
  RAISE NOTICE 'cs_events has % RLS policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_event_reads';
  RAISE NOTICE 'cs_event_reads has % RLS policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_carpool_offers';
  RAISE NOTICE 'cs_carpool_offers has % RLS policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_carpool_passengers';
  RAISE NOTICE 'cs_carpool_passengers has % RLS policies', v_count;

  -- Check carpool RPCs
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_upsert_carpool_offer') THEN
    RAISE WARNING 'cs_upsert_carpool_offer RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_upsert_carpool_offer() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_join_carpool') THEN
    RAISE WARNING 'cs_join_carpool RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_join_carpool() exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cs_leave_carpool') THEN
    RAISE WARNING 'cs_leave_carpool RPC NOT found!';
  ELSE
    RAISE NOTICE 'OK: cs_leave_carpool() exists';
  END IF;

  RAISE NOTICE '--- All checks complete ---';
END
$$;


-- ═══════════════════════════════════════════════════════════════════
--  16. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
