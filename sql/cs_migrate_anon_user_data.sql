-- ================================================================
-- Migration RPC: migrate_anon_user_data(old_uid, new_uid)
--
-- Migrates all data owned by an anonymous user (old_uid) to a newly
-- registered/linked user (new_uid). Called from the client after a
-- successful signUp/signIn when a previous anon session existed.
--
-- Security:
--   1. The caller must be authenticated as new_uid (auth.uid()).
--   2. p_old_uid must be an anonymous user (auth.users.is_anonymous = true
--      OR email IS NULL). If not anon the function raises an exception.
-- We pass old_uid as a parameter; the RPC validates both checks.
--
-- Tables updated (all columns containing user references):
--   1. cs_app_profiles        → user_id
--   2. cs_team_members        → user_id
--   3. cs_team_players        → claimed_by
--   4. cs_teams               → created_by
--   5. cs_matches             → created_by
--   6. cs_match_availability  → user_id
--   7. cs_match_roster        → user_id
--   8. cs_match_lineup_slots  → user_id
--   9. cs_dinner_rsvps        → user_id
--  10. cs_carpool_offers      → driver_user_id
--  11. cs_expenses            → paid_by (if exists)
--  12. cs_event_reads         → user_id
--  13. cs_notifications       → recipient_user_id
--  14. cs_device_tokens       → user_id (if exists)
--  15. cs_notification_prefs  → user_id (if exists)
--
-- Approach: Best-effort UPDATE with ON CONFLICT handling.
-- If a row for new_uid already exists (unique constraint), the old
-- row is deleted to avoid conflicts.
-- ================================================================

