-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  EMERGENCY RECOVERY V2 – Vollständige Wiederherstellung        ║
-- ║  Erstellt ALLE Funktionen + Trigger neu.                       ║
-- ║  Jeder Block ist unabhängig: ein Fehler blockiert NICHT den    ║
-- ║  Rest. Sicher mehrfach ausführbar (idempotent).                ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  0. CLEANUP: Auto-Promotion + alte Trigger entfernen
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;
DROP TRIGGER IF EXISTS trg_cs_events_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS trg_on_event_create_enqueue_push ON public.cs_events;
DROP TRIGGER IF EXISTS cs_on_event_create_enqueue_push ON public.cs_events;
DROP FUNCTION IF EXISTS public.cs_on_event_create_enqueue_push();

-- ═══════════════════════════════════════════════════════════════════
--  1. fn_emit_availability_changed_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_availability_changed_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_team_id uuid; v_opponent text; v_player_name text;
  v_status_text text; v_title text; v_body text;
BEGIN
  BEGIN
    SELECT m.team_id, m.opponent INTO v_team_id, v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;
    IF v_team_id IS NULL THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id AND tp.claimed_by = NEW.user_id LIMIT 1;

    v_status_text := CASE NEW.status
      WHEN 'yes' THEN 'zugesagt' WHEN 'no' THEN 'abgesagt'
      WHEN 'maybe' THEN 'unsicher' ELSE NEW.status END;

    v_title := 'Verfügbarkeit: ' || initcap(v_status_text);
    v_body  := coalesce(v_player_name,'?') || ' hat ' || v_status_text
               || CASE WHEN v_opponent IS NOT NULL THEN ' (vs '||v_opponent||')' ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter)
    VALUES (v_team_id, NEW.match_id, 'availability_changed', v_title, v_body,
      jsonb_build_object('team_id',v_team_id,'match_id',NEW.match_id,'user_id',NEW.user_id,
        'status',NEW.status,'player_name',coalesce(v_player_name,'?')),
      NEW.user_id, 'captain');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_availability_changed_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_availability_changed_event ON public.cs_match_availability;
  CREATE TRIGGER trg_emit_availability_changed_event
    AFTER INSERT OR UPDATE ON public.cs_match_availability FOR EACH ROW
    EXECUTE FUNCTION fn_emit_availability_changed_event();
  RAISE NOTICE '✓ trg_emit_availability_changed_event erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_availability_changed_event FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  2. fn_emit_dinner_rsvp_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_dinner_rsvp_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_team_id uuid; v_opponent text; v_player_name text;
  v_status_text text; v_title text; v_body text;
