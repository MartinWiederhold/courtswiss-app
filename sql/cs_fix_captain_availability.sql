-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX: Captain kann Verfügbarkeit ändern auch bei Aufstellung   ║
-- ║  + Auto-Promotion Ersatzspieler → Starter                     ║
-- ║  + Push-Benachrichtigung an nachgerückten Spieler              ║
-- ║  NEUE DATEI – ändert KEINE bestehenden Notification-Trigger.   ║
-- ║  Sicher mehrfach ausführbar (idempotent).                      ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  1. Alten Trigger sofort entfernen
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;


-- ═══════════════════════════════════════════════════════════════════
--  2. Tabelle cs_lineup_events sicherstellen
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
--  3. auto_handle_absence RPC
--
--     WICHTIGE ÄNDERUNG gegenüber früheren Versionen:
--     → Der absagende Spieler wird IMMER verarbeitet, auch wenn
--       sein Slot gesperrt ist. (Er hat EXPLIZIT abgesagt.)
--     → Nur bei der RESERVE-Suche wird "locked" beachtet.
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
  v_lineup_id     uuid;
  v_team_id       uuid;
  v_status        text;
  v_absent_slot   record;
  v_reserve_slot  record;
  v_absent_name   text  := '?';
  v_promoted_name text  := '?';
  v_return        jsonb := '{"promoted":false,"reason":"unknown"}'::jsonb;
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

    -- 2. Starter-Slot des abwesenden Spielers finden
    --    ★ KEIN locked-Check: Der Spieler hat EXPLIZIT abgesagt!
    SELECT s.id, s.position, s.player_slot_id, s.user_id
      INTO v_absent_slot
      FROM public.cs_match_lineup_slots s
     WHERE s.match_id  = p_match_id
       AND s.user_id   = p_absent_user_id
       AND s.slot_type  = 'starter'
     LIMIT 1;

    IF v_absent_slot IS NULL THEN
      RETURN '{"promoted":false,"reason":"not_starter"}'::jsonb;
    END IF;

    -- Name des Abwesenden
    BEGIN
      SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
        INTO v_absent_name
        FROM public.cs_team_players tp
       WHERE tp.id = v_absent_slot.player_slot_id;
      v_absent_name := coalesce(v_absent_name, '?');
    EXCEPTION WHEN OTHERS THEN v_absent_name := '?'; END;

    -- 3. Nächsten verfügbaren Ersatzspieler suchen
    --    ★ Gesperrte Ersätze WERDEN übersprungen (locked check nur hier)
    SELECT s.id, s.position, s.player_slot_id, s.user_id
      INTO v_reserve_slot
      FROM public.cs_match_lineup_slots s
     WHERE s.match_id  = p_match_id
       AND s.slot_type = 'reserve'
       AND s.player_slot_id IS NOT NULL
       AND (s.locked IS NOT TRUE)
     ORDER BY s.position ASC
     LIMIT 1;

    IF v_reserve_slot IS NULL THEN
      -- Kein Ersatz → Captain/Team informieren
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
       WHERE tp.id = v_reserve_slot.player_slot_id;
      v_promoted_name := coalesce(v_promoted_name, '?');
    EXCEPTION WHEN OTHERS THEN v_promoted_name := '?'; END;

    -- 4. ★ Befördern: Ersatz → Starter
    UPDATE public.cs_match_lineup_slots
       SET slot_type = 'starter',
           position  = v_absent_slot.position
     WHERE id = v_reserve_slot.id;

    -- Abwesenden Spieler entfernen
    DELETE FROM public.cs_match_lineup_slots
     WHERE id = v_absent_slot.id;

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

    -- 6. Audit-Event (löst Push-Benachrichtigung aus über bestehende Trigger-Kette)
    BEGIN
      INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
      VALUES (p_match_id, v_team_id, 'auto_promotion',
        jsonb_build_object(
          'promoted_name', v_promoted_name,
          'absent_name',   v_absent_name,
          'to',            v_reserve_slot.user_id::text,
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
      'to',            v_reserve_slot.user_id,
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
    -- Nur feuern wenn Status auf 'no' wechselt
    IF NEW.status IS DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;
    -- Nicht doppelt feuern
    IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;
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
--  6. RLS für cs_match_availability (idempotent)
-- ═══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id uuid)
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
    SELECT EXISTS (
      SELECT 1 FROM public.cs_team_members
      WHERE team_id = p_team_id AND user_id = auth.uid()
    );
  $fn$;
  GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO anon;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'is_team_member: %', SQLERRM;
END $$;

ALTER TABLE public.cs_match_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_match_availability_select ON public.cs_match_availability;
CREATE POLICY cs_match_availability_select ON public.cs_match_availability
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.cs_matches m
            WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_insert ON public.cs_match_availability;
CREATE POLICY cs_match_availability_insert ON public.cs_match_availability
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m
                WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_update ON public.cs_match_availability;
CREATE POLICY cs_match_availability_update ON public.cs_match_availability
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.cs_matches m
                WHERE m.id = match_id AND public.is_team_member(m.team_id))
  );

DROP POLICY IF EXISTS cs_match_availability_delete ON public.cs_match_availability;
CREATE POLICY cs_match_availability_delete ON public.cs_match_availability
  FOR DELETE USING (user_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
--  7. Diagnose
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_count int;
BEGIN
  RAISE NOTICE '═══════════════════════════════════════';
  RAISE NOTICE '  DIAGNOSE: Captain Availability Fix';
  RAISE NOTICE '═══════════════════════════════════════';

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

  -- cs_lineup_events Tabelle
  SELECT count(*) INTO v_count FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'cs_lineup_events';
  IF v_count > 0 THEN RAISE NOTICE '✓ cs_lineup_events Tabelle';
  ELSE RAISE WARNING '✗ cs_lineup_events FEHLT!'; END IF;

  -- Push-Trigger-Kette (nur prüfen, nicht anfassen!)
  RAISE NOTICE '--- Push-Trigger Kette ---';

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_emit_availability_changed_event';
  IF v_count > 0 THEN RAISE NOTICE '✓ availability → cs_events';
  ELSE RAISE WARNING '✗ trg_emit_availability_changed_event FEHLT!'; END IF;

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

  -- RLS
  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_match_availability';
  RAISE NOTICE 'cs_match_availability: % policies (soll 4)', v_count;

  RAISE NOTICE '═══════════════════════════════════════';
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
