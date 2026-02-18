-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  CourtSwiss – Substitute Request System                       ║
-- ║  Idempotent SQL Patch for Supabase SQL Editor                 ║
-- ║                                                               ║
-- ║  Flow:                                                        ║
-- ║  1. Starter declines → captain/system calls create_sub_request║
-- ║  2. Best available team member gets a pending request          ║
-- ║  3. Substitute accepts → lineup slot is updated               ║
-- ║  4. Substitute declines → next candidate gets a request       ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════
--  1. TABLE
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cs_sub_requests (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at         timestamptz NOT NULL    DEFAULT now(),
  match_id           uuid        NOT NULL    REFERENCES public.cs_matches(id) ON DELETE CASCADE,
  team_id            uuid        NOT NULL    REFERENCES public.cs_teams(id)   ON DELETE CASCADE,
  original_user_id   uuid        NOT NULL    REFERENCES auth.users(id)        ON DELETE CASCADE,
  substitute_user_id uuid        NOT NULL    REFERENCES auth.users(id)        ON DELETE CASCADE,
  status             text        NOT NULL    DEFAULT 'pending'
                     CHECK (status IN ('pending','accepted','declined','expired')),
  responded_at       timestamptz
);

-- ═══════════════════════════════════════════════════════════════════
--  2. INDEXES
-- ═══════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_cs_sub_requests_match
  ON public.cs_sub_requests (match_id, status);

CREATE INDEX IF NOT EXISTS idx_cs_sub_requests_substitute
  ON public.cs_sub_requests (substitute_user_id, status);

CREATE INDEX IF NOT EXISTS idx_cs_sub_requests_original
  ON public.cs_sub_requests (original_user_id, match_id);

-- ═══════════════════════════════════════════════════════════════════
--  3. ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.cs_sub_requests ENABLE ROW LEVEL SECURITY;

-- Team members can see requests for their team
DROP POLICY IF EXISTS cs_sub_requests_select ON public.cs_sub_requests;
CREATE POLICY cs_sub_requests_select ON public.cs_sub_requests
  FOR SELECT USING (
    public.is_team_member(team_id)
  );

-- Only admin/captain can create requests
DROP POLICY IF EXISTS cs_sub_requests_insert ON public.cs_sub_requests;
CREATE POLICY cs_sub_requests_insert ON public.cs_sub_requests
  FOR INSERT WITH CHECK (
    public.is_team_admin(team_id) OR public.is_team_creator(team_id)
  );

-- Team members can update (for accept/decline via RPC SECURITY DEFINER)
DROP POLICY IF EXISTS cs_sub_requests_update ON public.cs_sub_requests;
CREATE POLICY cs_sub_requests_update ON public.cs_sub_requests
  FOR UPDATE USING (
    substitute_user_id = auth.uid()
    OR public.is_team_admin(team_id)
    OR public.is_team_creator(team_id)
  );