BEGIN
  BEGIN
    SELECT m.team_id, m.opponent INTO v_team_id, v_opponent
    FROM public.cs_matches m WHERE m.id = NEW.match_id;
    IF v_team_id IS NULL THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id AND tp.claimed_by = NEW.user_id LIMIT 1;

    v_status_text := CASE NEW.status
      WHEN 'yes' THEN 'isst mit' WHEN 'no' THEN 'isst nicht mit'
      WHEN 'maybe' THEN 'ist unsicher' ELSE NEW.status END;

    v_title := CASE NEW.status
      WHEN 'yes' THEN 'Essen: Zusage' WHEN 'no' THEN 'Essen: Absage'
      WHEN 'maybe' THEN 'Essen: Unsicher' ELSE 'Essen: '||NEW.status END;

    v_body := coalesce(v_player_name,'?') || ' ' || v_status_text
              || CASE WHEN v_opponent IS NOT NULL THEN ' (vs '||v_opponent||')' ELSE '' END;

    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by, recipient_filter)
    VALUES (v_team_id, NEW.match_id, 'dinner_rsvp', v_title, v_body,
      jsonb_build_object('team_id',v_team_id,'match_id',NEW.match_id,'user_id',NEW.user_id,
        'status',NEW.status,'player_name',coalesce(v_player_name,'?')),
      NEW.user_id, 'captain');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_dinner_rsvp_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
  CREATE TRIGGER trg_emit_dinner_rsvp_event
    AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps FOR EACH ROW
    EXECUTE FUNCTION fn_emit_dinner_rsvp_event();
  RAISE NOTICE '✓ trg_emit_dinner_rsvp_event erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_dinner_rsvp_event FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  3. fn_cs_event_fanout  ★ WICHTIGSTER TRIGGER ★
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cs_event_fanout()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user record; v_prefs record; v_status text; v_filter text;
BEGIN
  BEGIN
    v_filter := coalesce(NEW.recipient_filter, 'team');
    FOR v_user IN
      SELECT DISTINCT x.user_id FROM (
        SELECT ls.user_id FROM public.cs_match_lineup_slots ls
        WHERE v_filter='lineup_starters' AND NEW.match_id IS NOT NULL
          AND ls.match_id=NEW.match_id AND ls.slot_type='starter' AND ls.user_id IS NOT NULL
        UNION
        SELECT tm.user_id FROM public.cs_team_members tm
        WHERE v_filter='team_no_reserves' AND tm.team_id=NEW.team_id AND tm.user_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.cs_match_lineup_slots ls
            WHERE ls.match_id=NEW.match_id AND ls.user_id=tm.user_id AND ls.slot_type='reserve')
        UNION
        SELECT tm.user_id FROM public.cs_team_members tm
        WHERE v_filter='captain' AND tm.team_id=NEW.team_id AND tm.role='captain' AND tm.user_id IS NOT NULL
        UNION
        SELECT t.created_by FROM public.cs_teams t
        WHERE v_filter='captain' AND t.id=NEW.team_id AND t.created_by IS NOT NULL
        UNION
        SELECT tm.user_id FROM public.cs_team_members tm
        WHERE v_filter='team' AND tm.team_id=NEW.team_id AND tm.user_id IS NOT NULL
      ) x
      WHERE (NEW.recipient_user_id IS NULL OR x.user_id=NEW.recipient_user_id)
        AND (NEW.created_by IS NULL OR x.user_id <> NEW.created_by)
    LOOP
      BEGIN
        SELECT np.push_enabled, np.types_disabled INTO v_prefs
        FROM public.cs_notification_prefs np
        WHERE np.user_id=v_user.user_id AND np.team_id=NEW.team_id;
        IF NOT FOUND THEN
          SELECT np.push_enabled, np.types_disabled INTO v_prefs
          FROM public.cs_notification_prefs np
          WHERE np.user_id=v_user.user_id AND np.team_id IS NULL;
        END IF;
      EXCEPTION WHEN OTHERS THEN v_prefs := NULL; END;

      IF v_prefs IS NOT NULL AND (v_prefs.push_enabled=false OR NEW.event_type=ANY(v_prefs.types_disabled))
      THEN v_status := 'skipped'; ELSE v_status := 'pending'; END IF;

      INSERT INTO public.cs_event_deliveries (event_id, user_id, channel, status)
      VALUES (NEW.id, v_user.user_id, 'push', v_status)
      ON CONFLICT (event_id, user_id, channel) DO NOTHING;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_cs_event_fanout failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_cs_event_fanout ON public.cs_events;
  CREATE TRIGGER trg_cs_event_fanout
    AFTER INSERT ON public.cs_events FOR EACH ROW
    EXECUTE FUNCTION fn_cs_event_fanout();
  RAISE NOTICE '✓ trg_cs_event_fanout erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_cs_event_fanout FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. fn_bridge_delivery_to_notification  ★ WICHTIG ★
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_bridge_delivery_to_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event record;
BEGIN
  IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
  BEGIN
    SELECT e.event_type, e.title, e.body, e.payload, e.match_id, e.team_id INTO v_event
    FROM public.cs_events e WHERE e.id = NEW.event_id;
    IF v_event IS NULL THEN RETURN NEW; END IF;
    INSERT INTO public.cs_notifications
      (recipient_user_id, type, title, body, payload, match_id, team_id)
    VALUES (NEW.user_id, v_event.event_type, v_event.title, v_event.body,
            v_event.payload, v_event.match_id, v_event.team_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_bridge_delivery_to_notification failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_bridge_delivery_to_notification ON public.cs_event_deliveries;
  CREATE TRIGGER trg_bridge_delivery_to_notification
    AFTER INSERT ON public.cs_event_deliveries FOR EACH ROW
    EXECUTE FUNCTION fn_bridge_delivery_to_notification();
  RAISE NOTICE '✓ trg_bridge_delivery_to_notification erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_bridge_delivery_to_notification FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  5. fn_emit_expense_created_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_expense_created_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_opponent text; v_payer_name text; v_amount_display text;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=NEW.match_id;
    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp WHERE tp.team_id=NEW.team_id AND tp.claimed_by=NEW.paid_by_user_id LIMIT 1;
    v_amount_display := to_char(NEW.amount_cents/100.0,'FM999990.00')||' '||NEW.currency;
    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_filter,dedupe_key)
    VALUES (NEW.team_id,NEW.match_id,'expense_added','Neue Spese',
      coalesce(v_payer_name,'?')||': '||NEW.title||' – '||v_amount_display,
      jsonb_build_object('team_id',NEW.team_id,'match_id',NEW.match_id,'expense_id',NEW.id,
        'title',NEW.title,'amount_cents',NEW.amount_cents,'currency',NEW.currency,
        'payer_name',coalesce(v_payer_name,'?')),
      NEW.paid_by_user_id,'team','expense_'||NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_created_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_expense_created_event ON public.cs_expenses;
  CREATE TRIGGER trg_emit_expense_created_event
    AFTER INSERT ON public.cs_expenses FOR EACH ROW
    EXECUTE FUNCTION fn_emit_expense_created_event();
  RAISE NOTICE '✓ trg_emit_expense_created_event erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_expense_created_event FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  6. fn_emit_carpool_passenger_joined_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_joined_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_offer record; v_passenger_name text; v_opponent text;
BEGIN
  BEGIN
    SELECT o.id,o.team_id,o.match_id,o.driver_user_id,o.seats_total INTO v_offer
    FROM public.cs_carpool_offers o WHERE o.id=NEW.offer_id;
    IF v_offer IS NULL THEN RETURN NEW; END IF;
    IF NEW.passenger_user_id=v_offer.driver_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp WHERE tp.team_id=v_offer.team_id AND tp.claimed_by=NEW.passenger_user_id LIMIT 1;
    SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_user_id,recipient_filter)
    VALUES (v_offer.team_id,v_offer.match_id,'carpool_passenger_joined','Mitfahrer',
      coalesce(v_passenger_name,'?')||' fährt mit'
        ||CASE WHEN v_opponent IS NOT NULL THEN ' (vs '||v_opponent||')' ELSE '' END,
      jsonb_build_object('team_id',v_offer.team_id,'match_id',v_offer.match_id,
        'offer_id',v_offer.id,'passenger_name',coalesce(v_passenger_name,'?'),
        'user_id',NEW.passenger_user_id),
      NEW.passenger_user_id, v_offer.driver_user_id, 'team');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_joined_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_joined ON public.cs_carpool_passengers;
  CREATE TRIGGER trg_emit_carpool_passenger_joined
    AFTER INSERT ON public.cs_carpool_passengers FOR EACH ROW
    EXECUTE FUNCTION fn_emit_carpool_passenger_joined_event();
  RAISE NOTICE '✓ trg_emit_carpool_passenger_joined erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_carpool_passenger_joined FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  7. fn_emit_carpool_passenger_left_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_carpool_passenger_left_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_offer record; v_passenger_name text; v_opponent text;
