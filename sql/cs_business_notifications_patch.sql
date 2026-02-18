-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Business Push Notifications                      ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                  ║
-- ║                                                                ║
-- ║  Adds:                                                         ║
-- ║  1. dedupe_key column on cs_events (idempotent inserts)        ║
-- ║  2. recipient_filter column on cs_events                       ║
-- ║  3. Updated fanout trigger with recipient filtering            ║
-- ║  4. Trigger: expense_added (cs_expenses INSERT)                ║
-- ║  5. Trigger: dinner_rsvp_yes (cs_dinner_rsvps INSERT/UPDATE)  ║
-- ║  6. Trigger: carpool_offered (cs_carpool_offers INSERT)        ║
-- ║  7. Function: cs_create_match_reminders() (24h + 2h)          ║
-- ║                                                                ║
-- ║  Depends on:                                                   ║
-- ║  - cs_events_patch.sql                                         ║
-- ║  - cs_push_pipeline_patch.sql                                  ║
-- ║  - cs_expenses_patch.sql                                       ║
-- ║  - cs_dinner_rsvps_patch.sql                                   ║
-- ║  - cs_carpool_rls_patch.sql                                    ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. ADD dedupe_key COLUMN to cs_events
--     Prevents duplicate events (e.g. match reminders).
-- ═══════════════════════════════════════════════════════════════════

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

-- Partial unique index: only enforced when dedupe_key is set.
CREATE UNIQUE INDEX IF NOT EXISTS idx_cs_events_dedupe_key
  ON public.cs_events (dedupe_key)
  WHERE dedupe_key IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
--  2. ADD recipient_filter COLUMN to cs_events
--     Controls who receives push notifications:
--       'team'             → all team members (default, backward compat)
--       'lineup_starters'  → only starters in cs_match_lineup_slots
--       'team_no_reserves' → team members minus lineup reserves
--       'captain'          → captain(s) + team creator
-- ═══════════════════════════════════════════════════════════════════

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

-- Add CHECK constraint (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
     WHERE constraint_name = 'chk_cs_events_recipient_filter'
  ) THEN
    ALTER TABLE public.cs_events
      ADD CONSTRAINT chk_cs_events_recipient_filter
      CHECK (recipient_filter IN ('team', 'lineup_starters', 'team_no_reserves', 'captain'));
  END IF;
END
$$;

