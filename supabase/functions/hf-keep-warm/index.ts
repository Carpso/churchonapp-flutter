// Supabase Edge Function: hf-keep-warm
// Pings the active AI provider every 10 min (via pg_cron) to keep the model
// loaded. Goes through the shared multi-provider layer (`_shared/ai.ts`) —
// Cloudflare Workers AI (primary, when configured) with HuggingFace as the
// automatic fallback, so whichever provider serves Kael is kept warm.
import { callModel, getAiHealth } from "../_shared/ai.ts";

Deno.serve(async () => {
  const health = getAiHealth();

  if (health.active_provider === "none") {
    return new Response(
      JSON.stringify({ warm: false, error: "No AI provider configured", secrets: health.secrets }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const start = Date.now();
    const { provider } = await callModel(
      [{ role: "user", content: "ping" }],
      { maxTokens: 4, temperature: 0, label: "hf-keep-warm" },
    );
    return new Response(
      JSON.stringify({ warm: true, ms: Date.now() - start, provider }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ warm: false, error: `${e instanceof Error ? e.message : e}`, provider: health.active_provider }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
