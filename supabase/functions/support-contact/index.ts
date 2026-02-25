import "@supabase/functions-js/edge-runtime.d.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const rateLimitStore = new Map<string, number[]>();

const ALLOWED_CATEGORIES = new Set(["TECHNICAL", "GENERAL", "FEEDBACK"]);

type SupportPayload = {
  category?: unknown;
  subject?: unknown;
  message?: unknown;
  email?: unknown;
  userId?: unknown;
  userEmail?: unknown;
  platform?: unknown;
  appVersion?: unknown;
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
    },
  });
}

function toTrimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const attempts = (rateLimitStore.get(ip) ?? []).filter(
    (ts) => now - ts < RATE_LIMIT_WINDOW_MS,
  );
  attempts.push(now);
  rateLimitStore.set(ip, attempts);
  return attempts.length > RATE_LIMIT_MAX;
}

function readClientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return "unknown";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  const ip = readClientIp(req);
  if (isRateLimited(ip)) {
    return jsonResponse(429, { ok: false, error: "rate_limited" });
  }

  let body: SupportPayload;
  try {
    body = (await req.json()) as SupportPayload;
  } catch {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }

  const category = toTrimmedString(body.category);
  const subject = toTrimmedString(body.subject);
  const message = toTrimmedString(body.message);
  const email = toTrimmedString(body.email);
  const userId = toTrimmedString(body.userId);
  const userEmail = toTrimmedString(body.userEmail);
  const platform = toTrimmedString(body.platform);
  const appVersion = toTrimmedString(body.appVersion);

  const messageLength = message?.length ?? 0;
  const hasEmail = !!email;

  if (!category || !ALLOWED_CATEGORIES.has(category)) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (!message || message.length < 10 || message.length > 4000) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (subject && subject.length > 200) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (email && (email.length > 200 || !isValidEmail(email))) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (userId && userId.length > 200) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (userEmail && (userEmail.length > 200 || !isValidEmail(userEmail))) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (platform && platform.length > 50) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }
  if (appVersion && appVersion.length > 100) {
    return jsonResponse(400, { ok: false, error: "validation_error" });
  }

  const sendGridApiKey = Deno.env.get("SENDGRID_API_KEY");
  const fromEmail = Deno.env.get("SENDGRID_FROM_EMAIL");
  const toEmail = Deno.env.get("SUPPORT_TO_EMAIL") ?? "info@onewell.ch";

  if (!sendGridApiKey || !fromEmail) {
    console.error("[support-contact] failed", {
      category,
      status: "missing_secrets",
      messageLength,
    });
    return jsonResponse(500, { ok: false, error: "send_failed" });
  }

  const subjectLabel = subject ?? "Neue Nachricht";
  const sendGridSubject = `[Lineup Support] ${category} - ${subjectLabel}`;
  const timestamp = new Date().toISOString();
  const replyTo = email ?? userEmail ?? null;

  const textBody =
    `Lineup Support Anfrage\n` +
    `\n` +
    `Category: ${category}\n` +
    `Subject: ${subject ?? "-"}\n` +
    `Message:\n${message}\n` +
    `\n` +
    `Provided Email: ${email ?? "-"}\n` +
    `User ID: ${userId ?? "-"}\n` +
    `User Email: ${userEmail ?? "-"}\n` +
    `Platform: ${platform ?? "-"}\n` +
    `App Version: ${appVersion ?? "-"}\n` +
    `Timestamp: ${timestamp}\n`;

  const sendGridPayload: Record<string, unknown> = {
    personalizations: [{ to: [{ email: toEmail }] }],
    from: { email: fromEmail },
    subject: sendGridSubject,
    content: [{ type: "text/plain", value: textBody }],
  };

  if (replyTo) {
    sendGridPayload.reply_to = { email: replyTo };
  }

  try {
    const sendResp = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${sendGridApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(sendGridPayload),
    });

    if (!sendResp.ok) {
      console.error("[support-contact] failed", {
        category,
        status: sendResp.status,
        messageLength,
      });
      return jsonResponse(500, { ok: false, error: "send_failed" });
    }

    console.log("[support-contact] ok", {
      category,
      hasEmail,
      messageLength,
    });
    return jsonResponse(200, { ok: true });
  } catch (e) {
    console.error("[support-contact] failed", {
      category,
      status: "request_error",
      messageLength,
      error: String(e),
    });
    return jsonResponse(500, { ok: false, error: "send_failed" });
  }
});
