// Supabase Edge Function: hf-keep-warm
// Pings HuggingFace inference every 10 min (via pg_cron) to keep Kael's
// model loaded. Default: Qwen2.5-1.5B-Instruct (fast, free).
Deno.serve(async () => {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  const hfModel = Deno.env.get("HF_MODEL_ID") ?? "Qwen/Qwen2.5-1.5B-Instruct";

  if (!hfToken) {
    return new Response(JSON.stringify({ warm: false, error: "HUGGINGFACE_TOKEN not set" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const start = Date.now();
    const res = await fetch(`https://api-inference.huggingface.co/models/${hfModel}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${hfToken}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(30_000),
      body: JSON.stringify({
        inputs: "<|im_start|>user\nping<|im_end|>\n<|im_start|>assistant\n",
        parameters: { max_new_tokens: 4, temperature: 0, return_full_text: false },
        options: { wait_for_model: false },
      }),
    });

    const elapsed = Date.now() - start;
    const data = await res.json().catch(() => null);
    const genText = Array.isArray(data) ? data[0]?.generated_text?.trim() : null;
    return new Response(JSON.stringify({ warm: res.ok && genText != null, ms: elapsed, model: hfModel }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ warm: false, error: e.message }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