BEGIN
  BEGIN
    SELECT o.id,o.team_id,o.match_id,o.driver_user_id,o.seats_total INTO v_offer
    FROM public.cs_carpool_offers o WHERE o.id=OLD.offer_id;
    IF v_offer IS NULL THEN RETURN OLD; END IF;
    IF OLD.passenger_user_id=v_offer.driver_user_id THEN RETURN OLD; END IF;

    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_passenger_name
    FROM public.cs_team_players tp WHERE tp.team_id=v_offer.team_id AND tp.claimed_by=OLD.passenger_user_id LIMIT 1;
    SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=v_offer.match_id;

    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_user_id,recipient_filter)
    VALUES (v_offer.team_id,v_offer.match_id,'carpool_passenger_left','Mitfahrer ausgestiegen',
      coalesce(v_passenger_name,'?')||' fährt nicht mehr mit'
        ||CASE WHEN v_opponent IS NOT NULL THEN ' (vs '||v_opponent||')' ELSE '' END,
      jsonb_build_object('team_id',v_offer.team_id,'match_id',v_offer.match_id,
        'offer_id',v_offer.id,'passenger_name',coalesce(v_passenger_name,'?'),
        'user_id',OLD.passenger_user_id),
      OLD.passenger_user_id, v_offer.driver_user_id, 'team');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_passenger_left_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN OLD;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_carpool_passenger_left ON public.cs_carpool_passengers;
  CREATE TRIGGER trg_emit_carpool_passenger_left
    AFTER DELETE ON public.cs_carpool_passengers FOR EACH ROW
    EXECUTE FUNCTION fn_emit_carpool_passenger_left_event();
  RAISE NOTICE '✓ trg_emit_carpool_passenger_left erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_carpool_passenger_left FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  8. fn_emit_expense_share_paid_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_expense_share_paid_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_expense record; v_debtor_name text; v_amount_display text;
