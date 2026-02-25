# Support Contact Setup

## Purpose

Adds a Supabase Edge Function `support-contact` that sends support emails via SendGrid to `info@onewell.ch` (or `SUPPORT_TO_EMAIL` override).

## Required Secrets

Set secrets in Supabase project:

```bash
supabase secrets set SENDGRID_API_KEY=YOUR_SENDGRID_API_KEY
supabase secrets set SENDGRID_FROM_EMAIL=no-reply@onewell.ch
supabase secrets set SUPPORT_TO_EMAIL=info@onewell.ch
```

Notes:
- `SENDGRID_FROM_EMAIL` must be verified in SendGrid.
- `SUPPORT_TO_EMAIL` is optional; default is `info@onewell.ch`.

## Deploy

```bash
supabase functions deploy support-contact
```

## Local Run (manual)

```bash
supabase start
supabase functions serve support-contact --no-verify-jwt
```

Example request:

```bash
curl -i --location --request POST "http://127.0.0.1:54321/functions/v1/support-contact" \
  --header "Content-Type: application/json" \
  --data '{
    "category": "TECHNICAL",
    "subject": "Login Problem",
    "message": "Ich kann mich seit heute nicht mehr anmelden. Bitte prüfen.",
    "email": "spieler@example.com",
    "userId": "00000000-0000-0000-0000-000000000000",
    "userEmail": "user@example.com",
    "platform": "ios",
    "appVersion": "unknown"
  }'
```

Expected responses:
- `200` → `{ "ok": true }`
- `400` → `{ "ok": false, "error": "validation_error" }`
- `429` → `{ "ok": false, "error": "rate_limited" }`
- `500` → `{ "ok": false, "error": "send_failed" }`

## Security Notes

- No SendGrid secret is used in Flutter client code.
- Client only calls Supabase function `support-contact`.
- SendGrid API key is read server-side via `Deno.env`.
