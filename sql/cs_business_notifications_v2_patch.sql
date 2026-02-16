-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss/Lineup – Business Push Notifications v2           ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                 ║
-- ║                                                                ║
-- ║  Adds / Updates:                                               ║
-- ║  1. Trigger: availability_changed (ALL statuses) → captain    ║
-- ║  2. Trigger: dinner_rsvp (ALL statuses) → captain             ║
-- ║     (replaces dinner_rsvp_yes-only trigger from v1)           ║
-- ║  3. Trigger: carpool_passenger_joined → driver                ║
-- ║  4. Trigger: expense_share_paid (is_paid=true) → payer        ║
-- ║  5. Trigger: expense_share_due (new share) → debtor           ║
-- ║                                                                ║
-- ║  Depends on:                                                   ║
-- ║  - cs_events_patch.sql                                         ║
-- ║  - cs_push_pipeline_patch.sql                                  ║
-- ║  - cs_business_notifications_patch.sql  (v1, for fanout etc)  ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  1. TRIGGER: Availability Changed → captain push
--     Fires on INSERT or UPDATE of cs_match_availability.
--     Notifies captain for ALL status changes (yes / no / maybe).
--     Skips if status hasn't changed on UPDATE.
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
  -- Skip if UPDATE and status didn't change
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

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
    AND tp.user_id = NEW.user_id
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
     payload, created_by, recipient_filter, dedupe_key)
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
    NEW.user_id,                 -- actor (excluded from push)
    'captain',                   -- only captain(s)
    'avail_' || NEW.match_id || '_' || NEW.user_id || '_' || NEW.status
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_availability_changed_event ON public.cs_match_availability;
CREATE TRIGGER trg_emit_availability_changed_event
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_availability_changed_event();


-- ═══════════════════════════════════════════════════════════════════
--  2. TRIGGER: Dinner RSVP (ALL statuses) → captain
--     Replaces the v1 trigger that only fired for 'yes'.
--     Now fires for yes / no / maybe, always notifying captain.
--     Skips if status unchanged on UPDATE.
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
  -- Skip if UPDATE and status didn't change
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
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
    AND tp.user_id = NEW.user_id
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
     payload, created_by, recipient_filter, dedupe_key)
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
    NEW.user_id,               -- actor (excluded from push)
    'captain',                 -- only captain(s)
    'dinner_' || NEW.match_id || '_' || NEW.user_id || '_' || NEW.status
  );

  RETURN NEW;
END;
$$;

-- Trigger already exists from v1 – the CREATE OR REPLACE above
-- updated the function body. No need to re-create the trigger
-- unless the trigger name changed. Ensure it fires for INSERT OR UPDATE.
DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_emit_dinner_rsvp_event
  AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_dinner_rsvp_event();


-- ═══════════════════════════════════════════════════════════════════
--  3. TRIGGER: Carpool Passenger Joined → driver push
--     Fires on INSERT on cs_carpool_passengers.
--     Notifies the driver (targeted via recipient_user_id).
-- ═══════════════════════════════════════════════════════════════════

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
  -- Resolve offer details
  SELECT o.id, o.team_id, o.match_id, o.driver_user_id, o.seats_total
  INTO v_offer
  FROM public.cs_carpool_offers o
  WHERE o.id = NEW.offer_id;

  IF v_offer IS NULL THEN
    RETURN NEW;
  END IF;

  -- Don't notify if driver joins their own ride (shouldn't happen but be safe)
  IF NEW.user_id = v_offer.driver_user_id THEN
    RETURN NEW;
  END IF;

  -- Resolve passenger name
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_passenger_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_offer.team_id
    AND tp.user_id = NEW.user_id
  LIMIT 1;

  -- Resolve opponent from match
  SELECT m.opponent INTO v_opponent
  FROM public.cs_matches m
  WHERE m.id = v_offer.match_id;

  INSERT INTO public.cs_events
    (team_id, match_id, event_type, title, body,
     payload, created_by, recipient_user_id, recipient_filter, dedupe_key)
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
      'user_id',        NEW.user_id
    ),
    NEW.user_id,                    -- actor (passenger, excluded from push)
    v_offer.driver_user_id,         -- targeted to driver only
    'team',                         -- filter = team (+ recipient_user_id restricts)
    'carpool_join_' || v_offer.id || '_' || NEW.user_id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_joined ON public.cs_carpool_passengers;
CREATE TRIGGER trg_emit_carpool_passenger_joined
  AFTER INSERT ON public.cs_carpool_passengers
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_carpool_passenger_joined_event();


-- ═══════════════════════════════════════════════════════════════════
--  4. TRIGGER: Expense Share Paid → push to expense creator
--     Fires on UPDATE of cs_expense_shares when is_paid becomes true.
--     Notifies the person who paid (expense creator / paid_by_user_id).
-- ═══════════════════════════════════════════════════════════════════

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
  -- Only fire when is_paid transitions false → true
  IF NOT NEW.is_paid OR (OLD.is_paid IS NOT DISTINCT FROM true) THEN
    RETURN NEW;
  END IF;

  -- Resolve expense details
  SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id,
         e.amount_cents, e.currency
  INTO v_expense
  FROM public.cs_expenses e
  WHERE e.id = NEW.expense_id;

  IF v_expense IS NULL THEN
    RETURN NEW;
  END IF;

  -- Don't notify if the expense creator is marking their own share
  IF NEW.user_id = v_expense.paid_by_user_id THEN
    RETURN NEW;
  END IF;

  -- Resolve debtor name
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_debtor_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_expense.team_id
    AND tp.user_id = NEW.user_id
  LIMIT 1;

  -- Format share amount
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
    NEW.user_id,                       -- actor (debtor who paid)
    v_expense.paid_by_user_id,         -- targeted to expense creator
    'team',                            -- filter + recipient_user_id
    'share_paid_' || NEW.id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_paid ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_paid
  AFTER UPDATE ON public.cs_expense_shares
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_share_paid_event();


-- ═══════════════════════════════════════════════════════════════════
--  5. TRIGGER: Expense Share Created → push "du musst zahlen" to debtor
--     Fires on INSERT on cs_expense_shares.
--     Notifies each share holder that they owe money.
--     Skips the expense payer (they paid, they don't owe themselves).
-- ═══════════════════════════════════════════════════════════════════

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
  -- Resolve expense details
  SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id,
         e.amount_cents, e.currency
  INTO v_expense
  FROM public.cs_expenses e
  WHERE e.id = NEW.expense_id;

  IF v_expense IS NULL THEN
    RETURN NEW;
  END IF;

  -- Skip if this share belongs to the payer (they don't owe themselves)
  IF NEW.user_id = v_expense.paid_by_user_id THEN
    RETURN NEW;
  END IF;

  -- Resolve payer name
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_expense.team_id
    AND tp.user_id = v_expense.paid_by_user_id
  LIMIT 1;

  -- Format share amount
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
    v_expense.paid_by_user_id,     -- actor = expense creator (excluded)
    NEW.user_id,                    -- targeted to debtor
    'team',                         -- filter + recipient_user_id
    'share_due_' || NEW.id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_due ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_due
  AFTER INSERT ON public.cs_expense_shares
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_expense_share_due_event();


-- ═══════════════════════════════════════════════════════════════════
--  6. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
