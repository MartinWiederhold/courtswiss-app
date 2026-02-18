-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX 1: NUR Trigger-Funktionen + Trigger wiederherstellen      ║
-- ║  Kein RLS, keine RPCs, keine Tabellen. Nur das Minimum.        ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- Alte störende Trigger entfernen
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;
DROP TRIGGER IF EXISTS trg_cs_events_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS trg_on_event_create_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS cs_on_event_create_enqueue_push ON public.cs_events;
DROP FUNCTION IF EXISTS public.cs_on_event_create_enqueue_push();


-- ── 1. Verfügbarkeit ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_availability_changed_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_team_id     uuid;
  v_opponent    text;
  v_player_name text;
  v_status_text text;
  v_title       text;
  v_body        text;
BEGIN
  BEGIN
    SELECT m.team_id, m.opponent INTO v_team_id, v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;
    IF v_team_id IS NULL THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id AND tp.claimed_by = NEW.user_id LIMIT 1;

    v_status_text := CASE NEW.status
      WHEN 'yes'   THEN 'zugesagt'
      WHEN 'no'    THEN 'abgesagt'
      WHEN 'maybe' THEN 'unsicher'
      ELSE NEW.status
    END;

    v_title := 'Verfügbarkeit: ' || initcap(v_status_text);
    v_body  := coalesce(v_player_name, '?') || ' hat ' || v_status_text
               || CASE WHEN v_opponent IS NOT NULL THEN ' (vs ' || v_opponent || ')' ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter)
    VALUES (
      v_team_id, NEW.match_id, 'availability_changed', v_title, v_body,
      jsonb_build_object(
        'team_id',     v_team_id,
        'match_id',    NEW.match_id,
        'user_id',     NEW.user_id,
        'status',      NEW.status,
        'player_name', coalesce(v_player_name, '?')
      ),
      NEW.user_id, 'captain'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_availability_changed_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_availability_changed_event ON public.cs_match_availability;
CREATE TRIGGER trg_emit_availability_changed_event
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW EXECUTE FUNCTION fn_emit_availability_changed_event();


-- ── 2. Essen ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_dinner_rsvp_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_team_id     uuid;
  v_opponent    text;
  v_player_name text;
  v_status_text text;
  v_title       text;
  v_body        text;
BEGIN
  BEGIN
    SELECT m.team_id, m.opponent INTO v_team_id, v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;
    IF v_team_id IS NULL THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id AND tp.claimed_by = NEW.user_id LIMIT 1;

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
              || CASE WHEN v_opponent IS NOT NULL THEN ' (vs ' || v_opponent || ')' ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter)
    VALUES (
      v_team_id, NEW.match_id, 'dinner_rsvp', v_title, v_body,
      jsonb_build_object(
        'team_id',     v_team_id,
        'match_id',    NEW.match_id,
        'user_id',     NEW.user_id,
        'status',      NEW.status,
        'player_name', coalesce(v_player_name, '?')
      ),
      NEW.user_id, 'captain'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_dinner_rsvp_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_emit_dinner_rsvp_event
  AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW EXECUTE FUNCTION fn_emit_dinner_rsvp_event();


-- ── 3. Event Fanout (WICHTIGSTER) ─────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cs_event_fanout()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user   record;
  v_prefs  record;
  v_status text;
  v_filter text;
BEGIN
  BEGIN
    v_filter := coalesce(NEW.recipient_filter, 'team');

    FOR v_user IN
      SELECT DISTINCT x.user_id
      FROM (
        SELECT ls.user_id
        FROM public.cs_match_lineup_slots ls
        WHERE v_filter = 'lineup_starters'
          AND NEW.match_id IS NOT NULL
          AND ls.match_id = NEW.match_id
          AND ls.slot_type = 'starter'
          AND ls.user_id IS NOT NULL

        UNION

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

        SELECT tm.user_id
        FROM public.cs_team_members tm
        WHERE v_filter = 'captain'
          AND tm.team_id = NEW.team_id
          AND tm.role = 'captain'
          AND tm.user_id IS NOT NULL

        UNION

        SELECT t.created_by
        FROM public.cs_teams t
        WHERE v_filter = 'captain'
          AND t.id = NEW.team_id
          AND t.created_by IS NOT NULL

        UNION

        SELECT tm.user_id
        FROM public.cs_team_members tm
        WHERE v_filter = 'team'
          AND tm.team_id = NEW.team_id
          AND tm.user_id IS NOT NULL
      ) x
      WHERE (NEW.recipient_user_id IS NULL OR x.user_id = NEW.recipient_user_id)
        AND (NEW.created_by IS NULL OR x.user_id <> NEW.created_by)
    LOOP
      BEGIN
        SELECT np.push_enabled, np.types_disabled INTO v_prefs
        FROM public.cs_notification_prefs np
        WHERE np.user_id = v_user.user_id AND np.team_id = NEW.team_id;
        IF NOT FOUND THEN
          SELECT np.push_enabled, np.types_disabled INTO v_prefs
          FROM public.cs_notification_prefs np
          WHERE np.user_id = v_user.user_id AND np.team_id IS NULL;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_prefs := NULL;
      END;

      IF v_prefs IS NOT NULL
         AND (v_prefs.push_enabled = false OR NEW.event_type = ANY(v_prefs.types_disabled))
      THEN
        v_status := 'skipped';
      ELSE
        v_status := 'pending';
      END IF;

      INSERT INTO public.cs_event_deliveries
        (event_id, user_id, channel, status)
      VALUES
        (NEW.id, v_user.user_id, 'push', v_status)
      ON CONFLICT (event_id, user_id, channel) DO NOTHING;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_cs_event_fanout failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cs_event_fanout ON public.cs_events;
CREATE TRIGGER trg_cs_event_fanout
  AFTER INSERT ON public.cs_events
  FOR EACH ROW EXECUTE FUNCTION fn_cs_event_fanout();


-- ── 4. Bridge delivery → notification ─────────────────────────────
CREATE OR REPLACE FUNCTION fn_bridge_delivery_to_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event record;
BEGIN
  IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
  BEGIN
    SELECT e.event_type, e.title, e.body, e.payload, e.match_id, e.team_id
    INTO v_event
    FROM public.cs_events e WHERE e.id = NEW.event_id;
    IF v_event IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.cs_notifications
      (recipient_user_id, type, title, body, payload, match_id, team_id)
    VALUES (
      NEW.user_id, v_event.event_type, v_event.title, v_event.body,
      v_event.payload, v_event.match_id, v_event.team_id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_bridge_delivery_to_notification failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bridge_delivery_to_notification ON public.cs_event_deliveries;
CREATE TRIGGER trg_bridge_delivery_to_notification
  AFTER INSERT ON public.cs_event_deliveries
  FOR EACH ROW EXECUTE FUNCTION fn_bridge_delivery_to_notification();


-- ── 5. Expense Created ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_expense_created_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opponent       text;
  v_payer_name     text;
  v_amount_display text;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = NEW.team_id AND tp.claimed_by = NEW.paid_by_user_id LIMIT 1;

    v_amount_display := to_char(NEW.amount_cents / 100.0, 'FM999990.00') || ' ' || NEW.currency;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter, dedupe_key)
    VALUES (
      NEW.team_id, NEW.match_id, 'expense_added', 'Neue Spese',
      coalesce(v_payer_name, '?') || ': ' || NEW.title || ' – ' || v_amount_display,
      jsonb_build_object(
        'team_id',      NEW.team_id,
        'match_id',     NEW.match_id,
        'expense_id',   NEW.id,
        'title',        NEW.title,
        'amount_cents', NEW.amount_cents,
        'currency',     NEW.currency,
        'payer_name',   coalesce(v_payer_name, '?')
      ),
      NEW.paid_by_user_id, 'team', 'expense_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_created_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_created_event ON public.cs_expenses;
CREATE TRIGGER trg_emit_expense_created_event
  AFTER INSERT ON public.cs_expenses
  FOR EACH ROW EXECUTE FUNCTION fn_emit_expense_created_event();


-- ── 6. Carpool Passenger Joined ───────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_joined_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_offer          record;
  v_passenger_name text;
  v_opponent       text;
BEGIN
  BEGIN
    SELECT o.id, o.team_id, o.match_id, o.driver_user_id, o.seats_total
    INTO v_offer
    FROM public.cs_carpool_offers o WHERE o.id = NEW.offer_id;
    IF v_offer IS NULL THEN RETURN NEW; END IF;
    IF NEW.passenger_user_id = v_offer.driver_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_offer.team_id AND tp.claimed_by = NEW.passenger_user_id LIMIT 1;

    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m WHERE m.id = v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_user_id, recipient_filter)
    VALUES (
      v_offer.team_id, v_offer.match_id, 'carpool_passenger_joined', 'Mitfahrer',
      coalesce(v_passenger_name, '?') || ' fährt mit'
        || CASE WHEN v_opponent IS NOT NULL THEN ' (vs ' || v_opponent || ')' ELSE '' END,
      jsonb_build_object(
        'team_id',        v_offer.team_id,
        'match_id',       v_offer.match_id,
        'offer_id',       v_offer.id,
        'passenger_name', coalesce(v_passenger_name, '?'),
        'user_id',        NEW.passenger_user_id
      ),
      NEW.passenger_user_id, v_offer.driver_user_id, 'team'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_joined_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_joined ON public.cs_carpool_passengers;
CREATE TRIGGER trg_emit_carpool_passenger_joined
  AFTER INSERT ON public.cs_carpool_passengers
  FOR EACH ROW EXECUTE FUNCTION fn_emit_carpool_passenger_joined_event();


-- ── 7. Carpool Passenger Left ─────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_left_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_offer          record;
  v_passenger_name text;
  v_opponent       text;
BEGIN
  BEGIN
    SELECT o.id, o.team_id, o.match_id, o.driver_user_id, o.seats_total
    INTO v_offer
    FROM public.cs_carpool_offers o WHERE o.id = OLD.offer_id;
    IF v_offer IS NULL THEN RETURN OLD; END IF;
    IF OLD.passenger_user_id = v_offer.driver_user_id THEN RETURN OLD; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_offer.team_id AND tp.claimed_by = OLD.passenger_user_id LIMIT 1;

    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m WHERE m.id = v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_user_id, recipient_filter)
    VALUES (
      v_offer.team_id, v_offer.match_id, 'carpool_passenger_left', 'Mitfahrer ausgestiegen',
      coalesce(v_passenger_name, '?') || ' fährt nicht mehr mit'
        || CASE WHEN v_opponent IS NOT NULL THEN ' (vs ' || v_opponent || ')' ELSE '' END,
      jsonb_build_object(
        'team_id',        v_offer.team_id,
        'match_id',       v_offer.match_id,
        'offer_id',       v_offer.id,
        'passenger_name', coalesce(v_passenger_name, '?'),
        'user_id',        OLD.passenger_user_id
      ),
      OLD.passenger_user_id, v_offer.driver_user_id, 'team'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_left_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_left ON public.cs_carpool_passengers;
CREATE TRIGGER trg_emit_carpool_passenger_left
  AFTER DELETE ON public.cs_carpool_passengers
  FOR EACH ROW EXECUTE FUNCTION fn_emit_carpool_passenger_left_event();


-- ── 8. Expense Share Paid ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_expense_share_paid_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_expense      record;
  v_debtor_name  text;
  v_amount_display text;
BEGIN
  IF NOT NEW.is_paid OR (OLD.is_paid IS NOT DISTINCT FROM true) THEN RETURN NEW; END IF;
  BEGIN
    SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id, e.amount_cents, e.currency
    INTO v_expense
    FROM public.cs_expenses e WHERE e.id = NEW.expense_id;
    IF v_expense IS NULL THEN RETURN NEW; END IF;
    IF NEW.user_id = v_expense.paid_by_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_debtor_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_expense.team_id AND tp.claimed_by = NEW.user_id LIMIT 1;

    v_amount_display := to_char(NEW.share_cents / 100.0, 'FM999990.00') || ' CHF';

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_user_id, recipient_filter, dedupe_key)
    VALUES (
      v_expense.team_id, v_expense.match_id, 'expense_share_paid', 'Spese bezahlt',
      coalesce(v_debtor_name, '?') || ' hat ' || v_amount_display || ' bezahlt (' || v_expense.title || ')',
      jsonb_build_object(
        'team_id',       v_expense.team_id,
        'match_id',      v_expense.match_id,
        'expense_id',    v_expense.id,
        'share_id',      NEW.id,
        'debtor_name',   coalesce(v_debtor_name, '?'),
        'share_cents',   NEW.share_cents,
        'expense_title', v_expense.title
      ),
      NEW.user_id, v_expense.paid_by_user_id, 'team', 'share_paid_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_paid_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_paid ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_paid
  AFTER UPDATE ON public.cs_expense_shares
  FOR EACH ROW EXECUTE FUNCTION fn_emit_expense_share_paid_event();


-- ── 9. Expense Share Due ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_expense_share_due_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_expense      record;
  v_payer_name   text;
  v_amount_display text;
BEGIN
  BEGIN
    SELECT e.id, e.team_id, e.match_id, e.title, e.paid_by_user_id, e.amount_cents, e.currency
    INTO v_expense
    FROM public.cs_expenses e WHERE e.id = NEW.expense_id;
    IF v_expense IS NULL THEN RETURN NEW; END IF;
    IF NEW.user_id = v_expense.paid_by_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_expense.team_id AND tp.claimed_by = v_expense.paid_by_user_id LIMIT 1;

    v_amount_display := to_char(NEW.share_cents / 100.0, 'FM999990.00') || ' CHF';

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_user_id, recipient_filter, dedupe_key)
    VALUES (
      v_expense.team_id, v_expense.match_id, 'expense_share_due', 'Offene Spese',
      v_amount_display || ' an ' || coalesce(v_payer_name, '?') || ' (' || v_expense.title || ')',
      jsonb_build_object(
        'team_id',       v_expense.team_id,
        'match_id',      v_expense.match_id,
        'expense_id',    v_expense.id,
        'share_id',      NEW.id,
        'payer_name',    coalesce(v_payer_name, '?'),
        'share_cents',   NEW.share_cents,
        'expense_title', v_expense.title
      ),
      v_expense.paid_by_user_id, NEW.user_id, 'team', 'share_due_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_due_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_expense_share_due ON public.cs_expense_shares;
CREATE TRIGGER trg_emit_expense_share_due
  AFTER INSERT ON public.cs_expense_shares
  FOR EACH ROW EXECUTE FUNCTION fn_emit_expense_share_due_event();


-- ── 10. Lineup Published ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_lineup_published_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opponent text;
  v_payload  jsonb;
BEGIN
  IF NEW.status = 'published'
     AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'published')
  THEN
    BEGIN
      SELECT m.opponent INTO v_opponent
      FROM public.cs_matches m WHERE m.id = NEW.match_id;

      v_payload := jsonb_build_object('team_id', NEW.team_id, 'match_id', NEW.match_id);
      IF NEW.id IS NOT NULL THEN
        v_payload := v_payload || jsonb_build_object('lineup_id', NEW.id);
      END IF;

      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload, created_by)
      VALUES (
        NEW.team_id, NEW.match_id, 'lineup_published',
        'Aufstellung veröffentlicht',
        'Die Aufstellung für ' || coalesce(v_opponent, '?') || ' ist online.',
        v_payload, NEW.created_by
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_emit_lineup_published_event failed: % (%)', SQLERRM, SQLSTATE;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_lineup_published_event ON public.cs_match_lineups;
CREATE TRIGGER trg_emit_lineup_published_event
  AFTER UPDATE ON public.cs_match_lineups
  FOR EACH ROW EXECUTE FUNCTION fn_emit_lineup_published_event();


-- ── 11. Lineup Event → cs_events ──────────────────────────────────
DROP FUNCTION IF EXISTS public.cs_event_payload_merge(jsonb, jsonb);
CREATE FUNCTION public.cs_event_payload_merge(
  base  jsonb,
  merge jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(base, '{}'::jsonb) || coalesce(merge, '{}'::jsonb);
$$;
GRANT EXECUTE ON FUNCTION public.cs_event_payload_merge(jsonb, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION fn_emit_lineup_event_to_cs_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opponent     text;
  v_promoted_uid uuid;
  v_captain_uid  uuid;
  v_payload      jsonb;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;

    v_payload := jsonb_build_object('team_id', NEW.team_id, 'match_id', NEW.match_id);

    IF NEW.payload IS NOT NULL AND jsonb_typeof(NEW.payload) = 'object' THEN
      v_payload := public.cs_event_payload_merge(v_payload, NEW.payload);
    END IF;
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
      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload, created_by)
      VALUES (
        NEW.team_id, NEW.match_id, 'replacement_promoted',
        'Ersatz ist nachgerückt',
        coalesce(NEW.payload->>'promoted_name', '?') || ' ersetzt ' || coalesce(NEW.payload->>'absent_name', '?'),
        v_payload, NEW.created_by
      );

      v_promoted_uid := (NEW.payload->>'to')::uuid;
      IF v_promoted_uid IS NOT NULL THEN
        INSERT INTO public.cs_events
          (team_id, match_id, event_type, title, body, payload, recipient_user_id, created_by)
        VALUES (
          NEW.team_id, NEW.match_id, 'replacement_promoted',
          'Du bist nachgerückt',
          'Du spielst nun im Match vs ' || coalesce(v_opponent, '?'),
          v_payload, v_promoted_uid, NEW.created_by
        );
      END IF;

    ELSIF NEW.event_type = 'no_reserve' THEN
      SELECT user_id INTO v_captain_uid
      FROM public.cs_team_members
      WHERE team_id = NEW.team_id AND role = 'captain' LIMIT 1;

      IF v_captain_uid IS NULL THEN
        SELECT created_by INTO v_captain_uid FROM public.cs_teams WHERE id = NEW.team_id;
      END IF;

      INSERT INTO public.cs_events
        (team_id, match_id, event_type, title, body, payload, created_by)
      VALUES (
        NEW.team_id, NEW.match_id, 'no_reserve_available',
        'Kein Ersatz verfügbar',
        coalesce(NEW.payload->>'absent_name', '?') || ' hat abgesagt – kein Ersatz!',
        v_payload, NEW.created_by
      );

      IF v_captain_uid IS NOT NULL THEN
        INSERT INTO public.cs_events
          (team_id, match_id, event_type, title, body, payload, recipient_user_id, created_by)
        VALUES (
          NEW.team_id, NEW.match_id, 'no_reserve_available',
          'Kein Ersatz verfügbar',
          coalesce(NEW.payload->>'absent_name', '?') || ' hat abgesagt – kein Ersatz verfügbar!',
          v_payload, v_captain_uid, NEW.created_by
        );
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_lineup_event_to_cs_events failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_lineup_event_to_cs_events ON public.cs_lineup_events;
CREATE TRIGGER trg_emit_lineup_event_to_cs_events
  AFTER INSERT ON public.cs_lineup_events
  FOR EACH ROW EXECUTE FUNCTION fn_emit_lineup_event_to_cs_events();


-- ── 12. Carpool Created ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emit_carpool_created_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_driver_name text;
  v_opponent    text;
BEGIN
  BEGIN
    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_driver_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = NEW.team_id AND tp.claimed_by = NEW.driver_user_id LIMIT 1;

    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter, dedupe_key)
    VALUES (
      NEW.team_id, NEW.match_id, 'carpool_offered', 'Neue Fahrgemeinschaft',
      coalesce(v_driver_name, '?') || ' bietet Fahrt an'
        || CASE WHEN v_opponent IS NOT NULL THEN ' (vs ' || v_opponent || ')' ELSE '' END,
      jsonb_build_object(
        'team_id',     NEW.team_id,
        'match_id',    NEW.match_id,
        'offer_id',    NEW.id,
        'driver_name', coalesce(v_driver_name, '?'),
        'seats_total', NEW.seats_total
      ),
      NEW.driver_user_id, 'team_no_reserves', 'carpool_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_created_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_emit_carpool_created_event ON public.cs_carpool_offers;
CREATE TRIGGER trg_emit_carpool_created_event
  AFTER INSERT ON public.cs_carpool_offers
  FOR EACH ROW EXECUTE FUNCTION fn_emit_carpool_created_event();


-- ── DIAGNOSE ──────────────────────────────────────────────────────
DO $$
DECLARE
  v_name text;
  v_ok   int := 0;
  v_fail int := 0;
BEGIN
  RAISE NOTICE '═══ Trigger-Prüfung ═══';
  FOR v_name IN VALUES
    ('trg_emit_availability_changed_event'),
    ('trg_emit_dinner_rsvp_event'),
    ('trg_cs_event_fanout'),
    ('trg_bridge_delivery_to_notification'),
    ('trg_emit_expense_created_event'),
    ('trg_emit_carpool_passenger_joined'),
    ('trg_emit_carpool_passenger_left'),
    ('trg_emit_expense_share_paid'),
    ('trg_emit_expense_share_due'),
    ('trg_emit_lineup_published_event'),
    ('trg_emit_lineup_event_to_cs_events'),
    ('trg_emit_carpool_created_event')
  LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = v_name) THEN
      RAISE NOTICE '  ✓ %', v_name;
      v_ok := v_ok + 1;
    ELSE
      RAISE WARNING '  ✗ FEHLT: %', v_name;
      v_fail := v_fail + 1;
    END IF;
  END LOOP;
  RAISE NOTICE '═══ Ergebnis: % OK, % fehlen ═══', v_ok, v_fail;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