-- ═══════════════════════════════════════════════════════════════════
--  3. UPDATED FANOUT TRIGGER: fn_cs_event_fanout
--     Now respects recipient_filter to determine target audience.
--
--     Filters:
--       'team'             → all cs_team_members (original behavior)
--       'lineup_starters'  → cs_match_lineup_slots WHERE slot_type='starter'
--       'team_no_reserves' → team members NOT in lineup as 'reserve'
--       'captain'          → captain role + team creator (fallback)
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
  v_filter := coalesce(NEW.recipient_filter, 'team');

  FOR v_user IN
    SELECT DISTINCT x.user_id
    FROM (
      -----------------------------------------------------------
      -- FILTER: lineup_starters
      -- Only starters in the published lineup for this match.
      -----------------------------------------------------------
      SELECT ls.user_id
      FROM public.cs_match_lineup_slots ls
      WHERE v_filter = 'lineup_starters'
        AND NEW.match_id IS NOT NULL
        AND ls.match_id = NEW.match_id
        AND ls.slot_type = 'starter'
        AND ls.user_id IS NOT NULL

      UNION

      -----------------------------------------------------------
      -- FILTER: team_no_reserves
      -- All team members MINUS those who are reserves in the
      -- lineup for this match.  If no lineup exists, everyone
      -- gets included (no reserves to exclude).
      -----------------------------------------------------------
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

      -----------------------------------------------------------
      -- FILTER: captain
      -- Team captain(s) by role.
      -----------------------------------------------------------
      SELECT tm.user_id
      FROM public.cs_team_members tm
      WHERE v_filter = 'captain'
        AND tm.team_id = NEW.team_id
        AND tm.role = 'captain'
        AND tm.user_id IS NOT NULL

      UNION

      -- Captain fallback: team creator (if no captain role exists)
      SELECT t.created_by
      FROM public.cs_teams t
      WHERE v_filter = 'captain'
        AND t.id = NEW.team_id
        AND t.created_by IS NOT NULL

      UNION

      -----------------------------------------------------------
      -- FILTER: team (default)
      -- All team members with a user_id.
      -----------------------------------------------------------
      SELECT tm.user_id
      FROM public.cs_team_members tm
      WHERE v_filter = 'team'
        AND tm.team_id = NEW.team_id
        AND tm.user_id IS NOT NULL
    ) x
    WHERE (
      -- If recipient_user_id is set, further restrict to that user
      NEW.recipient_user_id IS NULL
      OR x.user_id = NEW.recipient_user_id
    )
    -- Skip the actor (they don't need a push for their own action)
    AND (NEW.created_by IS NULL OR x.user_id <> NEW.created_by)
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

-- Re-create trigger (idempotent)
DROP TRIGGER IF EXISTS trg_cs_event_fanout ON public.cs_events;
CREATE TRIGGER trg_cs_event_fanout
  AFTER INSERT ON public.cs_events
  FOR EACH ROW
  EXECUTE FUNCTION fn_cs_event_fanout();

-- ═══════════════════════════════════════════════════════════════════
--  4. TRIGGER: Expense Created → cs_events
--     Fires when a new row is inserted into cs_expenses.
--     Notifies all team members (recipient_filter = 'team').
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
  -- Resolve opponent name from match
  SELECT m.opponent INTO v_opponent
  FROM public.cs_matches m
  WHERE m.id = NEW.match_id;

  -- Resolve payer name
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = NEW.team_id
    AND tp.claimed_by = NEW.paid_by_user_id
  LIMIT 1;

  -- Format amount: cents → "12.50 CHF"
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
    NEW.paid_by_user_id,      -- created_by → excluded from push
    'team',                   -- all team members
    'expense_' || NEW.id      -- dedupe
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_created_event ON public.cs_expenses;
CREATE TRIGGER trg_emit_expense_created_event
  AFTER INSERT ON public.cs_expenses
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_created_event();

-- ═══════════════════════════════════════════════════════════════════
--  5. TRIGGER: Dinner RSVP "Ja" → cs_events
--     Fires on INSERT or UPDATE on cs_dinner_rsvps.
--     Only when status = 'yes' (and was not already 'yes').
--     Notifies the team captain (recipient_filter = 'captain').
--
--     Rationale: Captain/organiser needs to know headcount for
--     dinner; all team members can see RSVPs in the app UI.
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
BEGIN
  -- Only fire when status becomes 'yes'
  IF NEW.status <> 'yes' THEN
    RETURN NEW;
  END IF;

  -- Skip if UPDATE and status didn't change
  IF TG_OP = 'UPDATE' AND OLD.status = 'yes' THEN
    RETURN NEW;
  END IF;

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

  INSERT INTO public.cs_events
    (team_id, match_id, event_type, title, body,
     payload, created_by, recipient_filter, dedupe_key)
  VALUES (
    v_team_id,
    NEW.match_id,
    'dinner_rsvp_yes',
    'Essen: Zusage',
    coalesce(v_player_name, '?') || ' isst mit'
      || CASE WHEN v_opponent IS NOT NULL
           THEN ' (vs ' || v_opponent || ')'
           ELSE '' END,
    jsonb_build_object(
      'team_id',     v_team_id,
      'match_id',    NEW.match_id,
      'user_id',     NEW.user_id,
      'player_name', coalesce(v_player_name, '?')
    ),
    NEW.user_id,               -- created_by → actor excluded
    'captain',                 -- only captain(s)
    'dinner_yes_' || NEW.match_id || '_' || NEW.user_id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_emit_dinner_rsvp_event
  AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_dinner_rsvp_event();

-- ═══════════════════════════════════════════════════════════════════
--  6. TRIGGER: Carpool Offer Created → cs_events
--     Fires on INSERT on cs_carpool_offers.
--     Notifies team members EXCLUDING lineup reserves
--     (recipient_filter = 'team_no_reserves').
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
    NEW.driver_user_id,        -- created_by → actor excluded
    'team_no_reserves',        -- everyone except reserves
    'carpool_' || NEW.id       -- dedupe
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_created_event ON public.cs_carpool_offers;
CREATE TRIGGER trg_emit_carpool_created_event
  AFTER INSERT ON public.cs_carpool_offers
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_carpool_created_event();

-- ═══════════════════════════════════════════════════════════════════
--  7. FUNCTION: cs_create_match_reminders
--     Call periodically (every 5–10 min via pg_cron or Edge Fn cron).
--     Creates idempotent reminder events for matches starting in
--     ~24h and ~2h.  Only lineup starters receive the push.
--
--     Returns JSON with counts of newly created reminders.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_create_match_reminders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match     record;
  v_24h       int := 0;
  v_2h        int := 0;
  v_inserted  int;
BEGIN
  -- ── 24-hour reminders ──────────────────────────────────────
  FOR v_match IN
    SELECT m.id, m.team_id, m.opponent, m.match_at
    FROM public.cs_matches m
    WHERE m.match_at BETWEEN (now() + interval '23 hours 50 minutes')
                        AND (now() + interval '24 hours 10 minutes')
  LOOP
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, recipient_filter, dedupe_key)
    VALUES (
      v_match.team_id,
      v_match.id,
      'match_reminder_24h',
      'Spielerinnerung – morgen',
      'Morgen: Match vs ' || coalesce(v_match.opponent, '?'),
      jsonb_build_object(
        'team_id',  v_match.team_id,
        'match_id', v_match.id
      ),
      'lineup_starters',
      'reminder_24h_' || v_match.id
    )
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_24h := v_24h + v_inserted;
  END LOOP;

  -- ── 2-hour reminders ───────────────────────────────────────
  FOR v_match IN
    SELECT m.id, m.team_id, m.opponent, m.match_at
    FROM public.cs_matches m
    WHERE m.match_at BETWEEN (now() + interval '1 hour 50 minutes')
                        AND (now() + interval '2 hours 10 minutes')
  LOOP
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body,
       payload, recipient_filter, dedupe_key)
    VALUES (
      v_match.team_id,
      v_match.id,
      'match_reminder_2h',
      'Gleich gehts los!',
      'In 2 Stunden: Match vs ' || coalesce(v_match.opponent, '?'),
      jsonb_build_object(
        'team_id',  v_match.team_id,
        'match_id', v_match.id
      ),
      'lineup_starters',
      'reminder_2h_' || v_match.id
    )
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_2h := v_2h + v_inserted;
  END LOOP;

  RETURN jsonb_build_object(
    'reminders_24h_created', v_24h,
    'reminders_2h_created',  v_2h,
    'checked_at',            now()
  );
