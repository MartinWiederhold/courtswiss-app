-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX: Availability RLS + Auto-Promotion (resilient)            ║
-- ║  NEUE DATEI – ändert keine bestehenden Trigger.                ║
-- ║  Sicher mehrfach ausführbar (idempotent).                      ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ═══════════════════════════════════════════════════════════════════
--  1. Helper-Funktion sicherstellen
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.is_team_member(p_team_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cs_team_members
    WHERE team_id = p_team_id AND user_id = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_team_member(uuid) TO anon;


-- ═══════════════════════════════════════════════════════════════════
--  2. RLS für cs_match_availability
-- ═══════════════════════════════════════════════════════════════════
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
--  3. cs_lineup_events Tabelle (Audit-Trail für Auto-Promotion)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cs_lineup_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    uuid        NOT NULL,
  team_id     uuid        NOT NULL,
  event_type  text        NOT NULL,    -- 'auto_promotion' | 'no_reserve'
  payload     jsonb,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.cs_lineup_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_lineup_events_select ON public.cs_lineup_events;
CREATE POLICY cs_lineup_events_select ON public.cs_lineup_events
  FOR SELECT USING (public.is_team_member(team_id));

DROP POLICY IF EXISTS cs_lineup_events_insert ON public.cs_lineup_events;
CREATE POLICY cs_lineup_events_insert ON public.cs_lineup_events
  FOR INSERT WITH CHECK (true);

-- Spalte für Bestätigung durch den nachgerückten Spieler
DO $$ BEGIN
  ALTER TABLE public.cs_lineup_events ADD COLUMN confirmed_at timestamptz;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. auto_handle_absence RPC (voll resilient)
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.auto_handle_absence(uuid, uuid);

CREATE FUNCTION public.auto_handle_absence(
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
  v_absent_name   text;
  v_promoted_name text;
  v_return        jsonb;
BEGIN
  BEGIN  -- äusserer EXCEPTION-Block

    -- 1. Gibt es eine veröffentlichte Aufstellung?
    SELECT l.id, l.team_id, l.status
    INTO v_lineup_id, v_team_id, v_status
    FROM public.cs_match_lineups l
    WHERE l.match_id = p_match_id LIMIT 1;

    IF v_lineup_id IS NULL THEN
      RETURN jsonb_build_object('promoted', false, 'reason', 'no_lineup');
    END IF;
    IF v_status != 'published' THEN
      RETURN jsonb_build_object('promoted', false, 'reason', 'not_published');
    END IF;

    -- 2. Starter-Slot des abwesenden Spielers finden
    SELECT s.id, s.position, s.player_slot_id, s.user_id
    INTO v_absent_slot
    FROM public.cs_match_lineup_slots s
    WHERE s.match_id = p_match_id
      AND s.user_id = p_absent_user_id
      AND s.slot_type = 'starter'
      AND (s.locked IS NOT TRUE)
    LIMIT 1;

    IF v_absent_slot IS NULL THEN
      RETURN jsonb_build_object('promoted', false, 'reason', 'not_starter');
    END IF;

    -- Name des abwesenden Spielers
    BEGIN
      SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
      INTO v_absent_name
      FROM public.cs_team_players tp WHERE tp.id = v_absent_slot.player_slot_id;
      v_absent_name := coalesce(v_absent_name, '?');
    EXCEPTION WHEN OTHERS THEN v_absent_name := '?'; END;

    -- 3. Nächsten verfügbaren Ersatzspieler finden
    SELECT s.id, s.position, s.player_slot_id, s.user_id
    INTO v_reserve_slot
    FROM public.cs_match_lineup_slots s
    WHERE s.match_id = p_match_id
      AND s.slot_type = 'reserve'
      AND s.player_slot_id IS NOT NULL
      AND (s.locked IS NOT TRUE)
    ORDER BY s.position ASC LIMIT 1;

    IF v_reserve_slot IS NULL THEN
      -- Kein Ersatz verfügbar
      BEGIN
        INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
        VALUES (p_match_id, v_team_id, 'no_reserve',
          jsonb_build_object(
            'absent_name', v_absent_name,
            'from', p_absent_user_id::text,
            'match_id', p_match_id::text,
            'team_id', v_team_id::text
          ));
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'auto_handle_absence: no_reserve event insert failed: %', SQLERRM;
      END;
      RETURN jsonb_build_object('promoted', false, 'reason', 'no_reserve', 'absent_name', v_absent_name);
    END IF;

    -- Name des nachgerückten Spielers
    BEGIN
      SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
      INTO v_promoted_name
      FROM public.cs_team_players tp WHERE tp.id = v_reserve_slot.player_slot_id;
      v_promoted_name := coalesce(v_promoted_name, '?');
    EXCEPTION WHEN OTHERS THEN v_promoted_name := '?'; END;

    -- 4. Befördern: Ersatz an Starter-Position verschieben
    UPDATE public.cs_match_lineup_slots
    SET slot_type = 'starter', position = v_absent_slot.position
    WHERE id = v_reserve_slot.id;

    -- Abwesenden Spieler entfernen
    DELETE FROM public.cs_match_lineup_slots WHERE id = v_absent_slot.id;

    -- 5. Verbleibende Ersätze neu nummerieren
    WITH numbered AS (
      SELECT s.id, ROW_NUMBER() OVER (ORDER BY s.position) AS new_pos
      FROM public.cs_match_lineup_slots s
      WHERE s.match_id = p_match_id AND s.slot_type = 'reserve'
    )
    UPDATE public.cs_match_lineup_slots ls
    SET position = numbered.new_pos FROM numbered WHERE ls.id = numbered.id;

    -- 6. Audit-Event erstellen (löst Push-Benachrichtigung aus)
    BEGIN
      INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
      VALUES (p_match_id, v_team_id, 'auto_promotion',
        jsonb_build_object(
          'promoted_name', v_promoted_name,
          'absent_name',   v_absent_name,
          'to',            v_reserve_slot.user_id::text,
          'from',          p_absent_user_id::text,
          'match_id',      p_match_id::text,
          'team_id',       v_team_id::text
        ));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_handle_absence: auto_promotion event insert failed: %', SQLERRM;
    END;

    v_return := jsonb_build_object(
      'promoted', true,
      'promoted_name', v_promoted_name,
      'absent_name', v_absent_name,
      'to', v_reserve_slot.user_id,
      'from', p_absent_user_id
    );

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_handle_absence RPC failed: % (%)', SQLERRM, SQLSTATE;
    v_return := jsonb_build_object('promoted', false, 'reason', 'rpc_exception', 'error', SQLERRM);
  END;

  RETURN v_return;
END;
$$;
GRANT EXECUTE ON FUNCTION public.auto_handle_absence(uuid, uuid) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════
--  5. Trigger: Bei Absage automatisch Ersatz nachrücken
--     KOMPLETT in EXCEPTION gewrappt → blockiert NIEMALS die
--     Verfügbarkeits-Änderung. Selbst bei totalem Crash wird
--     nur ein Warning geloggt und NEW zurückgegeben.
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
  BEGIN  -- äusserer EXCEPTION-Block

    -- Nur feuern wenn Status auf 'no' wechselt
    IF NEW.status IS DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;

    -- Kein Doppel-Feuern wenn Status bereits 'no' war
    IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;

    -- Gibt es eine veröffentlichte Aufstellung?
    IF EXISTS (
      SELECT 1 FROM public.cs_match_lineups
      WHERE match_id = NEW.match_id AND status = 'published'
    ) THEN
      v_result := public.auto_handle_absence(NEW.match_id, NEW.user_id);
      RAISE NOTICE 'auto_promote_on_absence: %', v_result;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- NIEMALS die Verfügbarkeits-Änderung blockieren!
    RAISE WARNING 'fn_auto_promote_on_absence failed (non-blocking): % (%)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Trigger erstellen (idempotent)
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;
CREATE TRIGGER trg_auto_promote_on_absence
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_promote_on_absence();


-- ═══════════════════════════════════════════════════════════════════
--  6. RPC: Nachrücken bestätigen
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
--  7. Diagnose
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE v_count int;
BEGIN
  RAISE NOTICE '═══ Prüfung ═══';

  SELECT count(*) INTO v_count FROM pg_policies WHERE tablename = 'cs_match_availability';
  RAISE NOTICE 'cs_match_availability: % policies (soll 4)', v_count;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_auto_promote_on_absence'
    AND tgrelid = 'public.cs_match_availability'::regclass;
  IF v_count > 0 THEN RAISE NOTICE '✓ trg_auto_promote_on_absence existiert';
  ELSE RAISE WARNING '✗ trg_auto_promote_on_absence FEHLT'; END IF;

  -- Prüfen dass die 12 Push-Trigger noch da sind
  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_emit_availability_changed_event';
  IF v_count > 0 THEN RAISE NOTICE '✓ trg_emit_availability_changed_event noch da';
  ELSE RAISE WARNING '✗ trg_emit_availability_changed_event FEHLT!'; END IF;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_cs_event_fanout';
  IF v_count > 0 THEN RAISE NOTICE '✓ trg_cs_event_fanout noch da';
  ELSE RAISE WARNING '✗ trg_cs_event_fanout FEHLT!'; END IF;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_bridge_delivery_to_notification';
  IF v_count > 0 THEN RAISE NOTICE '✓ trg_bridge_delivery_to_notification noch da';
  ELSE RAISE WARNING '✗ trg_bridge_delivery_to_notification FEHLT!'; END IF;

  RAISE NOTICE '═══ Fertig ═══';
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
