// Supabase Edge Function: hf-keep-warm
// Pings HuggingFace inference every 10 min (via pg_cron) to keep Kael's
// model loaded. Router endpoint is OpenAI-compatible and resolves from the
// Supabase edge runtime (api-inference.huggingface.co does NOT). Default:
// meta-llama/Llama-3.1-8B-Instruct — verified on this account's free tier.
Deno.serve(async () => {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  const hfModel = Deno.env.get("HF_MODEL_ID") ?? "meta-llama/Llama-3.1-8B-Instruct";

  if (!hfToken) {
    return new Response(JSON.stringify({ warm: false, error: "HUGGINGFACE_TOKEN not set" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const start = Date.now();
    const res = await fetch("https://router.huggingface.co/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${hfToken}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(30_000),
      body: JSON.stringify({
        model: hfModel,
        messages: [{ role: "user", content: "ping" }],
        max_tokens: 4,
        temperature: 0,
      }),
    });

    const elapsed = Date.now() - start;
    const data = await res.json().catch(() => null);
    const choice = Array.isArray(data?.choices) ? data.choices[0] : undefined;
    const message = choice && typeof choice.message === "object" ? choice.message : undefined;
    const genText = message && typeof message.content === "string" ? message.content.trim() : null;
    return new Response(JSON.stringify({ warm: res.ok && genText != null, ms: elapsed, model: hfModel }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ warm: false, error: `${e instanceof Error ? e.message : e}` }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});