// ── Invite Redirect Edge Function ─────────────────────────────────
// Serves a tiny HTML page that:
//   1. Immediately tries to open the app via lineup://join?token=XYZ
//   2. After a short delay, shows a fallback message with App-Store links
//
// Usage: https://<project-ref>.supabase.co/functions/v1/invite-redirect?token=XYZ
// ──────────────────────────────────────────────────────────────────

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve((req: Request) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";

  if (!token) {
    return new Response("Missing token parameter.", { status: 400 });
  }

  const deepLink = `lineup://join?token=${encodeURIComponent(token)}`;

  const html = `<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Lineup – Einladung</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0a0a0a;
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      background: #1a1a1a;
      border-radius: 16px;
      padding: 32px 24px;
      max-width: 380px;
      width: 100%;
      text-align: center;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
    }
    .icon { font-size: 48px; margin-bottom: 16px; }
    h1 { font-size: 22px; font-weight: 700; margin-bottom: 8px; }
    p { font-size: 15px; color: #aaa; margin-bottom: 24px; line-height: 1.5; }
    .btn {
      display: inline-block;
      background: #10b981;
      color: #fff;
      text-decoration: none;
      padding: 14px 28px;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 600;
      transition: background 0.2s;
    }
    .btn:hover { background: #059669; }
    .hint { font-size: 12px; color: #666; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">🎾</div>
    <h1>Du wurdest eingeladen!</h1>
    <p>Öffne die Lineup App, um dem Team beizutreten.</p>
    <a class="btn" id="openApp" href="${deepLink}">App öffnen</a>
    <p class="hint" id="fallback" style="display:none;">
      Falls die App nicht geöffnet wurde, stelle sicher dass Lineup installiert ist.
    </p>
  </div>
  <script>
    // Try to open the app automatically
    window.location.href = "${deepLink}";
    // Show fallback hint after 2 seconds
    setTimeout(function() {
      document.getElementById('fallback').style.display = 'block';
    }, 2000);
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache",
    },
  });
});
