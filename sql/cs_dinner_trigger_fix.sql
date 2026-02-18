-- ═══════════════════════════════════════════════════════════════════
--  DINNER TRIGGER FIX – Standalone
--  Bitte im Supabase SQL Editor ausführen.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Prüfe zuerst die aktuelle Funktion:
--    Zeigt ob die alte Skip-Logik noch drin ist
SELECT CASE
  WHEN prosrc LIKE '%OLD.status = NEW.status%'
    THEN '❌ ALTE VERSION: Skip-Logik ist noch aktiv!'
  ELSE '✅ NEUE VERSION: Keine Skip-Logik'
END AS fn_status,
substring(prosrc for 200) AS fn_preview
FROM pg_proc
WHERE proname = 'fn_emit_dinner_rsvp_event';


-- 2. Funktion NEU erstellen (OHNE Skip-Logik)
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
  -- KEIN Skip: Captain wird bei JEDEM Klick benachrichtigt

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
    );

    RAISE NOTICE 'dinner_rsvp event created for user % match %', NEW.user_id, NEW.match_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_emit_dinner_rsvp_event failed: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- 3. Trigger neu erstellen
DROP TRIGGER IF EXISTS trg_emit_dinner_rsvp_event ON public.cs_dinner_rsvps;
CREATE TRIGGER trg_emit_dinner_rsvp_event
  AFTER INSERT OR UPDATE ON public.cs_dinner_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION fn_emit_dinner_rsvp_event();

-- 4. Gleicher Fix für Availability
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
  -- KEIN Skip: Captain wird bei JEDEM Klick benachrichtigt

  BEGIN
    SELECT m.team_id, m.opponent
    INTO v_team_id, v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    IF v_team_id IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_player_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_team_id
      AND tp.claimed_by = NEW.user_id
    LIMIT 1;

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
    );

    RAISE NOTICE 'availability_changed event created for user % match %', NEW.user_id, NEW.match_id;
  EXCEPTION WHEN OTHERS THEN
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


-- 5. VERIFIZIERUNG: Prüfe ob die Funktionen korrekt sind
SELECT proname,
  CASE
    WHEN prosrc LIKE '%OLD.status = NEW.status%'
      THEN '❌ ALTE VERSION'
    ELSE '✅ OK - Keine Skip-Logik'
  END AS status
FROM pg_proc
WHERE proname IN ('fn_emit_dinner_rsvp_event', 'fn_emit_availability_changed_event');
