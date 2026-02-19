-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX v4: Auto-Promotion – Robuster user_id-Lookup              ║
-- ║                                                                 ║
-- ║  PROBLEM: generate_lineup setzt nur player_slot_id, aber NICHT  ║
-- ║  user_id in cs_match_lineup_slots. auto_handle_absence suchte   ║
-- ║  bisher NUR per user_id → findet nichts → keine Beförderung.    ║
-- ║                                                                 ║
-- ║  FIX:                                                           ║
-- ║  1. Backfill: user_id in allen Slots nachträglich setzen        ║
-- ║  2. auto_handle_absence: Slot-Suche über JOIN mit               ║
-- ║     cs_team_players.claimed_by als Fallback                     ║
-- ║  3. Bei Promotion: user_id auf dem Slot ebenfalls setzen        ║
-- ║  4. cs_decline_promotion RPC hinzufügen                         ║
-- ║                                                                 ║
-- ║  NEUE DATEI – ändert keine bestehenden Trigger-Ketten.          ║
-- ║  Sicher mehrfach ausführbar (idempotent).                       ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  0. Backfill: user_id in bestehenden Slots setzen (wo NULL)
--     Quelle: cs_team_players.claimed_by
-- ═══════════════════════════════════════════════════════════════════
UPDATE public.cs_match_lineup_slots ls
   SET user_id = tp.claimed_by
  FROM public.cs_team_players tp
 WHERE ls.player_slot_id = tp.id
   AND ls.user_id IS NULL
   AND tp.claimed_by IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════
--  1. Alten Trigger entfernen (wird unten neu erstellt)
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;


-- ═══════════════════════════════════════════════════════════════════
--  2. cs_lineup_events Tabelle sicherstellen
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cs_lineup_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    uuid        NOT NULL,
  team_id     uuid        NOT NULL,
  event_type  text        NOT NULL,
  payload     jsonb,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cs_lineup_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  ALTER TABLE public.cs_lineup_events ADD COLUMN confirmed_at timestamptz;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS cs_lineup_events_select ON public.cs_lineup_events;
  CREATE POLICY cs_lineup_events_select ON public.cs_lineup_events
    FOR SELECT USING (true);
  DROP POLICY IF EXISTS cs_lineup_events_insert ON public.cs_lineup_events;
  CREATE POLICY cs_lineup_events_insert ON public.cs_lineup_events
    FOR INSERT WITH CHECK (true);
  DROP POLICY IF EXISTS cs_lineup_events_update ON public.cs_lineup_events;
  CREATE POLICY cs_lineup_events_update ON public.cs_lineup_events
    FOR UPDATE USING (true);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cs_lineup_events RLS: %', SQLERRM;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  3. auto_handle_absence RPC  (★ HAUPTFIX)