-- ═══════════════════════════════════════════════════════════════════
--  4. RPC: cs_create_sub_request
--     Finds the best available substitute and creates a pending request.
-- ═══════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.cs_create_sub_request(uuid, uuid);
CREATE OR REPLACE FUNCTION public.cs_create_sub_request(
  p_match_id       uuid,
  p_original_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id        uuid;
  v_sub_user_id    uuid;
  v_sub_name       text;
  v_request_id     uuid;
BEGIN
  -- 1. Determine team_id from the match
  SELECT m.team_id INTO v_team_id
  FROM public.cs_matches m
  WHERE m.id = p_match_id;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Match not found: %', p_match_id;
  END IF;

  -- 2. Expire any existing pending request for this match + original user
  UPDATE public.cs_sub_requests
  SET status = 'expired', responded_at = now()
  WHERE match_id      = p_match_id
    AND original_user_id = p_original_user_id
    AND status        = 'pending';

  -- 3. Find best substitute candidate:
  --    - Must be a team member
  --    - Must NOT be the original user
  --    - Must NOT already be in the lineup as a starter
  --    - Must NOT have a pending/accepted sub request for this match
  --    - Must have availability = 'yes' (or no response, depending on policy)
  --    - Order by ranking (best first via cs_team_players)
  SELECT tp.claimed_by INTO v_sub_user_id
  FROM public.cs_team_players tp
  JOIN public.cs_team_members tm
    ON tm.team_id = v_team_id AND tm.user_id = tp.claimed_by
  WHERE tp.team_id = v_team_id
    AND tp.claimed_by IS NOT NULL
    AND tp.claimed_by <> p_original_user_id
    -- Not already a starter in this match
    AND NOT EXISTS (
      SELECT 1 FROM public.cs_match_lineup_slots ls
      WHERE ls.match_id = p_match_id
        AND ls.user_id  = tp.claimed_by
        AND ls.slot_type = 'starter'
    )
    -- Not already asked (pending) or accepted for this match
    AND NOT EXISTS (
      SELECT 1 FROM public.cs_sub_requests sr
      WHERE sr.match_id           = p_match_id
        AND sr.substitute_user_id = tp.claimed_by
        AND sr.status IN ('pending', 'accepted')
    )
    -- Has availability 'yes' or has not responded yet
    AND (
      EXISTS (
        SELECT 1 FROM public.cs_match_availability ma
        WHERE ma.match_id = p_match_id
          AND ma.user_id  = tp.claimed_by
          AND ma.status   = 'yes'
      )
      OR NOT EXISTS (
        SELECT 1 FROM public.cs_match_availability ma
        WHERE ma.match_id = p_match_id
          AND ma.user_id  = tp.claimed_by
      )
    )
  ORDER BY tp.ranking ASC NULLS LAST
  LIMIT 1;

  IF v_sub_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'no_candidate',
      'message', 'Kein verfügbarer Ersatzspieler gefunden'
    );
  END IF;

  -- 4. Get substitute name for response
  SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_sub_name
  FROM public.cs_team_players tp
  WHERE tp.team_id = v_team_id AND tp.claimed_by = v_sub_user_id
  LIMIT 1;

  -- 5. Insert the pending request
  INSERT INTO public.cs_sub_requests
    (match_id, team_id, original_user_id, substitute_user_id, status)
  VALUES
    (p_match_id, v_team_id, p_original_user_id, v_sub_user_id, 'pending')
  RETURNING id INTO v_request_id;

  -- 6. Create a targeted cs_events entry for the substitute
  INSERT INTO public.cs_events
    (team_id, match_id, event_type, title, body, payload, recipient_user_id, created_by)
  VALUES (
    v_team_id,
    p_match_id,
    'sub_request',
    'Ersatzanfrage',
    'Du wurdest als Ersatz angefragt',
    jsonb_build_object(
      'team_id', v_team_id,
      'match_id', p_match_id,
      'request_id', v_request_id,
      'original_user_id', p_original_user_id
    ),
    v_sub_user_id,
    auth.uid()
  );

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'substitute_user_id', v_sub_user_id,
    'substitute_name', coalesce(v_sub_name, '?')
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_create_sub_request(uuid, uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  5. RPC: cs_respond_sub_request
--     Substitute accepts or declines the request.
-- ═══════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.cs_respond_sub_request(uuid, text);
CREATE OR REPLACE FUNCTION public.cs_respond_sub_request(
  p_request_id uuid,
  p_response   text   -- 'accepted' or 'declined'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req              record;
  v_slot_id          uuid;
  v_sub_name         text;
  v_original_name    text;
BEGIN
  IF p_response NOT IN ('accepted', 'declined') THEN
    RAISE EXCEPTION 'Invalid response: %. Must be accepted or declined.', p_response;
  END IF;

  -- 1. Load and lock the request
  SELECT * INTO v_req
  FROM public.cs_sub_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Sub request not found: %', p_request_id;
  END IF;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'not_pending',
      'message', 'Anfrage ist nicht mehr offen (Status: ' || v_req.status || ')'
    );
  END IF;

  -- Verify the caller is the substitute
  IF v_req.substitute_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the substitute can respond to this request';
  END IF;

  -- 2. Update the request status
  UPDATE public.cs_sub_requests
  SET status       = p_response,
      responded_at = now()
  WHERE id = p_request_id;

  -- 3. If accepted: update the lineup slot
  IF p_response = 'accepted' THEN
    -- Find the slot of the original user (starter)
    SELECT ls.id INTO v_slot_id
    FROM public.cs_match_lineup_slots ls
    WHERE ls.match_id = v_req.match_id
      AND ls.user_id  = v_req.original_user_id
    LIMIT 1;

    IF v_slot_id IS NOT NULL THEN
      -- Swap the user in the lineup slot
      UPDATE public.cs_match_lineup_slots
      SET user_id = v_req.substitute_user_id
      WHERE id = v_slot_id;
    END IF;

    -- Get names for the event
    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_sub_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_req.team_id AND tp.claimed_by = v_req.substitute_user_id
    LIMIT 1;

    SELECT CONCAT_WS(' ', tp.first_name, tp.last_name) INTO v_original_name
    FROM public.cs_team_players tp
    WHERE tp.team_id = v_req.team_id AND tp.claimed_by = v_req.original_user_id
    LIMIT 1;

    -- Broadcast event: substitute accepted
    INSERT INTO public.cs_events
      (team_id, match_id, event_type, title, body, payload, created_by)
    VALUES (
      v_req.team_id,
      v_req.match_id,
      'sub_accepted',
      'Ersatz bestätigt',
      coalesce(v_sub_name, '?') || ' ersetzt ' || coalesce(v_original_name, '?'),
      jsonb_build_object(
        'team_id', v_req.team_id,
        'match_id', v_req.match_id,
        'request_id', p_request_id,
        'substitute_user_id', v_req.substitute_user_id,
        'original_user_id', v_req.original_user_id,
        'substitute_name', coalesce(v_sub_name, '?'),
        'original_name', coalesce(v_original_name, '?')
      ),
      auth.uid()
    );

    RETURN jsonb_build_object(
      'success', true,
      'action', 'accepted',
      'slot_updated', v_slot_id IS NOT NULL
    );

  ELSE
    -- Declined: create event for captain
    RETURN jsonb_build_object(
      'success', true,
      'action', 'declined',
      'message', 'Ersatzanfrage wurde abgelehnt. Captain kann erneut anfragen.'
    );
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cs_respond_sub_request(uuid, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  6. RPC: cs_list_my_sub_requests
--     Lists pending sub requests for the current user.
-- ═══════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.cs_list_my_sub_requests();
CREATE OR REPLACE FUNCTION public.cs_list_my_sub_requests()
RETURNS SETOF public.cs_sub_requests
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT *
  FROM public.cs_sub_requests
  WHERE substitute_user_id = auth.uid()
    AND status = 'pending'
  ORDER BY created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.cs_list_my_sub_requests() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
--  7. PostgREST reload
-- ═══════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
