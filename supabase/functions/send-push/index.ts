// ╔══════════════════════════════════════════════════════════════════╗
// ║  CourtSwiss – send-push Edge Function                          ║
// ║                                                                ║
// ║  Processes pending push deliveries from cs_event_deliveries    ║
// ║  and sends them via Firebase Cloud Messaging HTTP v1 API.      ║
// ║                                                                ║
// ║  ENV secrets required:                                         ║
// ║    GOOGLE_SERVICE_ACCOUNT_JSON – Firebase SA credentials       ║
// ║    SUPABASE_URL                – (auto-set by Supabase)        ║
// ║    SUPABASE_SERVICE_ROLE_KEY   – (auto-set by Supabase)        ║
// ║                                                                ║
// ║  Invoke:                                                       ║
// ║    POST /functions/v1/send-push                                ║
// ║    Body: { "batch_size": 100 }  (optional)                     ║
// ║                                                                ║
// ║  Intended to be called via cron (every 1–2 minutes).           ║
// ╚══════════════════════════════════════════════════════════════════╝

import "@supabase/functions-js/edge-runtime.d.ts";

// ─── Helpers: Base64URL encoding ─────────────────────────────────

function base64urlEncode(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlEncodeStr(str: string): string {
  return base64urlEncode(new TextEncoder().encode(str));
}

// ─── Google OAuth2: Service Account JWT → Access Token ───────────

async function importPKCS8Key(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

async function getGoogleAccessToken(
  sa: { client_email: string; private_key: string }
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64urlEncodeStr(
    JSON.stringify({ alg: "RS256", typ: "JWT" })
  );
  const payload = base64urlEncodeStr(
    JSON.stringify({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: "https://oauth2.googleapis.com/token",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      iat: now,
      exp: now + 3600,
    })
  );

  const unsigned = `${header}.${payload}`;
  const key = await importPKCS8Key(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned)
  );
  const jwt = `${unsigned}.${base64urlEncode(new Uint8Array(sig))}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  const data = await resp.json();
  if (!data.access_token) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

// ─── FCM v1: Send a single push message ─────────────────────────

interface FcmResult {
  success: boolean;
  error?: string;
}

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  platform: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<FcmResult> {
  const message: Record<string, unknown> = {
    token: deviceToken,
    notification: { title, body },
    data,
  };

  // Platform-specific config
  if (platform === "android") {
    message.android = {
      priority: "high",
      notification: { sound: "default", channel_id: "lineup_default" },
    };
  } else if (platform === "ios") {
    message.apns = {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          "content-available": 1,
        },
      },
    };
  }

  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    });

    if (resp.ok) {
      return { success: true };
    }

    const errBody = await resp.text();

    // Token invalid/expired → should be cleaned up
    if (resp.status === 404 || resp.status === 400) {
      return {
        success: false,
        error: `fcm_${resp.status}: ${errBody.substring(0, 200)}`,
      };
    }

    return {
      success: false,
      error: `fcm_${resp.status}: ${errBody.substring(0, 200)}`,
    };
  } catch (e) {
    return { success: false, error: `fetch_error: ${String(e)}` };
  }
}

// ─── Main handler ────────────────────────────────────────────────

Deno.serve(async (req) => {
  const startTime = Date.now();

  // ── 1. Parse request ────────────────────────────────────────
  let batchSize = 100;
  try {
    const body = await req.json();
    if (body?.batch_size && typeof body.batch_size === "number") {
      batchSize = Math.min(body.batch_size, 500);
    }
  } catch {
    // No body or invalid JSON → use defaults
  }

  // ── 2. Load Google Service Account ──────────────────────────
  const saJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!saJson) {
    return new Response(
      JSON.stringify({ error: "GOOGLE_SERVICE_ACCOUNT_JSON not configured" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  let serviceAccount: {
    client_email: string;
    private_key: string;
    project_id: string;
  };
  try {
    serviceAccount = JSON.parse(saJson);
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid GOOGLE_SERVICE_ACCOUNT_JSON" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const projectId = serviceAccount.project_id;
  if (!projectId) {
    return new Response(
      JSON.stringify({ error: "project_id missing in service account" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 3. Get Google access token ──────────────────────────────
  let accessToken: string;
  try {
    accessToken = await getGoogleAccessToken(serviceAccount);
  } catch (e) {
    return new Response(
      JSON.stringify({ error: `Auth failed: ${String(e)}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 4. Connect to Supabase (service_role) ───────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Use raw SQL via PostgREST RPC for batch processing
  const rpcUrl = `${supabaseUrl}/rest/v1/rpc/cs_process_pending_deliveries`;
  const batchResp = await fetch(rpcUrl, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({ p_batch_size: batchSize }),
  });

  if (!batchResp.ok) {
    const errText = await batchResp.text();
    return new Response(
      JSON.stringify({ error: `RPC failed: ${errText}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const deliveries = await batchResp.json();

  if (!Array.isArray(deliveries) || deliveries.length === 0) {
    return new Response(
      JSON.stringify({
        sent: 0,
        failed: 0,
        skipped: 0,
        duration_ms: Date.now() - startTime,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 5. Send FCM messages ────────────────────────────────────
  let sent = 0;
  let failed = 0;
  const errors: string[] = [];

  for (const delivery of deliveries) {
    const {
      delivery_id,
      title,
      body,
      payload,
      device_tokens,
    } = delivery;

    // Build data payload (all values must be strings for FCM)
    const data: Record<string, string> = {};
    if (payload?.team_id) data.team_id = String(payload.team_id);
    if (payload?.match_id) data.match_id = String(payload.match_id);
    if (delivery.event_type) data.event_type = delivery.event_type;

    let allSuccess = true;
    let lastError = "";

    // Send to each device token for this user
    for (const dt of device_tokens || []) {
      const result = await sendFcmMessage(
        accessToken,
        projectId,
        dt.token,
        dt.platform,
        title || "Lineup",
        body || "",
        data
      );

      if (!result.success) {
        allSuccess = false;
        lastError = result.error || "unknown";
        console.error(
          `FCM send failed: delivery=${delivery_id} ` +
          `token=${dt.token.substring(0, 12)}… error=${result.error}`
        );
      }
    }

    // ── 6. Update delivery status ─────────────────────────────
    const status = allSuccess ? "sent" : "failed";
    if (allSuccess) sent++;
    else {
      failed++;
      errors.push(`${delivery_id}: ${lastError}`);
    }

    const markUrl = `${supabaseUrl}/rest/v1/rpc/cs_mark_delivery_result`;
    await fetch(markUrl, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_delivery_id: delivery_id,
        p_status: status,
        p_error: allSuccess ? null : lastError.substring(0, 500),
      }),
    });
  }

  // ── 7. Response ─────────────────────────────────────────────
  const result = {
    processed: deliveries.length,
    sent,
    failed,
    errors: errors.slice(0, 10), // Limit error details
    duration_ms: Date.now() - startTime,
  };

  console.log(`send-push complete: ${JSON.stringify(result)}`);

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" },
  });
});
