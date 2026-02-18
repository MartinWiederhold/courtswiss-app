-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FIX: Auto-Promotion Trigger – Standalone Patch                ║
-- ║  Fixes "Etwas ist schiefgelaufen" when clicking Abgesagt.      ║
-- ║  Safe to run multiple times (idempotent).                      ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  STEP 1: Drop the auto-promotion trigger so Abgesagt works again
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;

-- ═══════════════════════════════════════════════════════════════════
--  STEP 2: Ensure cs_lineup_events table exists
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cs_lineup_events (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id   uuid        NOT NULL,
  team_id    uuid        NOT NULL,
  event_type text        NOT NULL,
  payload    jsonb,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cs_lineup_events ENABLE ROW LEVEL SECURITY;

-- RLS: anyone in the team can read
DO $$
BEGIN
  -- is_team_member might not exist yet – wrap in exception
  BEGIN
    DROP POLICY IF EXISTS cs_lineup_events_select ON public.cs_lineup_events;
    CREATE POLICY cs_lineup_events_select ON public.cs_lineup_events
      FOR SELECT USING (public.is_team_member(team_id));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Could not create select policy for cs_lineup_events: %', SQLERRM;
  END;
END $$;

DROP POLICY IF EXISTS cs_lineup_events_insert ON public.cs_lineup_events;
CREATE POLICY cs_lineup_events_insert ON public.cs_lineup_events
  FOR INSERT WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════════
--  STEP 3: Create or replace auto_handle_absence RPC
--          (SECURITY DEFINER – bypasses RLS)
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.auto_handle_absence(uuid, uuid);
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
  v_absent_name   text;
  v_promoted_name text;
BEGIN
  -- 1. Check if lineup exists and is published
  SELECT l.id, l.team_id, l.status
  INTO v_lineup_id, v_team_id, v_status
  FROM public.cs_match_lineups l
  WHERE l.match_id = p_match_id
  LIMIT 1;

  IF v_lineup_id IS NULL THEN
    RETURN jsonb_build_object('promoted', false, 'reason', 'no_lineup');
  END IF;

  IF v_status IS DISTINCT FROM 'published' THEN
    RETURN jsonb_build_object('promoted', false, 'reason', 'not_published');
  END IF;

  -- 2. Find the absent player's STARTER slot
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

  -- Resolve absent player name (safe: returns '?' on failure)
  BEGIN
    SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
    INTO v_absent_name
    FROM public.cs_team_players tp
    WHERE tp.id = v_absent_slot.player_slot_id;
  EXCEPTION WHEN OTHERS THEN
    v_absent_name := '?';
  END;
  v_absent_name := coalesce(v_absent_name, '?');

  -- 3. Find the next available reserve (lowest position, not locked)
  SELECT s.id, s.position, s.player_slot_id, s.user_id
  INTO v_reserve_slot
  FROM public.cs_match_lineup_slots s
  WHERE s.match_id = p_match_id
    AND s.slot_type = 'reserve'
    AND s.player_slot_id IS NOT NULL
    AND (s.locked IS NOT TRUE)
  ORDER BY s.position ASC
  LIMIT 1;

  IF v_reserve_slot IS NULL THEN
    -- No reserve → log event
    BEGIN
      INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
      VALUES (
        p_match_id, v_team_id, 'no_reserve',
        jsonb_build_object(
          'absent_name', v_absent_name,
          'from',        p_absent_user_id::text,
          'match_id',    p_match_id::text,
          'team_id',     v_team_id::text
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_handle_absence: no_reserve event insert failed: %', SQLERRM;
    END;
    RETURN jsonb_build_object('promoted', false, 'reason', 'no_reserve', 'absent_name', v_absent_name);
  END IF;

  -- Resolve promoted player name (safe)
  BEGIN
    SELECT coalesce(tp.first_name || ' ' || tp.last_name, '?')
    INTO v_promoted_name
    FROM public.cs_team_players tp
    WHERE tp.id = v_reserve_slot.player_slot_id;
  EXCEPTION WHEN OTHERS THEN
    v_promoted_name := '?';
  END;
  v_promoted_name := coalesce(v_promoted_name, '?');

  -- 4. Promote: move reserve to the starter's position
  UPDATE public.cs_match_lineup_slots
  SET slot_type = 'starter',
      position  = v_absent_slot.position
  WHERE id = v_reserve_slot.id;

  -- Remove the absent player's slot
  DELETE FROM public.cs_match_lineup_slots
  WHERE id = v_absent_slot.id;

  -- 5. Renumber remaining reserves
  WITH numbered AS (
    SELECT s.id, ROW_NUMBER() OVER (ORDER BY s.position) AS new_pos
    FROM public.cs_match_lineup_slots s
    WHERE s.match_id = p_match_id AND s.slot_type = 'reserve'
  )
  UPDATE public.cs_match_lineup_slots ls
  SET position = numbered.new_pos
  FROM numbered
  WHERE ls.id = numbered.id;

  -- 6. Create audit event (wrapped in exception for safety)
  BEGIN
    INSERT INTO public.cs_lineup_events (match_id, team_id, event_type, payload)
    VALUES (
      p_match_id, v_team_id, 'auto_promotion',
      jsonb_build_object(
        'promoted_name', v_promoted_name,
        'absent_name',   v_absent_name,
        'to',            v_reserve_slot.user_id::text,
        'from',          p_absent_user_id::text,
        'match_id',      p_match_id::text,
        'team_id',       v_team_id::text
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_handle_absence: audit event insert failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'promoted', true,
    'promoted_name', v_promoted_name,
    'absent_name', v_absent_name,
    'to', v_reserve_slot.user_id,
    'from', p_absent_user_id
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.auto_handle_absence(uuid, uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  STEP 4: Create the trigger function
--          ENTIRE body wrapped in EXCEPTION – can NEVER block
--          the availability change, no matter what goes wrong.
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
  -- Top-level EXCEPTION: nothing inside can ever block the upsert
  BEGIN
    -- Only fire when status is 'no'
    IF NEW.status IS DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;

    -- Skip if status was already 'no' (no change)
    IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'no' THEN
      RETURN NEW;
    END IF;

    -- Check if there's a published lineup for this match
    IF EXISTS (
      SELECT 1 FROM public.cs_match_lineups
      WHERE match_id = NEW.match_id AND status = 'published'
    ) THEN
      v_result := public.auto_handle_absence(NEW.match_id, NEW.user_id);
      RAISE NOTICE 'auto_promote_on_absence result: %', v_result;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Log the error but NEVER block the availability change
    RAISE WARNING 'fn_auto_promote_on_absence SAFELY caught: % (SQLSTATE %)', SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
--  STEP 5: Re-create the trigger
-- ═══════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_auto_promote_on_absence ON public.cs_match_availability;
CREATE TRIGGER trg_auto_promote_on_absence
  AFTER INSERT OR UPDATE ON public.cs_match_availability
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_promote_on_absence();

-- ═══════════════════════════════════════════════════════════════════
--  STEP 6: Diagnostic – list all triggers on cs_match_availability
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  r record;
BEGIN
  RAISE NOTICE '--- Triggers on cs_match_availability ---';
  FOR r IN
    SELECT tgname, pg_get_triggerdef(oid) AS def
    FROM pg_trigger
    WHERE tgrelid = 'public.cs_match_availability'::regclass
      AND NOT tgisinternal
  LOOP
    RAISE NOTICE 'Trigger: % → %', r.tgname, r.def;
  END LOOP;
  RAISE NOTICE '--- Done ---';
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