BEGIN
  IF NOT NEW.is_paid OR (OLD.is_paid IS NOT DISTINCT FROM true) THEN RETURN NEW; END IF;
  BEGIN
    SELECT e.id,e.team_id,e.match_id,e.title,e.paid_by_user_id,e.amount_cents,e.currency INTO v_expense
    FROM public.cs_expenses e WHERE e.id=NEW.expense_id;
    IF v_expense IS NULL THEN RETURN NEW; END IF;
    IF NEW.user_id=v_expense.paid_by_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_debtor_name
    FROM public.cs_team_players tp WHERE tp.team_id=v_expense.team_id AND tp.claimed_by=NEW.user_id LIMIT 1;
    v_amount_display := to_char(NEW.share_cents/100.0,'FM999990.00')||' CHF';

    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_user_id,recipient_filter,dedupe_key)
    VALUES (v_expense.team_id,v_expense.match_id,'expense_share_paid','Spese bezahlt',
      coalesce(v_debtor_name,'?')||' hat '||v_amount_display||' bezahlt ('||v_expense.title||')',
      jsonb_build_object('team_id',v_expense.team_id,'match_id',v_expense.match_id,
        'expense_id',v_expense.id,'share_id',NEW.id,'debtor_name',coalesce(v_debtor_name,'?'),
        'share_cents',NEW.share_cents,'expense_title',v_expense.title),
      NEW.user_id, v_expense.paid_by_user_id, 'team', 'share_paid_'||NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_paid_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_expense_share_paid ON public.cs_expense_shares;
  CREATE TRIGGER trg_emit_expense_share_paid
    AFTER UPDATE ON public.cs_expense_shares FOR EACH ROW
    EXECUTE FUNCTION fn_emit_expense_share_paid_event();
  RAISE NOTICE '✓ trg_emit_expense_share_paid erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_expense_share_paid FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  9. fn_emit_expense_share_due_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_expense_share_due_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_expense record; v_payer_name text; v_amount_display text;
BEGIN
  BEGIN
    SELECT e.id,e.team_id,e.match_id,e.title,e.paid_by_user_id,e.amount_cents,e.currency INTO v_expense
    FROM public.cs_expenses e WHERE e.id=NEW.expense_id;
    IF v_expense IS NULL THEN RETURN NEW; END IF;
    IF NEW.user_id=v_expense.paid_by_user_id THEN RETURN NEW; END IF;

    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_payer_name
    FROM public.cs_team_players tp WHERE tp.team_id=v_expense.team_id AND tp.claimed_by=v_expense.paid_by_user_id LIMIT 1;
    v_amount_display := to_char(NEW.share_cents/100.0,'FM999990.00')||' CHF';

    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_user_id,recipient_filter,dedupe_key)
    VALUES (v_expense.team_id,v_expense.match_id,'expense_share_due','Offene Spese',
      v_amount_display||' an '||coalesce(v_payer_name,'?')||' ('||v_expense.title||')',
      jsonb_build_object('team_id',v_expense.team_id,'match_id',v_expense.match_id,
        'expense_id',v_expense.id,'share_id',NEW.id,'payer_name',coalesce(v_payer_name,'?'),
        'share_cents',NEW.share_cents,'expense_title',v_expense.title),
      v_expense.paid_by_user_id, NEW.user_id, 'team', 'share_due_'||NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_expense_share_due_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_expense_share_due ON public.cs_expense_shares;
  CREATE TRIGGER trg_emit_expense_share_due
    AFTER INSERT ON public.cs_expense_shares FOR EACH ROW
    EXECUTE FUNCTION fn_emit_expense_share_due_event();
  RAISE NOTICE '✓ trg_emit_expense_share_due erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_expense_share_due FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  10. fn_emit_lineup_published_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_lineup_published_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_opponent text; v_payload jsonb;
BEGIN
  IF NEW.status='published' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'published') THEN
    BEGIN
      SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=NEW.match_id;
      v_payload := jsonb_build_object('team_id',NEW.team_id,'match_id',NEW.match_id);
      IF NEW.id IS NOT NULL THEN v_payload := v_payload||jsonb_build_object('lineup_id',NEW.id); END IF;

      INSERT INTO public.cs_events
        (team_id,match_id,event_type,title,body,payload,created_by)
      VALUES (NEW.team_id,NEW.match_id,'lineup_published','Aufstellung veröffentlicht',
        'Die Aufstellung für '||coalesce(v_opponent,'?')||' ist online.',
        v_payload, NEW.created_by);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_emit_lineup_published_event failed: % (%)', SQLERRM, SQLSTATE;
    END;
  END IF;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_lineup_published_event ON public.cs_match_lineups;
  CREATE TRIGGER trg_emit_lineup_published_event
    AFTER UPDATE ON public.cs_match_lineups FOR EACH ROW
    EXECUTE FUNCTION fn_emit_lineup_published_event();
  RAISE NOTICE '✓ trg_emit_lineup_published_event erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_lineup_published_event FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  11. fn_emit_lineup_event_to_cs_events  (auto-promotion → push)
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.cs_event_payload_merge(jsonb, jsonb);
CREATE FUNCTION public.cs_event_payload_merge(base jsonb, merge jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(base,'{}'::jsonb) || coalesce(merge,'{}'::jsonb);
$$;
GRANT EXECUTE ON FUNCTION public.cs_event_payload_merge(jsonb, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION fn_emit_lineup_event_to_cs_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opponent text; v_promoted_uid uuid; v_captain_uid uuid; v_payload jsonb;
BEGIN
  BEGIN
    SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=NEW.match_id;
    v_payload := jsonb_build_object('team_id',NEW.team_id,'match_id',NEW.match_id);
    IF NEW.payload IS NOT NULL AND jsonb_typeof(NEW.payload)='object' THEN
      v_payload := public.cs_event_payload_merge(v_payload, NEW.payload);
    END IF;
    IF NEW.payload ? 'promoted_name' THEN v_payload := v_payload||jsonb_build_object('in_name',NEW.payload->>'promoted_name'); END IF;
    IF NEW.payload ? 'absent_name' THEN v_payload := v_payload||jsonb_build_object('out_name',NEW.payload->>'absent_name'); END IF;
    IF NEW.payload ? 'to' THEN v_payload := v_payload||jsonb_build_object('in_member_id',NEW.payload->>'to'); END IF;
    IF NEW.payload ? 'from' THEN v_payload := v_payload||jsonb_build_object('out_member_id',NEW.payload->>'from'); END IF;
    IF NEW.created_by IS NOT NULL THEN v_payload := v_payload||jsonb_build_object('actor',NEW.created_by); END IF;

    IF NEW.event_type='auto_promotion' THEN
      INSERT INTO public.cs_events (team_id,match_id,event_type,title,body,payload,created_by)
      VALUES (NEW.team_id,NEW.match_id,'replacement_promoted','Ersatz ist nachgerückt',
        coalesce(NEW.payload->>'promoted_name','?')||' ersetzt '||coalesce(NEW.payload->>'absent_name','?'),
        v_payload, NEW.created_by);
      v_promoted_uid := (NEW.payload->>'to')::uuid;
      IF v_promoted_uid IS NOT NULL THEN
        INSERT INTO public.cs_events (team_id,match_id,event_type,title,body,payload,recipient_user_id,created_by)
        VALUES (NEW.team_id,NEW.match_id,'replacement_promoted','Du bist nachgerückt',
          'Du spielst nun im Match vs '||coalesce(v_opponent,'?'), v_payload, v_promoted_uid, NEW.created_by);
      END IF;
    ELSIF NEW.event_type='no_reserve' THEN
      SELECT user_id INTO v_captain_uid FROM public.cs_team_members
      WHERE team_id=NEW.team_id AND role='captain' LIMIT 1;
      IF v_captain_uid IS NULL THEN
        SELECT created_by INTO v_captain_uid FROM public.cs_teams WHERE id=NEW.team_id;
      END IF;
      INSERT INTO public.cs_events (team_id,match_id,event_type,title,body,payload,created_by)
      VALUES (NEW.team_id,NEW.match_id,'no_reserve_available','Kein Ersatz verfügbar',
        coalesce(NEW.payload->>'absent_name','?')||' hat abgesagt – kein Ersatz!', v_payload, NEW.created_by);
      IF v_captain_uid IS NOT NULL THEN
        INSERT INTO public.cs_events (team_id,match_id,event_type,title,body,payload,recipient_user_id,created_by)
        VALUES (NEW.team_id,NEW.match_id,'no_reserve_available','Kein Ersatz verfügbar',
          coalesce(NEW.payload->>'absent_name','?')||' hat abgesagt – kein Ersatz verfügbar!',
          v_payload, v_captain_uid, NEW.created_by);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_lineup_event_to_cs_events failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  CREATE TABLE IF NOT EXISTS public.cs_lineup_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(), match_id uuid NOT NULL,
    team_id uuid NOT NULL, event_type text NOT NULL, payload jsonb,
    created_by uuid, created_at timestamptz NOT NULL DEFAULT now()
  );
  DROP TRIGGER IF EXISTS trg_emit_lineup_event_to_cs_events ON public.cs_lineup_events;
  CREATE TRIGGER trg_emit_lineup_event_to_cs_events
    AFTER INSERT ON public.cs_lineup_events FOR EACH ROW
    EXECUTE FUNCTION fn_emit_lineup_event_to_cs_events();
  RAISE NOTICE '✓ trg_emit_lineup_event_to_cs_events erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_lineup_event_to_cs_events FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  12. fn_emit_carpool_created_event
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_emit_carpool_created_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_driver_name text; v_opponent text;
BEGIN
  BEGIN
    SELECT CONCAT_WS(' ',tp.first_name,tp.last_name) INTO v_driver_name
    FROM public.cs_team_players tp WHERE tp.team_id=NEW.team_id AND tp.claimed_by=NEW.driver_user_id LIMIT 1;
    SELECT m.opponent INTO v_opponent FROM public.cs_matches m WHERE m.id=NEW.match_id;
    INSERT INTO public.cs_events
      (team_id,match_id,event_type,title,body,payload,created_by,recipient_filter,dedupe_key)
    VALUES (NEW.team_id,NEW.match_id,'carpool_offered','Neue Fahrgemeinschaft',
      coalesce(v_driver_name,'?')||' bietet Fahrt an'
        ||CASE WHEN v_opponent IS NOT NULL THEN ' (vs '||v_opponent||')' ELSE '' END,
      jsonb_build_object('team_id',NEW.team_id,'match_id',NEW.match_id,'offer_id',NEW.id,
        'driver_name',coalesce(v_driver_name,'?'),'seats_total',NEW.seats_total),
      NEW.driver_user_id, 'team_no_reserves', 'carpool_'||NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_carpool_created_event failed: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END; $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_emit_carpool_created_event ON public.cs_carpool_offers;
  CREATE TRIGGER trg_emit_carpool_created_event
    AFTER INSERT ON public.cs_carpool_offers FOR EACH ROW
    EXECUTE FUNCTION fn_emit_carpool_created_event();
  RAISE NOTICE '✓ trg_emit_carpool_created_event erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ trg_emit_carpool_created_event FEHLER: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  13. DIAGNOSE
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_trigger_name text; v_table_name text; v_found boolean;
BEGIN
  RAISE NOTICE '═══════════════════════════════════';
  RAISE NOTICE '  ERGEBNIS – Trigger-Status';
  RAISE NOTICE '═══════════════════════════════════';
  FOR v_trigger_name, v_table_name IN VALUES
    ('trg_emit_availability_changed_event','cs_match_availability'),
    ('trg_emit_dinner_rsvp_event','cs_dinner_rsvps'),
    ('trg_cs_event_fanout','cs_events'),
    ('trg_bridge_delivery_to_notification','cs_event_deliveries'),
    ('trg_emit_expense_created_event','cs_expenses'),
    ('trg_emit_carpool_passenger_joined','cs_carpool_passengers'),
    ('trg_emit_carpool_passenger_left','cs_carpool_passengers'),
    ('trg_emit_expense_share_paid','cs_expense_shares'),
    ('trg_emit_expense_share_due','cs_expense_shares'),
    ('trg_emit_lineup_published_event','cs_match_lineups'),
    ('trg_emit_lineup_event_to_cs_events','cs_lineup_events'),
    ('trg_emit_carpool_created_event','cs_carpool_offers')
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger t JOIN pg_class c ON t.tgrelid=c.oid
      WHERE t.tgname=v_trigger_name AND c.relname=v_table_name
    ) INTO v_found;
    IF v_found THEN RAISE NOTICE '✓ %', v_trigger_name;
    ELSE RAISE WARNING '✗ FEHLT: %', v_trigger_name; END IF;
  END LOOP;

  -- Auto-promote muss weg sein
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_auto_promote_on_absence') INTO v_found;
  IF v_found THEN RAISE WARNING '✗ trg_auto_promote_on_absence existiert noch!';
  ELSE RAISE NOTICE '✓ trg_auto_promote_on_absence entfernt (gut)'; END IF;

  -- Alte Trigger dürfen nicht existieren
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname IN
    ('trg_cs_events_enqueue_push','trg_on_event_create_enqueue_push','cs_on_event_create_enqueue_push')
  ) INTO v_found;
  IF v_found THEN RAISE WARNING '✗ Alter störender Trigger auf cs_events gefunden!';
  ELSE RAISE NOTICE '✓ Keine alten störenden Trigger'; END IF;

  RAISE NOTICE '═══════════════════════════════════';
