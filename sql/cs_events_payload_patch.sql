-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Event-Qualität + Deep-Link Robustheit            ║
-- ║  (Payload-Standard)                                            ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                  ║
-- ║                                                                ║
-- ║  Changes:                                                      ║
-- ║  1. cs_event_payload_merge() helper function                   ║
-- ║  2. Backfill existing cs_events payloads with team_id/match_id ║
-- ║  3. CHECK constraint: payload must be a JSON object            ║
-- ║  4. Updated trigger: fn_emit_lineup_published_event            ║
-- ║     → payload includes {team_id, match_id, lineup_id}          ║
-- ║  5. Updated trigger: fn_emit_lineup_event_to_cs_events         ║
-- ║     → payload includes {team_id, match_id, in_name, out_name,  ║
-- ║       in_member_id, out_member_id, actor}                      ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. HELPER FUNCTION: cs_event_payload_merge
--     Merges two JSONB objects (base || override).
--     Returns base unchanged when override is null/empty.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cs_event_payload_merge(
  base  jsonb,
  merge jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(base, '{}'::jsonb) || coalesce(merge, '{}'::jsonb);
$$;

COMMENT ON FUNCTION public.cs_event_payload_merge(jsonb, jsonb) IS
  'Shallow-merge two JSONB objects. Used to enrich event payloads with standard keys.';

GRANT EXECUTE ON FUNCTION public.cs_event_payload_merge(jsonb, jsonb) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  2. BACKFILL existing cs_events payloads
--     Adds team_id and match_id into payload where missing.
-- ═══════════════════════════════════════════════════════════════════

UPDATE public.cs_events
SET payload = public.cs_event_payload_merge(
  payload,
  jsonb_build_object('team_id', team_id)
  || CASE WHEN match_id IS NOT NULL
       THEN jsonb_build_object('match_id', match_id)
       ELSE '{}'::jsonb
     END
)
WHERE NOT (
  payload ? 'team_id'
  AND (match_id IS NULL OR payload ? 'match_id')
);

-- ═══════════════════════════════════════════════════════════════════
--  3. CHECK CONSTRAINT – payload must be a JSON object (not array/scalar)
--     Using DO block for idempotence (only add if not already present).
-- ═══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'chk_cs_events_payload_is_object'
  ) THEN
    ALTER TABLE public.cs_events
      ADD CONSTRAINT chk_cs_events_payload_is_object
      CHECK (jsonb_typeof(payload) = 'object');
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
--  4. UPDATED TRIGGER: fn_emit_lineup_published_event
--     Now includes {team_id, match_id, lineup_id} in payload.
-- ═══════════════════════════════════════════════════════════════════

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
    SELECT m.opponent INTO v_opponent
    FROM public.cs_matches m
    WHERE m.id = NEW.match_id;

    -- Build standardised payload
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

-- ═══════════════════════════════════════════════════════════════════
--  5. UPDATED TRIGGER: fn_emit_lineup_event_to_cs_events
--     Enriches payload with {team_id, match_id} and extracts
--     in_name/out_name/in_member_id/out_member_id/actor from
--     the cs_lineup_events payload when available.
-- ═══════════════════════════════════════════════════════════════════

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
  -- (in_name = promoted player, out_name = absent player, actor = who triggered)
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
--  6. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
