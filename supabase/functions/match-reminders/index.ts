// ╔══════════════════════════════════════════════════════════════════╗
// ║  CourtSwiss – match-reminders Edge Function                    ║
// ║                                                                ║
// ║  Creates idempotent reminder events (24h + 2h before match).   ║
// ║  Calls the SQL function cs_create_match_reminders().           ║
// ║                                                                ║
// ║  Intended to be called via Supabase Cron (every 5 minutes).    ║
// ║                                                                ║
// ║  ENV (auto-set by Supabase):                                   ║
// ║    SUPABASE_URL                                                ║
// ║    SUPABASE_SERVICE_ROLE_KEY                                   ║
// ╚══════════════════════════════════════════════════════════════════╝

import "@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (_req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  console.log("match-reminders: checking for upcoming matches…");

  try {
    const rpcUrl = `${supabaseUrl}/rest/v1/rpc/cs_create_match_reminders`;
    const resp = await fetch(rpcUrl, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });

    if (!resp.ok) {
      const errText = await resp.text();
      console.error(`match-reminders RPC failed: ${resp.status} ${errText}`);
      return new Response(
        JSON.stringify({ error: `RPC failed: ${errText}` }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const result = await resp.json();
    console.log(`match-reminders: ${JSON.stringify(result)}`);

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(`match-reminders error: ${String(e)}`);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