END $$;

-- ═══════════════════════════════════════════════════════════════════
--  14. HELPER-FUNKTIONEN für RLS (müssen existieren!)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.cs_team_members WHERE team_id=p_team_id AND user_id=auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO anon;

CREATE OR REPLACE FUNCTION public.is_team_admin(p_team_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.cs_team_members WHERE team_id=p_team_id AND user_id=auth.uid() AND role='captain');
$$;
GRANT EXECUTE ON FUNCTION public.is_team_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_admin(uuid) TO anon;

CREATE OR REPLACE FUNCTION public.is_team_creator(p_team_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.cs_teams WHERE id=p_team_id AND created_by=auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.is_team_creator(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_creator(uuid) TO anon;


-- ═══════════════════════════════════════════════════════════════════
--  15. RLS-POLICIES für cs_match_availability
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE public.cs_match_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_match_availability_select ON public.cs_match_availability;
CREATE POLICY cs_match_availability_select ON public.cs_match_availability
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_insert ON public.cs_match_availability;
CREATE POLICY cs_match_availability_insert ON public.cs_match_availability
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_update ON public.cs_match_availability;
CREATE POLICY cs_match_availability_update ON public.cs_match_availability
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_delete ON public.cs_match_availability;
CREATE POLICY cs_match_availability_delete ON public.cs_match_availability
  FOR DELETE USING (user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  16. RLS-POLICIES für cs_events
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE public.cs_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_events_select ON public.cs_events;
CREATE POLICY cs_events_select ON public.cs_events
  FOR SELECT USING (
    public.is_team_member(team_id)
    OR recipient_user_id = auth.uid()
  );

DROP POLICY IF EXISTS cs_events_insert ON public.cs_events;
CREATE POLICY cs_events_insert ON public.cs_events
  FOR INSERT WITH CHECK (true);


-- ═══════════════════════════════════════════════════════════════════
--  17. RLS-POLICIES für cs_event_deliveries
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE public.cs_event_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_event_deliveries_select ON public.cs_event_deliveries;
CREATE POLICY cs_event_deliveries_select ON public.cs_event_deliveries
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS cs_event_deliveries_insert ON public.cs_event_deliveries;
CREATE POLICY cs_event_deliveries_insert ON public.cs_event_deliveries
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS cs_event_deliveries_update ON public.cs_event_deliveries;
CREATE POLICY cs_event_deliveries_update ON public.cs_event_deliveries
  FOR UPDATE USING (true);


-- ═══════════════════════════════════════════════════════════════════
--  18. RLS-POLICIES für cs_notifications
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE public.cs_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_notifications_select ON public.cs_notifications;
CREATE POLICY cs_notifications_select ON public.cs_notifications
  FOR SELECT USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS cs_notifications_insert ON public.cs_notifications;
CREATE POLICY cs_notifications_insert ON public.cs_notifications
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS cs_notifications_update ON public.cs_notifications;
CREATE POLICY cs_notifications_update ON public.cs_notifications
  FOR UPDATE USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS cs_notifications_delete ON public.cs_notifications;
CREATE POLICY cs_notifications_delete ON public.cs_notifications
  FOR DELETE USING (recipient_user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  19. RLS-POLICIES für cs_dinner_rsvps
-- ═══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  ALTER TABLE public.cs_dinner_rsvps ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS cs_dinner_rsvps_select ON public.cs_dinner_rsvps;
  CREATE POLICY cs_dinner_rsvps_select ON public.cs_dinner_rsvps
    FOR SELECT USING (
      EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
    );

  DROP POLICY IF EXISTS cs_dinner_rsvps_insert ON public.cs_dinner_rsvps;
  CREATE POLICY cs_dinner_rsvps_insert ON public.cs_dinner_rsvps
    FOR INSERT WITH CHECK (
      user_id = auth.uid()
      AND EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
    );

  DROP POLICY IF EXISTS cs_dinner_rsvps_update ON public.cs_dinner_rsvps;
  CREATE POLICY cs_dinner_rsvps_update ON public.cs_dinner_rsvps
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (
      user_id = auth.uid()
      AND EXISTS (SELECT 1 FROM public.cs_matches m WHERE m.id=match_id AND public.is_team_member(m.team_id))
    );

  DROP POLICY IF EXISTS cs_dinner_rsvps_delete ON public.cs_dinner_rsvps;
  CREATE POLICY cs_dinner_rsvps_delete ON public.cs_dinner_rsvps
    FOR DELETE USING (user_id = auth.uid());

  RAISE NOTICE '✓ cs_dinner_rsvps RLS policies erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ cs_dinner_rsvps RLS policies: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  20. RLS-POLICIES für cs_carpool_offers + cs_carpool_passengers
-- ═══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  ALTER TABLE public.cs_carpool_offers ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS cs_carpool_offers_select ON public.cs_carpool_offers;
  CREATE POLICY cs_carpool_offers_select ON public.cs_carpool_offers
    FOR SELECT USING (public.is_team_member(team_id));

  DROP POLICY IF EXISTS cs_carpool_offers_insert ON public.cs_carpool_offers;
  CREATE POLICY cs_carpool_offers_insert ON public.cs_carpool_offers
    FOR INSERT WITH CHECK (driver_user_id = auth.uid() AND public.is_team_member(team_id));

  DROP POLICY IF EXISTS cs_carpool_offers_update ON public.cs_carpool_offers;
  CREATE POLICY cs_carpool_offers_update ON public.cs_carpool_offers
    FOR UPDATE USING (driver_user_id = auth.uid());

  DROP POLICY IF EXISTS cs_carpool_offers_delete ON public.cs_carpool_offers;
  CREATE POLICY cs_carpool_offers_delete ON public.cs_carpool_offers
    FOR DELETE USING (driver_user_id = auth.uid());

  RAISE NOTICE '✓ cs_carpool_offers RLS policies erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ cs_carpool_offers RLS policies: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE public.cs_carpool_passengers ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS cs_carpool_passengers_select ON public.cs_carpool_passengers;
  CREATE POLICY cs_carpool_passengers_select ON public.cs_carpool_passengers
    FOR SELECT USING (
      EXISTS (SELECT 1 FROM public.cs_carpool_offers o WHERE o.id=offer_id AND public.is_team_member(o.team_id))
    );

  DROP POLICY IF EXISTS cs_carpool_passengers_insert ON public.cs_carpool_passengers;
  CREATE POLICY cs_carpool_passengers_insert ON public.cs_carpool_passengers
    FOR INSERT WITH CHECK (passenger_user_id = auth.uid());

  DROP POLICY IF EXISTS cs_carpool_passengers_delete ON public.cs_carpool_passengers;
  CREATE POLICY cs_carpool_passengers_delete ON public.cs_carpool_passengers
    FOR DELETE USING (passenger_user_id = auth.uid());

  RAISE NOTICE '✓ cs_carpool_passengers RLS policies erstellt';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '✗ cs_carpool_passengers RLS policies: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  21. cs_event_reads Tabelle + RPCs (für Benachrichtigungen löschen)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cs_event_reads (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid        NOT NULL REFERENCES public.cs_events(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL DEFAULT auth.uid(),
  read_at     timestamptz NOT NULL DEFAULT now(),
  dismissed_at timestamptz,
  UNIQUE (event_id, user_id)
);
ALTER TABLE public.cs_event_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_event_reads_select ON public.cs_event_reads;
CREATE POLICY cs_event_reads_select ON public.cs_event_reads FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS cs_event_reads_insert ON public.cs_event_reads;
CREATE POLICY cs_event_reads_insert ON public.cs_event_reads FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS cs_event_reads_update ON public.cs_event_reads;
CREATE POLICY cs_event_reads_update ON public.cs_event_reads FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS cs_event_reads_delete ON public.cs_event_reads;
CREATE POLICY cs_event_reads_delete ON public.cs_event_reads FOR DELETE USING (user_id = auth.uid());

-- Mark single event as read
CREATE OR REPLACE FUNCTION public.cs_mark_event_read(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id)
  VALUES (p_event_id, auth.uid())
  ON CONFLICT (event_id, user_id) DO UPDATE SET read_at = now();
END; $$;
GRANT EXECUTE ON FUNCTION public.cs_mark_event_read(uuid) TO authenticated;

-- Mark ALL events as read
CREATE OR REPLACE FUNCTION public.cs_mark_all_events_read()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id)
  SELECT e.id, auth.uid() FROM public.cs_events e
  WHERE NOT EXISTS (
    SELECT 1 FROM public.cs_event_reads r WHERE r.event_id=e.id AND r.user_id=auth.uid()
  )
  AND (
    public.is_team_member(e.team_id)
    OR e.recipient_user_id = auth.uid()
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.cs_mark_all_events_read() TO authenticated;

-- Unread count (DROP first: return type may differ)
DROP FUNCTION IF EXISTS public.cs_unread_event_count();
CREATE OR REPLACE FUNCTION public.cs_unread_event_count()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*) FROM public.cs_events e
  WHERE (public.is_team_member(e.team_id) OR e.recipient_user_id=auth.uid())
    AND NOT EXISTS (SELECT 1 FROM public.cs_event_reads r WHERE r.event_id=e.id AND r.user_id=auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.cs_unread_event_count() TO authenticated;

-- Dismiss single event (permanent hide)
CREATE OR REPLACE FUNCTION public.cs_dismiss_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, dismissed_at)
  VALUES (p_event_id, auth.uid(), now())
  ON CONFLICT (event_id, user_id) DO UPDATE SET dismissed_at = now();
END; $$;
GRANT EXECUTE ON FUNCTION public.cs_dismiss_event(uuid) TO authenticated;

-- Dismiss ALL events (permanent hide)
CREATE OR REPLACE FUNCTION public.cs_dismiss_all_events()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.cs_event_reads (event_id, user_id, dismissed_at)
  SELECT e.id, auth.uid(), now() FROM public.cs_events e
  WHERE (public.is_team_member(e.team_id) OR e.recipient_user_id=auth.uid())
  ON CONFLICT (event_id, user_id) DO UPDATE SET dismissed_at = now();
END; $$;
GRANT EXECUTE ON FUNCTION public.cs_dismiss_all_events() TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  FINAL: Abschluss-Diagnose
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE v_count int;
BEGIN
  RAISE NOTICE '═══ RLS-Policy Prüfung ═══';

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_match_availability';
  RAISE NOTICE 'cs_match_availability: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_events';
  RAISE NOTICE 'cs_events: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_event_deliveries';
  RAISE NOTICE 'cs_event_deliveries: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_notifications';
  RAISE NOTICE 'cs_notifications: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_dinner_rsvps';
  RAISE NOTICE 'cs_dinner_rsvps: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_carpool_offers';
  RAISE NOTICE 'cs_carpool_offers: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_carpool_passengers';
  RAISE NOTICE 'cs_carpool_passengers: % policies', v_count;

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename='cs_event_reads';
  RAISE NOTICE 'cs_event_reads: % policies', v_count;

  -- Verify no problematic triggers
  SELECT count(*) INTO v_count FROM pg_trigger WHERE tgname='trg_auto_promote_on_absence';
  IF v_count > 0 THEN RAISE WARNING '✗ trg_auto_promote_on_absence existiert noch!';
  ELSE RAISE NOTICE '✓ trg_auto_promote_on_absence entfernt'; END IF;

  RAISE NOTICE '═══ Fertig ═══';
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