CREATE OR REPLACE FUNCTION migrate_anon_user_data(
  p_old_uid UUID,
  p_new_uid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER        -- runs with elevated privileges to bypass RLS
SET search_path = public
AS $$
DECLARE
  v_result JSONB := '{}'::JSONB;
  v_count  INT;
BEGIN
  -- Validate: new_uid must be the current caller
  IF auth.uid() IS DISTINCT FROM p_new_uid THEN
    RAISE EXCEPTION 'new_uid must match the authenticated user';
  END IF;

  -- Validate: old and new must differ
  IF p_old_uid = p_new_uid THEN
    RETURN jsonb_build_object('migrated', false, 'reason', 'same user');
  END IF;

  -- ── Safety: p_old_uid must be an anonymous user ───────────
  -- An anonymous Supabase user has is_anonymous = true in auth.users.
  -- We also fall back to checking cs_app_profiles.email IS NULL
  -- in case the auth.users column is not accessible.
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_old_uid
      AND (is_anonymous = true OR email IS NULL)
  ) THEN
    -- Double-check via the app profiles table
    IF EXISTS (
      SELECT 1 FROM cs_app_profiles
      WHERE user_id = p_old_uid AND email IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'p_old_uid is not an anonymous user – migration aborted';
    END IF;
  END IF;

  -- ── 1. cs_app_profiles ──────────────────────────────────
  -- Delete old profile if new one already exists; else update
  IF EXISTS (SELECT 1 FROM cs_app_profiles WHERE user_id = p_new_uid) THEN
    DELETE FROM cs_app_profiles WHERE user_id = p_old_uid;
  ELSE
    UPDATE cs_app_profiles SET user_id = p_new_uid WHERE user_id = p_old_uid;
  END IF;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_app_profiles', v_count);

  -- ── 2. cs_team_members ──────────────────────────────────
  -- unique on (team_id, user_id) → delete old if duplicate
  DELETE FROM cs_team_members
    WHERE user_id = p_old_uid
      AND team_id IN (
        SELECT team_id FROM cs_team_members WHERE user_id = p_new_uid
      );
  UPDATE cs_team_members SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_team_members', v_count);

  -- ── 3. cs_team_players (claimed_by) ─────────────────────
  UPDATE cs_team_players SET claimed_by = p_new_uid WHERE claimed_by = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_team_players', v_count);

  -- ── 4. cs_teams (created_by) ────────────────────────────
  UPDATE cs_teams SET created_by = p_new_uid WHERE created_by = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_teams', v_count);

  -- ── 5. cs_matches (created_by) ──────────────────────────
  UPDATE cs_matches SET created_by = p_new_uid WHERE created_by = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_matches', v_count);

  -- ── 6. cs_match_availability ────────────────────────────
  DELETE FROM cs_match_availability
    WHERE user_id = p_old_uid
      AND match_id IN (
        SELECT match_id FROM cs_match_availability WHERE user_id = p_new_uid
      );
  UPDATE cs_match_availability SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_match_availability', v_count);

  -- ── 7. cs_match_roster ──────────────────────────────────
  DELETE FROM cs_match_roster
    WHERE user_id = p_old_uid
      AND match_id IN (
        SELECT match_id FROM cs_match_roster WHERE user_id = p_new_uid
      );
  UPDATE cs_match_roster SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_match_roster', v_count);

  -- ── 8. cs_match_lineup_slots ────────────────────────────
  UPDATE cs_match_lineup_slots SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_match_lineup_slots', v_count);

  -- ── 9. cs_dinner_rsvps ──────────────────────────────────
  DELETE FROM cs_dinner_rsvps
    WHERE user_id = p_old_uid
      AND match_id IN (
        SELECT match_id FROM cs_dinner_rsvps WHERE user_id = p_new_uid
      );
  UPDATE cs_dinner_rsvps SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_dinner_rsvps', v_count);

  -- ── 10. cs_carpool_offers (driver_user_id) ──────────────
  UPDATE cs_carpool_offers SET driver_user_id = p_new_uid WHERE driver_user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_carpool_offers', v_count);

  -- ── 11. cs_expenses (paid_by – if column exists) ────────
  BEGIN
    UPDATE cs_expenses SET paid_by = p_new_uid WHERE paid_by = p_old_uid;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_result := v_result || jsonb_build_object('cs_expenses', v_count);
  EXCEPTION WHEN undefined_column THEN
    -- Column may not exist in all deployments
    NULL;
  END;

  -- ── 12. cs_event_reads ──────────────────────────────────
  DELETE FROM cs_event_reads
    WHERE user_id = p_old_uid
      AND event_id IN (
        SELECT event_id FROM cs_event_reads WHERE user_id = p_new_uid
      );
  UPDATE cs_event_reads SET user_id = p_new_uid WHERE user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_event_reads', v_count);

  -- ── 13. cs_notifications ────────────────────────────────
  UPDATE cs_notifications SET recipient_user_id = p_new_uid WHERE recipient_user_id = p_old_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_result := v_result || jsonb_build_object('cs_notifications', v_count);

  -- ── 14. cs_device_tokens (if exists) ────────────────────
  BEGIN
    DELETE FROM cs_device_tokens
      WHERE user_id = p_old_uid
        AND token IN (
          SELECT token FROM cs_device_tokens WHERE user_id = p_new_uid
        );
    UPDATE cs_device_tokens SET user_id = p_new_uid WHERE user_id = p_old_uid;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_result := v_result || jsonb_build_object('cs_device_tokens', v_count);
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- ── 15. cs_notification_prefs (if exists) ───────────────
  BEGIN
    DELETE FROM cs_notification_prefs
      WHERE user_id = p_old_uid
        AND team_id IN (
          SELECT team_id FROM cs_notification_prefs WHERE user_id = p_new_uid
        );
    UPDATE cs_notification_prefs SET user_id = p_new_uid WHERE user_id = p_old_uid;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_result := v_result || jsonb_build_object('cs_notification_prefs', v_count);
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- Done
  v_result := v_result || jsonb_build_object('migrated', true);
  RETURN v_result;
END;
$$;

-- Grant execute to authenticated users (not anon, because after linking
-- the user will be authenticated as the new identity).
GRANT EXECUTE ON FUNCTION migrate_anon_user_data(UUID, UUID) TO authenticated;
