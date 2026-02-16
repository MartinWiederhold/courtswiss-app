-- ═══════════════════════════════════════════════════════════════
-- Account Deletion RPC – cs_delete_account()
--
-- FACTORY RESET: permanently deletes the authenticated user and
-- ALL associated data.  Teams created by the user are deleted
-- entirely (including other members' data in those teams).
--
-- Runs as SECURITY DEFINER so it can bypass RLS and access
-- auth.users directly.
--
-- Call from Flutter:
--   await Supabase.instance.client.rpc('cs_delete_account');
--
-- Robustness:
-- • User-specific rows use the _cs_da_delete helper which guards
--   every table/column access via information_schema.
-- • Team-scoped rows use direct SQL wrapped in BEGIN/EXCEPTION
--   blocks so missing tables never abort the transaction.
--
-- Idempotent – safe to run multiple times.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- Helper: safely DELETE rows where <col> = <uid>.
-- No-op if the table or column doesn't exist.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._cs_da_delete(
  p_table text,
  p_col   text,
  p_uid   uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = p_table
       AND column_name  = p_col
  ) THEN
    EXECUTE format('DELETE FROM public.%I WHERE %I = $1', p_table, p_col)
      USING p_uid;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- Helper: safely SET <col> = NULL where <col> = <uid>.
