-- ═══════════════════════════════════════════════════════════════
-- Smoke Test for cs_delete_account()  (factory-reset version)
--
-- Run AFTER deploying cs_delete_account.sql.
-- This script verifies:
--   1. The RPC and helpers exist.
--   2. The helper functions work (column-existence checks).
--   3. (Optional) End-to-end: create a test user + team,
--      call the RPC, verify both are gone.
--
-- Safe to run on production – no destructive changes unless
-- you uncomment the E2E section.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 1. Verify functions exist  (expect 3 rows)
-- ─────────────────────────────────────────────────────────────

SELECT routine_name, routine_type
  FROM information_schema.routines
 WHERE routine_schema = 'public'
   AND routine_name IN ('cs_delete_account', '_cs_da_delete', '_cs_da_nullify')
 ORDER BY routine_name;
-- Expected: 3 rows


-- ─────────────────────────────────────────────────────────────
-- 2. Verify column-existence guards  (should be no-ops)
-- ─────────────────────────────────────────────────────────────

-- Non-existent table → no-op:
SELECT _cs_da_delete(
  'nonexistent_table_xyz', 'user_id',
  '00000000-0000-0000-0000-000000000000'::uuid);
-- ✅ No error

-- Non-existent column → no-op:
SELECT _cs_da_delete(
  'cs_app_profiles', 'nonexistent_col_xyz',
  '00000000-0000-0000-0000-000000000000'::uuid);
-- ✅ No error


-- ─────────────────────────────────────────────────────────────
-- 3. Verify NO _cs_da_nullify calls remain in cs_delete_account
--    (factory-reset: everything is DELETE, never NULL)
-- ─────────────────────────────────────────────────────────────

SELECT prosrc
  FROM pg_proc
 WHERE proname = 'cs_delete_account'
   AND prosrc ILIKE '%_cs_da_nullify%';
-- Expected: 0 rows  (no nullify calls in the function body)


-- ─────────────────────────────────────────────────────────────
-- 4. Verify cs_teams.created_by handling is DELETE, not UPDATE
-- ─────────────────────────────────────────────────────────────

SELECT prosrc
  FROM pg_proc
 WHERE proname = 'cs_delete_account'
   AND (   prosrc ILIKE '%UPDATE%cs_teams%SET%created_by%'
        OR prosrc ILIKE '%nullify%cs_teams%');
-- Expected: 0 rows  (no UPDATE/nullify on cs_teams)


-- ─────────────────────────────────────────────────────────────
-- 5. List all cs_* tables with uuid columns  (audit reference)
-- ─────────────────────────────────────────────────────────────

SELECT c.table_name, c.column_name, c.is_nullable,
       tc.constraint_name,
       ccu.table_schema AS ref_schema,
       ccu.table_name   AS ref_table
  FROM information_schema.columns c
  LEFT JOIN information_schema.key_column_usage kcu
    ON kcu.table_schema = c.table_schema
   AND kcu.table_name   = c.table_name
   AND kcu.column_name  = c.column_name
  LEFT JOIN information_schema.table_constraints tc
    ON tc.constraint_name  = kcu.constraint_name
   AND tc.table_schema     = kcu.table_schema
   AND tc.constraint_type  = 'FOREIGN KEY'
  LEFT JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema    = tc.table_schema
 WHERE c.table_schema = 'public'
   AND c.table_name LIKE 'cs\_%'
   AND c.data_type = 'uuid'
   AND c.column_name NOT IN ('id')
 ORDER BY c.table_name, c.column_name;
-- Review: every user-referencing row should be handled
--         in cs_delete_account()


-- ─────────────────────────────────────────────────────────────
-- 6. (OPTIONAL) End-to-end test
--    Uncomment to run – creates a temp user + team, then
--    calls cs_delete_account() and verifies everything is gone.
--    WARNING: creates + immediately deletes real rows.
-- ─────────────────────────────────────────────────────────────

-- DO $$
-- DECLARE
--   v_test_uid UUID;
--   v_team_id  UUID;
-- BEGIN
--   -- A. Create a test user in auth.users
--   INSERT INTO auth.users (
--     instance_id, id, aud, role,
--     email, encrypted_password,
--     email_confirmed_at, created_at, updated_at,
--     confirmation_token, recovery_token,
--     raw_app_meta_data, raw_user_meta_data
--   ) VALUES (
--     '00000000-0000-0000-0000-000000000000',
--     gen_random_uuid(), 'authenticated', 'authenticated',
--     'delete-test-' || gen_random_uuid() || '@test.local',
--     crypt('testpass123', gen_salt('bf')),
--     now(), now(), now(),
--     '', '',
--     '{"provider":"email","providers":["email"]}'::jsonb,
--     '{}'::jsonb
--   ) RETURNING id INTO v_test_uid;
--
--   RAISE NOTICE 'Created test user: %', v_test_uid;
--
--   -- B. Create an app profile
--   INSERT INTO cs_app_profiles (user_id, email, display_name)
--   VALUES (v_test_uid, 'test@test.local', 'Test Delete User');
--
--   -- C. Create a team owned by this user
--   INSERT INTO cs_teams (id, name, season_year, created_by, created_at)
--   VALUES (gen_random_uuid(), 'DELETE-TEST-TEAM', 2099, v_test_uid, now())
--   RETURNING id INTO v_team_id;
--
--   RAISE NOTICE 'Created test team: %', v_team_id;
--
--   -- D. Create a team membership
--   INSERT INTO cs_team_members (team_id, user_id, role)
--   VALUES (v_team_id, v_test_uid, 'captain');
--
--   -- E. Fake the JWT claim so auth.uid() returns our test user
--   PERFORM set_config('request.jwt.claim.sub', v_test_uid::text, true);
--
--   -- F. Run the delete function
--   PERFORM cs_delete_account();
--
--   -- G. Assert: auth user is gone
--   IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_test_uid) THEN
--     RAISE EXCEPTION 'FAIL: auth user still exists after cs_delete_account()';
--   ELSE
--     RAISE NOTICE 'PASS: auth user deleted';
--   END IF;
--
--   -- H. Assert: team is gone
--   IF EXISTS (SELECT 1 FROM cs_teams WHERE id = v_team_id) THEN
--     RAISE EXCEPTION 'FAIL: cs_teams row still exists';
--   ELSE
--     RAISE NOTICE 'PASS: team deleted';
--   END IF;
--
--   -- I. Assert: app profile is gone
--   IF EXISTS (SELECT 1 FROM cs_app_profiles WHERE user_id = v_test_uid) THEN
--     RAISE EXCEPTION 'FAIL: app profile still exists';
--   ELSE
--     RAISE NOTICE 'PASS: app profile deleted';
--   END IF;
--
--   -- J. Assert: team membership is gone
--   IF EXISTS (SELECT 1 FROM cs_team_members WHERE team_id = v_team_id) THEN
--     RAISE EXCEPTION 'FAIL: team membership still exists';
--   ELSE
--     RAISE NOTICE 'PASS: team membership deleted';
--   END IF;
--
--   RAISE NOTICE '=== All smoke tests passed ===';
-- END;
-- $$;
