-- ═══════════════════════════════════════════════════════════════════
--  NOTIFICATION PIPELINE DEBUG v3
--  Run this to diagnose why notifications aren't working.
--  Bitte im Supabase SQL Editor ausführen.
-- ═══════════════════════════════════════════════════════════════════

-- 1. EVENT ÜBERSICHT: Welche Event-Typen existieren?
--    Zeigt ob dinner_rsvp, expense_added etc. überhaupt erstellt werden.
SELECT event_type, count(*) AS cnt,
       max(created_at) AS latest
FROM public.cs_events
GROUP BY event_type
ORDER BY latest DESC;

-- 2. LETZTE 15 EVENTS (alle Typen)
SELECT id::text, created_at::text, event_type, title,
       substring(body for 80) AS body_preview,
       recipient_filter, recipient_user_id::text,
       created_by::text, dedupe_key
FROM public.cs_events
ORDER BY created_at DESC
LIMIT 15;

-- 3. DELIVERIES für die letzten Carpool-Events
--    Prüft ob der Fahrer/Captain eine Delivery bekommt
SELECT d.id::text, d.status, d.user_id::text AS delivery_to,
       e.event_type, e.title,
       e.recipient_user_id::text AS intended_recipient,
       e.created_by::text AS event_creator,
       e.recipient_filter
FROM public.cs_event_deliveries d
JOIN public.cs_events e ON e.id = d.event_id
WHERE e.event_type IN (
  'carpool_passenger_joined','carpool_passenger_left',
  'dinner_rsvp','availability_changed',
  'expense_added','expense_share_paid','expense_share_due'
)
ORDER BY d.created_at DESC
LIMIT 15;

-- 4. NOTIFICATIONS: In-App-Benachrichtigungen
SELECT id::text, created_at::text, recipient_user_id::text,
       type, title, substring(body for 60) AS body_preview
FROM public.cs_notifications
WHERE type IN (
  'carpool_passenger_joined','carpool_passenger_left',
  'dinner_rsvp','availability_changed',
  'expense_added','expense_share_paid','expense_share_due'
)
ORDER BY created_at DESC
LIMIT 15;

-- 5. TRIGGERS: Welche Trigger sind installiert?
SELECT event_object_table AS tbl,
       trigger_name,
       event_manipulation AS event,
       action_timing AS timing,
       action_statement AS func
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table IN (
    'cs_match_availability',
    'cs_dinner_rsvps',
    'cs_carpool_passengers',
    'cs_carpool_offers',
    'cs_events',
    'cs_event_deliveries',
    'cs_expenses',
    'cs_expense_shares'
  )
ORDER BY event_object_table, trigger_name;

-- 6. TRIGGER-FUNKTIONEN: Existieren alle benötigten Funktionen?
DO $$
DECLARE
  v_name text;
  v_funcs text[] := ARRAY[
    'fn_emit_availability_changed_event',
    'fn_emit_dinner_rsvp_event',
    'fn_cs_event_fanout',
    'fn_bridge_delivery_to_notification',
    'fn_emit_expense_created_event',
    'fn_emit_expense_share_paid_event',
    'fn_emit_expense_share_due_event',
    'fn_emit_carpool_passenger_joined_event',
    'fn_emit_carpool_passenger_left_event',
    'fn_emit_carpool_created_event',
    'fn_emit_lineup_published_event'
  ];
BEGIN
  FOREACH v_name IN ARRAY v_funcs LOOP
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = v_name) THEN
      RAISE NOTICE 'OK: %() exists', v_name;
    ELSE
      RAISE WARNING 'MISSING: %() does NOT exist!', v_name;
    END IF;
  END LOOP;
END
$$;

-- 7. TEAM-MITGLIEDER: Wer ist Captain?
--    Prüft ob Captain in cs_team_members steht
SELECT tm.team_id::text, tm.user_id::text, tm.role,
       t.created_by::text AS team_creator,
       CASE WHEN tm.user_id = t.created_by THEN 'JA' ELSE 'nein' END AS is_creator
FROM public.cs_team_members tm
JOIN public.cs_teams t ON t.id = tm.team_id
ORDER BY tm.team_id, tm.role DESC
LIMIT 20;

-- 8. DEVICE TOKENS: Sind Geräte registriert?
SELECT user_id::text, platform, LEFT(token, 20) || '...' AS token_prefix,
       device_id, enabled, updated_at::text
FROM public.cs_device_tokens
ORDER BY updated_at DESC
LIMIT 5;

-- 9. MANUELLER TEST: Dinner-Trigger simulieren
--    Prüft die Namensauflösung über claimed_by
SELECT tp.team_id::text, tp.claimed_by::text,
       CONCAT_WS(' ', tp.first_name, tp.last_name) AS player_name
FROM public.cs_team_players tp
WHERE tp.claimed_by IS NOT NULL
LIMIT 10;