-- No-op if the table or column doesn't exist.
-- Retained for potential future use; NOT called by the current
-- factory-reset flow.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._cs_da_nullify(
  p_table text,
  p_col   text,
  p_uid   uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = p_table
       AND column_name  = p_col
  ) THEN
    EXECUTE format('UPDATE public.%I SET %I = NULL WHERE %I = $1',
                   p_table, p_col, p_col)
      USING p_uid;
  END IF;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Main RPC
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cs_delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RAISE LOG 'cs_delete_account: starting for uid=%', v_uid;

  -- ══════════════════════════════════════════════════════════════
  -- PHASE 1: USER-SPECIFIC ROWS
  --
  -- Delete rows where the user is directly referenced, across ALL
  -- teams (including teams owned by others).
  -- Order: RESTRICT FK first, then leaves → parents.
  -- Helpers guard against missing tables / columns.
  -- ══════════════════════════════════════════════════════════════

  -- 1a. Expenses  (paid_by_user_id → auth.users ON DELETE RESTRICT)
  PERFORM _cs_da_delete('cs_expense_shares', 'user_id', v_uid);
  PERFORM _cs_da_delete('cs_expenses',       'paid_by_user_id', v_uid);

  -- 1b. Carpools
  PERFORM _cs_da_delete('cs_carpool_passengers', 'passenger_user_id', v_uid);
  PERFORM _cs_da_delete('cs_carpool_passengers', 'user_id', v_uid);
  PERFORM _cs_da_delete('cs_carpool_offers',     'driver_user_id', v_uid);

  -- 1c. Lineups & roster
  PERFORM _cs_da_delete('cs_match_lineup_slots', 'user_id', v_uid);
  PERFORM _cs_da_delete('cs_match_lineups',      'created_by', v_uid);
  PERFORM _cs_da_delete('cs_lineup_events',      'created_by', v_uid);
  PERFORM _cs_da_delete('cs_match_roster',       'user_id', v_uid);

  -- 1d. Availability, dinner, sub-requests
  PERFORM _cs_da_delete('cs_match_availability', 'user_id', v_uid);
  PERFORM _cs_da_delete('cs_dinner_rsvps',       'user_id', v_uid);
  PERFORM _cs_da_delete('cs_sub_requests',       'original_user_id', v_uid);
  PERFORM _cs_da_delete('cs_sub_requests',       'substitute_user_id', v_uid);

  -- 1e. Events & notifications
  PERFORM _cs_da_delete('cs_event_reads',        'user_id', v_uid);
  PERFORM _cs_da_delete('cs_event_deliveries',   'user_id', v_uid);
  PERFORM _cs_da_delete('cs_events',             'recipient_user_id', v_uid);
  PERFORM _cs_da_delete('cs_events',             'created_by', v_uid);
  PERFORM _cs_da_delete('cs_notifications',      'recipient_user_id', v_uid);
  PERFORM _cs_da_delete('cs_notification_prefs', 'user_id', v_uid);
  PERFORM _cs_da_delete('cs_device_tokens',      'user_id', v_uid);

  -- 1f. Team-player links & membership
  PERFORM _cs_da_delete('cs_team_players',  'user_id', v_uid);
  PERFORM _cs_da_delete('cs_team_players',  'claimed_by', v_uid);
  PERFORM _cs_da_delete('cs_team_members',  'user_id', v_uid);

  -- 1g. App profile
  PERFORM _cs_da_delete('cs_app_profiles',  'user_id', v_uid);

  -- ══════════════════════════════════════════════════════════════
  -- PHASE 2: TEAM-OWNED DATA  (teams WHERE created_by = v_uid)
  --
  -- Factory-reset: delete the ENTIRE team and all its data
  -- (matches, lineups, expenses of all members, etc.).
  -- Children are deleted bottom-up so RESTRICT / NO ACTION FKs
  -- never block the parent deletion.
  -- Each block is wrapped in BEGIN/EXCEPTION so a missing table
  -- does not abort the transaction.
  -- ══════════════════════════════════════════════════════════════

  -- 2a. Expense shares → expenses  (deepest leaf first)
  BEGIN
    DELETE FROM cs_expense_shares WHERE expense_id IN (
      SELECT id FROM cs_expenses WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_expenses WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2b. Event reads / deliveries → events
  BEGIN
    DELETE FROM cs_event_reads WHERE event_id IN (
      SELECT id FROM cs_events WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_event_deliveries WHERE event_id IN (
      SELECT id FROM cs_events WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_events WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2c. Carpool passengers → offers  (scoped via matches in user's teams)
  BEGIN
    DELETE FROM cs_carpool_passengers WHERE offer_id IN (
      SELECT id FROM cs_carpool_offers WHERE match_id IN (
        SELECT id FROM cs_matches WHERE team_id IN (
          SELECT id FROM cs_teams WHERE created_by = v_uid
        )
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_carpool_offers WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2d. Match-scoped leaf tables
  BEGIN
    DELETE FROM cs_match_lineup_slots WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_match_lineups WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_lineup_events WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_match_roster WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_match_availability WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_dinner_rsvps WHERE match_id IN (
      SELECT id FROM cs_matches WHERE team_id IN (
        SELECT id FROM cs_teams WHERE created_by = v_uid
      )
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_sub_requests WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2e. Notification prefs (team-scoped, nullable team_id)
  BEGIN
    DELETE FROM cs_notification_prefs WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2f. Invites
  BEGIN
    DELETE FROM cs_invites WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2g. Matches → team players → team members → teams
  BEGIN
    DELETE FROM cs_matches WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_team_players WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    DELETE FROM cs_team_members WHERE team_id IN (
      SELECT id FROM cs_teams WHERE created_by = v_uid
    );
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  -- 2h. Finally: delete the teams themselves
  PERFORM _cs_da_delete('cs_teams', 'created_by', v_uid);

  -- ══════════════════════════════════════════════════════════════
  -- PHASE 3: DELETE AUTH USER
  -- Remaining FKs with ON DELETE CASCADE / SET NULL fire here.
  -- ══════════════════════════════════════════════════════════════
  DELETE FROM auth.users WHERE id = v_uid;

  RAISE LOG 'cs_delete_account: completed for uid=%', v_uid;
END;
$$;

-- Only authenticated users may call this function.
GRANT EXECUTE ON FUNCTION public.cs_delete_account() TO authenticated;
-- Helpers are internal; no direct grant needed (called by DEFINER func above).

-- Reload PostgREST schema cache so the RPC is immediately available.
NOTIFY pgrst, 'reload schema';