END;
$$;

-- Grant execute to service_role (Edge Function) and authenticated (debug)
GRANT EXECUTE ON FUNCTION public.cs_create_match_reminders() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  8. HELPER: cs_process_pending_deliveries
--     Returns pending deliveries with event + device token data
--     for the Edge Function send-push worker.
--     Marks selected rows as 'processing' to avoid double-sends.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_process_pending_deliveries(
  p_batch_size int DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deliveries jsonb;
BEGIN
  -- Select + lock pending deliveries and return with event + token info
  WITH batch AS (
    SELECT
      d.id           AS delivery_id,
      d.event_id,
      d.user_id,
      d.attempts,
      e.event_type,
      e.title,
      e.body,
      e.payload,
      e.team_id,
      e.match_id
    FROM public.cs_event_deliveries d
    JOIN public.cs_events e ON e.id = d.event_id
    WHERE d.status = 'pending'
    ORDER BY d.created_at ASC
    LIMIT p_batch_size
    FOR UPDATE OF d SKIP LOCKED
  ),
  tokens AS (
    SELECT
      b.*,
      jsonb_agg(
        jsonb_build_object(
          'token',    dt.token,
          'platform', dt.platform
        )
      ) AS device_tokens
    FROM batch b
    JOIN public.cs_device_tokens dt
      ON dt.user_id = b.user_id
     AND dt.enabled = true
     AND dt.token <> ''
     AND dt.token IS NOT NULL
    GROUP BY b.delivery_id, b.event_id, b.user_id, b.attempts,
             b.event_type, b.title, b.body, b.payload,
             b.team_id, b.match_id
  ),
  -- Mark as processing (increment attempts)
  updated AS (
    UPDATE public.cs_event_deliveries d
    SET attempts = d.attempts + 1
    FROM tokens t
    WHERE d.id = t.delivery_id
    RETURNING d.id
  )
  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'delivery_id',   t.delivery_id,
      'event_id',      t.event_id,
      'user_id',       t.user_id,
      'event_type',    t.event_type,
      'title',         t.title,
      'body',          t.body,
      'payload',       t.payload,
      'team_id',       t.team_id,
      'match_id',      t.match_id,
      'device_tokens', t.device_tokens,
      'attempts',      t.attempts + 1
    )
  ), '[]'::jsonb) INTO v_deliveries
  FROM tokens t;

  -- Skip deliveries with no valid device tokens
  UPDATE public.cs_event_deliveries d
  SET status = 'skipped',
      last_error = 'no_device_tokens',
      processed_at = now()
  WHERE d.status = 'pending'
    AND NOT EXISTS (
      SELECT 1 FROM public.cs_device_tokens dt
      WHERE dt.user_id = d.user_id
        AND dt.enabled = true
        AND dt.token <> ''
        AND dt.token IS NOT NULL
    )
    AND d.id IN (
      SELECT d2.id FROM public.cs_event_deliveries d2
      WHERE d2.status = 'pending'
      ORDER BY d2.created_at ASC
      LIMIT p_batch_size
    );

  RETURN v_deliveries;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
--  9. HELPER: cs_mark_delivery_result
--     Called by Edge Function after FCM send attempt.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_mark_delivery_result(
  p_delivery_id uuid,
  p_status      text,     -- 'sent' | 'failed'
  p_error       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cs_event_deliveries
  SET status       = p_status,
      last_error   = p_error,
      processed_at = now()
  WHERE id = p_delivery_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
--  10. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