--
--     ÄNDERUNG:  Slot wird NICHT mehr nur per user_id gesucht,
--                sondern zusätzlich per cs_team_players.claimed_by.
--                So funktioniert die Promotion auch wenn user_id
--                in cs_match_lineup_slots NULL ist.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.auto_handle_absence(
  p_match_id       uuid,
  p_absent_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lineup_id       uuid;
  v_team_id         uuid;
  v_status          text;
  v_absent_slot_id  uuid;
  v_absent_pos      int;
  v_absent_psid     uuid;   -- player_slot_id
  v_reserve_slot_id uuid;
  v_reserve_pos     int;
  v_reserve_psid    uuid;   -- player_slot_id
  v_reserve_uid     uuid;   -- resolved user_id for the promoted player
  v_absent_name     text  := '?';
  v_promoted_name   text  := '?';
  v_return          jsonb := '{"promoted":false,"reason":"unknown"}'::jsonb;
BEGIN
  BEGIN  -- äusserer EXCEPTION-Block

    -- 1. Veröffentlichte Aufstellung?
    SELECT l.id, l.team_id, l.status
      INTO v_lineup_id, v_team_id, v_status
      FROM public.cs_match_lineups l
     WHERE l.match_id = p_match_id
     LIMIT 1;

    IF v_lineup_id IS NULL THEN
      RETURN '{"promoted":false,"reason":"no_lineup"}'::jsonb;
    END IF;
    IF v_status != 'published' THEN
      RETURN '{"promoted":false,"reason":"not_published"}'::jsonb;
    END IF;

    -- ──────────────────────────────────────────────────────────────
    -- 2. Starter-Slot des abwesenden Spielers finden
    --    ★ KEIN locked-Check (Spieler hat EXPLIZIT abgesagt)
    --    ★ Sucht SOWOHL über user_id ALS AUCH über
    --      cs_team_players.claimed_by (Fallback)
    -- ──────────────────────────────────────────────────────────────
    SELECT s.id, s.position, s.player_slot_id
      INTO v_absent_slot_id, v_absent_pos, v_absent_psid
      FROM public.cs_match_lineup_slots s
      LEFT JOIN public.cs_team_players tp ON tp.id = s.player_slot_id
     WHERE s.match_id  = p_match_id
       AND s.slot_type = 'starter'
       AND (
             s.user_id = p_absent_user_id          -- direkt
             OR tp.claimed_by = p_absent_user_id   -- Fallback via team_players
           )
     LIMIT 1;

    IF v_absent_slot_id IS NULL THEN
      RETURN '{"promoted":false,"reason":"not_starter"}'::jsonb;
    END IF;

    -- Name des Abwesenden
    BEGIN
      SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
        INTO v_absent_name
        FROM public.cs_team_players tp
       WHERE tp.id = v_absent_psid;
      v_absent_name := coalesce(v_absent_name, '?');
    EXCEPTION WHEN OTHERS THEN v_absent_name := '?'; END;

    -- ──────────────────────────────────────────────────────────────
    -- 3. Nächsten verfügbaren Ersatzspieler suchen
    --    ★ Gesperrte Ersätze werden übersprungen
    --    ★ user_id wird aus cs_team_players.claimed_by aufgelöst
    -- ──────────────────────────────────────────────────────────────
    SELECT s.id, s.position, s.player_slot_id,
           coalesce(s.user_id, tp.claimed_by) AS resolved_uid
      INTO v_reserve_slot_id, v_reserve_pos, v_reserve_psid, v_reserve_uid
      FROM public.cs_match_lineup_slots s
      LEFT JOIN public.cs_team_players tp ON tp.id = s.player_slot_id
     WHERE s.match_id  = p_match_id
       AND s.slot_type = 'reserve'
       AND s.player_slot_id IS NOT NULL
       AND (s.locked IS NOT TRUE)
     ORDER BY s.position ASC
     LIMIT 1;

    IF v_reserve_slot_id IS NULL THEN
      -- Kein Ersatz vorhanden
      BEGIN
        INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
        VALUES (p_match_id, v_team_id, 'no_reserve',
          jsonb_build_object(
            'absent_name', v_absent_name,
            'from',        p_absent_user_id::text,
            'match_id',    p_match_id::text,
            'team_id',     v_team_id::text));
      EXCEPTION WHEN OTHERS THEN NULL; END;
      RETURN jsonb_build_object('promoted', false, 'reason', 'no_reserve',
                                'absent_name', v_absent_name);
    END IF;

    -- Name des Nachrückers
    BEGIN
      SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
        INTO v_promoted_name
        FROM public.cs_team_players tp
       WHERE tp.id = v_reserve_psid;
      v_promoted_name := coalesce(v_promoted_name, '?');
    EXCEPTION WHEN OTHERS THEN v_promoted_name := '?'; END;

    -- ──────────────────────────────────────────────────────────────
    -- 4. ★ Befördern: Ersatz → Starter
    --    Gleichzeitig user_id setzen (falls vorher NULL)
    -- ──────────────────────────────────────────────────────────────
    UPDATE public.cs_match_lineup_slots
       SET slot_type = 'starter',
           position  = v_absent_pos,
           user_id   = coalesce(user_id, v_reserve_uid)
     WHERE id = v_reserve_slot_id;

    -- Abwesenden Spieler entfernen
    DELETE FROM public.cs_match_lineup_slots
     WHERE id = v_absent_slot_id;

    -- 5. Verbleibende Ersätze neu nummerieren
    WITH numbered AS (
      SELECT s.id,
             ROW_NUMBER() OVER (ORDER BY s.position) AS new_pos
        FROM public.cs_match_lineup_slots s
       WHERE s.match_id  = p_match_id
         AND s.slot_type = 'reserve'
    )
    UPDATE public.cs_match_lineup_slots ls
       SET position = numbered.new_pos
      FROM numbered
     WHERE ls.id = numbered.id;

    -- ──────────────────────────────────────────────────────────────
    -- 6. Audit-Event (löst Push-Benachrichtigung aus)
    -- ──────────────────────────────────────────────────────────────
    BEGIN
      INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
      VALUES (p_match_id, v_team_id, 'auto_promotion',
        jsonb_build_object(
          'promoted_name', v_promoted_name,
          'absent_name',   v_absent_name,
          'to',            v_reserve_uid::text,
          'from',          p_absent_user_id::text,
          'match_id',      p_match_id::text,
          'team_id',       v_team_id::text));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_handle_absence: audit event failed: %', SQLERRM;
    END;

    v_return := jsonb_build_object(
      'promoted', true,
      'promoted_name', v_promoted_name,
      'absent_name',   v_absent_name,
      'to',            v_reserve_uid,
      'from',          p_absent_user_id);

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_handle_absence FAILED: % [%]', SQLERRM, SQLSTATE;
    v_return := jsonb_build_object(
      'promoted', false, 'reason', 'rpc_exception', 'error', SQLERRM);
  END;

  RETURN v_return;
END;
$$;

GRANT EXECUTE ON FUNCTION public.auto_handle_absence(uuid, uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  4. Trigger-Funktion (bombensicher)
--     RETURN NEW wird IMMER erreicht → Verfügbarkeit IMMER gespeichert
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_auto_promote_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  BEGIN
    -- Nur feuern wenn Status 'no' ist
    IF NEW.status IS DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;
    -- ★ KEIN Guard mehr für "status war schon no"!
    -- auto_handle_absence ist idempotent (liefert "not_starter"
    -- wenn kein Starter-Slot vorhanden). Wichtig damit die Promotion
    -- auch beim WIEDERHOLTEN Absagen funktioniert (z.B. nach einem
    -- fehlgeschlagenen Versuch mit alter Codeversion).

    -- Veröffentlichte Aufstellung vorhanden?
    IF EXISTS (
      SELECT 1 FROM public.cs_match_lineups
      WHERE match_id = NEW.match_id AND status = 'published'
    ) THEN
      v_result := public.auto_handle_absence(NEW.match_id, NEW.user_id);
      RAISE NOTICE 'auto_promote result: %', v_result;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_auto_promote_on_absence FAILED (non-blocking): % [%]', SQLERRM, SQLSTATE;
  END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_promote_on_absence
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_promote_on_absence();


-- ═══════════════════════════════════════════════════════════════════
--  5. Bestätigungs-RPC
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cs_confirm_promotion(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cs_lineup_events
     SET confirmed_at = now()
   WHERE id = p_event_id
     AND event_type = 'auto_promotion'
     AND (payload->>'to')::uuid = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_confirm_promotion(uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  6. Absage-RPC (Spieler lehnt Nachrücken ab → nächster Ersatz)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cs_decline_promotion(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev    record;
  v_uid   uuid := auth.uid();
BEGIN
  -- Event laden und prüfen
  SELECT id, match_id, team_id, payload
    INTO v_ev
    FROM public.cs_lineup_events
   WHERE id = p_event_id
     AND event_type = 'auto_promotion'
     AND (payload->>'to')::uuid = v_uid
     AND confirmed_at IS NULL;

  IF v_ev IS NULL THEN
    RETURN; -- nicht berechtigt oder schon bestätigt
  END IF;

  -- Event als abgelehnt markieren
  UPDATE public.cs_lineup_events
     SET confirmed_at = now(),
         payload = payload || '{"declined":true}'::jsonb
   WHERE id = p_event_id;

  -- Spieler-Verfügbarkeit auf 'no' setzen → löst erneut den
  -- Auto-Promotion-Trigger aus für den nächsten Ersatz
  INSERT INTO public.cs_match_availability (match_id, user_id, status, updated_at)
  VALUES (v_ev.match_id, v_uid, 'no', now())
  ON CONFLICT (match_id, user_id)
  DO UPDATE SET status = 'no', updated_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_decline_promotion(uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  7. Diagnose
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_count int;
  v_backfilled int;
BEGIN
  RAISE NOTICE '═══════════════════════════════════════';
  RAISE NOTICE '  DIAGNOSE: Auto-Promote v4 Fix';
  RAISE NOTICE '═══════════════════════════════════════';

  -- Backfill-Ergebnis
  SELECT count(*) INTO v_backfilled
    FROM public.cs_match_lineup_slots
   WHERE user_id IS NULL
     AND player_slot_id IS NOT NULL;
  RAISE NOTICE 'Slots mit user_id=NULL (nach Backfill): %', v_backfilled;

  -- Auto-Promotion Trigger
  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_auto_promote_on_absence'
    AND tgrelid = 'public.cs_match_availability'::regclass;
  IF v_count > 0 THEN RAISE NOTICE '✓ trg_auto_promote_on_absence';
  ELSE RAISE WARNING '✗ trg_auto_promote_on_absence FEHLT!'; END IF;

  -- auto_handle_absence RPC
  SELECT count(*) INTO v_count FROM pg_proc WHERE proname = 'auto_handle_absence';
  IF v_count > 0 THEN RAISE NOTICE '✓ auto_handle_absence RPC';
  ELSE RAISE WARNING '✗ auto_handle_absence FEHLT!'; END IF;

  -- cs_confirm_promotion RPC
  SELECT count(*) INTO v_count FROM pg_proc WHERE proname = 'cs_confirm_promotion';
  IF v_count > 0 THEN RAISE NOTICE '✓ cs_confirm_promotion RPC';
  ELSE RAISE WARNING '✗ cs_confirm_promotion FEHLT!'; END IF;

  -- cs_decline_promotion RPC
  SELECT count(*) INTO v_count FROM pg_proc WHERE proname = 'cs_decline_promotion';
  IF v_count > 0 THEN RAISE NOTICE '✓ cs_decline_promotion RPC';
  ELSE RAISE WARNING '✗ cs_decline_promotion FEHLT!'; END IF;

  -- cs_lineup_events Tabelle
  SELECT count(*) INTO v_count FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'cs_lineup_events';
  IF v_count > 0 THEN RAISE NOTICE '✓ cs_lineup_events Tabelle';
  ELSE RAISE WARNING '✗ cs_lineup_events FEHLT!'; END IF;

  -- Push-Trigger-Kette (nur prüfen, nicht anfassen!)
  RAISE NOTICE '--- Push-Trigger Kette ---';

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_emit_lineup_event_to_cs_events';
  IF v_count > 0 THEN RAISE NOTICE '✓ lineup_events → cs_events (Push an Spieler)';
  ELSE RAISE WARNING '✗ trg_emit_lineup_event_to_cs_events FEHLT!'; END IF;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_cs_event_fanout';
  IF v_count > 0 THEN RAISE NOTICE '✓ cs_events → deliveries';
  ELSE RAISE WARNING '✗ trg_cs_event_fanout FEHLT!'; END IF;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_bridge_delivery_to_notification';
  IF v_count > 0 THEN RAISE NOTICE '✓ deliveries → notifications + push';
  ELSE RAISE WARNING '✗ trg_bridge_delivery_to_notification FEHLT!'; END IF;

  RAISE NOTICE '═══════════════════════════════════════';
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
