// ─── Multi-provider AI layer ────────────────────────────────────────────────
//
// One place for every Edge Function that talks to an LLM. Provider chain:
//
//   1. Cloudflare Workers AI (primary) — used ONLY when BOTH
//      `CLOUDFLARE_ACCOUNT_ID` AND a token (`CLOUDFLARE_AI_TOKEN`, falling back
//      to `CLOUDFLARE_API_TOKEN`) are present.
//   2. HuggingFace router (fallback) — the previous behaviour, unchanged.
//   3. A clear error when neither provider is configured.
//
// Provider selection is automatic: until a Cloudflare token is added the
// HuggingFace path behaves exactly as before. Supabase Edge Functions are Deno
// and CANNOT use a Cloudflare Workers `env.AI` binding, so Workers AI is called
// over its REST API. Set `CF_AI_GATEWAY_URL` (e.g.
// `https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/workers-ai`) to
// route through an AI Gateway instead of the raw Cloudflare endpoint.
//
// Client contract is untouched:
//   - chat        → SSE `data: {"chunk": "..."}` … `data: {"done": true}`
//   - other       → JSON `{"response": "..."}` (callModel)
//
// Secrets read (never exposed):
//   CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_AI_TOKEN | CLOUDFLARE_API_TOKEN,
//   CF_AI_MODEL (default `@cf/meta/llama-3.3-70b-instruct-fp8-fast`),
//   CF_AI_GATEWAY_URL (optional),
//   HUGGINGFACE_TOKEN, HF_MODEL_ID (default `meta-llama/Llama-3.1-8B-Instruct`).

export type AiProvider = "workers-ai" | "huggingface";

export interface ChatMessage {
  role: string;
  content: string;
}

export interface CallOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  /** Per-attempt request timeout in ms (default 60s). */
  timeoutMs?: number;
  /** HuggingFace cold-start retry budget in ms (default 150s). */
  coldStartMs?: number;
  /** Log label, e.g. "kael-ai:chat". */
  label?: string;
}

export interface CallResult {
  text: string;
  provider: AiProvider;
}

export interface StreamResult {
  provider: AiProvider;
  /** App-format SSE body: `data: {"chunk": ...}` … `data: {"done": true}`. */
  stream: ReadableStream<Uint8Array>;
}

/** Provider failure carrying the HTTP status so callers can special-case 429. */
export class AiProviderError extends Error {
  provider: AiProvider;
  status: number;
  retryAfter?: string;

  constructor(
    provider: AiProvider,
    status: number,
    message: string,
    retryAfter?: string,
  ) {
    super(message);
    this.name = "AiProviderError";
    this.provider = provider;
    this.status = status;
    this.retryAfter = retryAfter;
  }
}

const HF_API_BASE = "https://router.huggingface.co/v1";
const HF_DEFAULT_MODEL = "meta-llama/Llama-3.1-8B-Instruct";
const CF_DEFAULT_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

export interface WorkersAiConfig {
  accountId: string;
  token: string;
  model: string;
  /** When set, replaces the raw Cloudflare endpoint (AI Gateway). */
  gatewayBase: string | null;
}

export interface HuggingFaceConfig {
  token: string;
  model: string;
}

export interface AiConfig {
  workersAi: WorkersAiConfig | null;
  huggingface: HuggingFaceConfig | null;
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

/** Resolves the provider configuration from the environment. */
export function getAiConfig(): AiConfig {
  const accountId = env("CLOUDFLARE_ACCOUNT_ID");
  const token = env("CLOUDFLARE_AI_TOKEN") || env("CLOUDFLARE_API_TOKEN");
  const cfModel = env("CF_AI_MODEL") || CF_DEFAULT_MODEL;
  const gatewayBase = env("CF_AI_GATEWAY_URL") || null;

  const hfToken = env("HUGGINGFACE_TOKEN");

  return {
    workersAi: accountId && token
      ? { accountId, token, model: cfModel, gatewayBase }
      : null,
    huggingface: hfToken
      ? { token: hfToken, model: env("HF_MODEL_ID") || HF_DEFAULT_MODEL }
      : null,
  };
}

export function activeProvider(cfg: AiConfig = getAiConfig()): AiProvider | "none" {
  if (cfg.workersAi) return "workers-ai";
  if (cfg.huggingface) return "huggingface";
  return "none";
}

export function hasAnyProvider(cfg: AiConfig = getAiConfig()): boolean {
  return Boolean(cfg.workersAi || cfg.huggingface);
}

/** Secret-free snapshot for the `GET ?health=ai` probe. */
export function getAiHealth() {
  const cfg = getAiConfig();
  return {
    status: hasAnyProvider(cfg) ? "ok" : "unconfigured",
    active_provider: activeProvider(cfg),
    providers: {
      workers_ai: cfg.workersAi
        ? { configured: true, model: cfg.workersAi.model, gateway: Boolean(cfg.workersAi.gatewayBase) }
        : { configured: false, model: null, gateway: false },
      huggingface: cfg.huggingface
        ? { configured: true, model: cfg.huggingface.model }
        : { configured: false, model: null },
    },
    secrets: {
      CLOUDFLARE_ACCOUNT_ID: Boolean(env("CLOUDFLARE_ACCOUNT_ID")),
      CLOUDFLARE_AI_TOKEN: Boolean(env("CLOUDFLARE_AI_TOKEN")),
      CLOUDFLARE_API_TOKEN: Boolean(env("CLOUDFLARE_API_TOKEN")),
      CF_AI_MODEL: Boolean(env("CF_AI_MODEL")),
      CF_AI_GATEWAY_URL: Boolean(env("CF_AI_GATEWAY_URL")),
      HUGGINGFACE_TOKEN: Boolean(env("HUGGINGFACE_TOKEN")),
      HF_MODEL_ID: Boolean(env("HF_MODEL_ID")),
    },
  };
}

// ─── URL / parsing helpers ──────────────────────────────────────────────────

function workersAiEndpoint(cfg: WorkersAiConfig): string {
  if (cfg.gatewayBase) {
    return `${cfg.gatewayBase.replace(/\/+$/, "")}/${cfg.model}`;
  }
  return `https://api.cloudflare.com/client/v4/accounts/${cfg.accountId}/ai/run/${cfg.model}`;
}

/** Strips chat-format tokens some models echo back. */
function stripMarkers(text: string): string {
  return text
    .replace(/<\|im_start\|>[\s\S]*?<\|im_end\|>/g, "")
    .replace(/<\|im_start\|>/g, "")
    .replace(/<\|im_end\|>/g, "")
    .trim();
}

function extractWorkersAiText(data: unknown): string | null {
  const root = (data ?? {}) as Record<string, unknown>;
  const result = (root.result ?? root) as Record<string, unknown>;
  const direct = typeof result.response === "string" ? result.response : null;
  const choices = result.choices as Array<{ message?: { content?: string } }> | undefined;
  const openai = choices?.[0]?.message?.content;
  const text = direct ?? (typeof openai === "string" ? openai : null);
  return text ? stripMarkers(text) : null;
}

function logServed(label: string | undefined, provider: AiProvider, model: string) {
  console.log(`[ai] ${label ?? "request"} served by ${provider} (${model})`);
}

// ─── Non-streaming provider calls ───────────────────────────────────────────

async function callWorkersAi(
  messages: ChatMessage[],
  opts: CallOptions,
  cfg: WorkersAiConfig,
): Promise<string> {
  const response = await fetch(workersAiEndpoint(cfg), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(opts.timeoutMs ?? 60_000),
    body: JSON.stringify({
      messages,
      max_tokens: opts.maxTokens ?? 512,
      temperature: opts.temperature ?? 0.7,
      top_p: opts.topP ?? 0.9,
      stream: false,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new AiProviderError(
      "workers-ai",
      response.status,
      `Workers AI error ${response.status}: ${errBody.slice(0, 200)}`,
    );
  }

  const data = await response.json().catch(() => null);
  const root = (data ?? {}) as Record<string, unknown>;
  if (root.success === false) {
    const errors = JSON.stringify(root.errors ?? []).slice(0, 200);
    throw new AiProviderError("workers-ai", 502, `Workers AI error: ${errors}`);
  }

  const text = extractWorkersAiText(data);
  if (!text) throw new AiProviderError("workers-ai", 502, "Workers AI returned empty response");
  return text;
}

async function callHuggingFace(
  messages: ChatMessage[],
  opts: CallOptions,
  cfg: HuggingFaceConfig,
): Promise<string> {
  const body = JSON.stringify({
    model: cfg.model,
    messages,
    max_tokens: opts.maxTokens ?? 512,
    temperature: opts.temperature ?? 0.7,
    top_p: opts.topP ?? 0.9,
  });

  const doFetch = (timeoutMs: number) =>
    fetch(`${HF_API_BASE}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.token}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(timeoutMs),
      body,
    });

  // Free-tier models sleep after ~15 min idle. A "loading" model may hold the
  // request or abort it instead of answering 503 quickly — so the first
  // attempt gets 60s and a retry with a 150s budget instead of failing fast.
  const first = opts.timeoutMs ?? 60_000;
  const cold = opts.coldStartMs ?? 150_000;

  let response: Response;
  try {
    response = await doFetch(first);
  } catch {
    response = await doFetch(cold);
  }
  if (response.status === 503) response = await doFetch(cold);

  if (response.status === 429) {
    const errBody = await response.text().catch(() => "");
    throw new AiProviderError(
      "huggingface",
      429,
      `HuggingFace error 429: ${errBody.slice(0, 200)}`,
      response.headers.get("retry-after") ?? "30",
    );
  }

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new AiProviderError(
      "huggingface",
      response.status,
      `HuggingFace error ${response.status}: ${errBody.slice(0, 200)}`,
    );
  }

  const data = await response.json().catch(() => null);
  const raw = (data as { choices?: Array<{ message?: { content?: string } }> })
    ?.choices?.[0]?.message?.content;
  const text = typeof raw === "string" ? stripMarkers(raw) : "";
  if (!text) throw new AiProviderError("huggingface", 502, "HuggingFace returned empty response");
  return text;
}

// ─── Public non-streaming API ───────────────────────────────────────────────

/**
 * Calls the model with automatic provider fallback.
 * Workers AI (when configured) → HuggingFace → clear error.
 */
export async function callModel(
  messages: ChatMessage[],
  opts: CallOptions = {},
): Promise<CallResult> {
  const cfg = getAiConfig();

  if (cfg.workersAi) {
    try {
      const text = await callWorkersAi(messages, opts, cfg.workersAi);
      logServed(opts.label, "workers-ai", cfg.workersAi.model);
      return { text, provider: "workers-ai" };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn(`[ai] Workers AI failed, falling back: ${msg}`);
      if (!cfg.huggingface) throw e;
    }
  }

  if (cfg.huggingface) {
    const text = await callHuggingFace(messages, opts, cfg.huggingface);
    logServed(opts.label, "huggingface", cfg.huggingface.model);
    return { text, provider: "huggingface" };
  }

  throw new Error(
    "No AI provider configured — set CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_AI_TOKEN (Workers AI) or HUGGINGFACE_TOKEN",
  );
}

// ─── Streaming ──────────────────────────────────────────────────────────────

/**
 * Converts a provider SSE body into the app's own SSE format, emitting
 * `data: {"chunk": "..."}` for each token and `data: {"done": true}` at the end.
 */
function sseToAppStream(
  body: ReadableStream<Uint8Array>,
  extract: (payload: unknown) => string | null,
): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  return new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = body.getReader();
      let buffer = "";
      let doneSent = false;
      const emit = (obj: unknown) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));
      };
      const emitDone = () => {
        if (doneSent) return;
        doneSent = true;
        emit({ done: true });
      };

      const handleLine = (rawLine: string): boolean => {
        const line = rawLine.trim();
        if (!line.startsWith("data:")) return false;
        const jsonStr = line.slice(5).trim();
        if (jsonStr === "") return false;
        if (jsonStr === "[DONE]") {
          emitDone();
          return true;
        }
        let payload: unknown;
        try {
          payload = JSON.parse(jsonStr);
        } catch {
          return false;
        }
        const root = payload as Record<string, unknown>;
        if (root?.error) {
          const err = typeof root.error === "string" ? root.error : JSON.stringify(root.error);
          emit({ error: err, done: true });
          doneSent = true;
          return true;
        }
        const chunk = extract(payload);
        if (chunk && chunk.length > 0) emit({ chunk });
        return false;
      };

      try {
        let finished = false;
        while (!finished) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            if (handleLine(line)) {
              finished = true;
              break;
            }
          }
        }
        if (!finished && buffer.trim() !== "") handleLine(buffer);
        emitDone();
      } catch (e) {
        emit({ error: e instanceof Error ? e.message : "AI stream error", done: true });
        doneSent = true;
      } finally {
        try {
          reader.releaseLock();
        } catch {
          // already released
        }
        try {
          controller.close();
        } catch {
          // already closed
        }
      }
    },
    cancel() {
      try {
        body.cancel();
      } catch {
        // already cancelled
      }
    },
  });
}

/** Emits the full text as paced word chunks (legacy simulated stream). */
function simulateTextStream(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      const words = text.split(/(\s+)/);
      let buffer = "";
      let wordIndex = 0;

      const sendChunk = () => {
        if (wordIndex >= words.length) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`));
          controller.close();
          return;
        }

        const chunkSize = 2 + Math.floor(Math.random() * 4);
        for (let i = 0; i < chunkSize && wordIndex < words.length; i++, wordIndex++) {
          buffer += words[wordIndex];
        }

        if (buffer.length > 0) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ chunk: buffer })}\n\n`));
          buffer = "";
        }

        setTimeout(sendChunk, 15 + Math.random() * 25);
      };

      sendChunk();
    },
  });
}

function extractWorkersAiDelta(payload: unknown): string | null {
  const root = (payload ?? {}) as Record<string, unknown>;
  if (typeof root.response === "string") return root.response;
  const choices = root.choices as Array<{ delta?: { content?: string } }> | undefined;
  const openai = choices?.[0]?.delta?.content;
  return typeof openai === "string" ? openai : null;
}

function extractHuggingFaceDelta(payload: unknown): string | null {
  const root = (payload ?? {}) as Record<string, unknown>;
  const choices = root.choices as
    | Array<{ delta?: { content?: string }; message?: { content?: string } }>
    | undefined;
  const delta = choices?.[0]?.delta?.content ?? choices?.[0]?.message?.content;
  if (typeof delta === "string") return delta;
  return typeof root.response === "string" ? root.response : null;
}

async function workersAiStream(
  messages: ChatMessage[],
  opts: CallOptions,
  cfg: WorkersAiConfig,
): Promise<ReadableStream<Uint8Array>> {
  const response = await fetch(workersAiEndpoint(cfg), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(opts.timeoutMs ?? 90_000),
    body: JSON.stringify({
      messages,
      max_tokens: opts.maxTokens ?? 512,
      temperature: opts.temperature ?? 0.7,
      top_p: opts.topP ?? 0.9,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new AiProviderError(
      "workers-ai",
      response.status,
      `Workers AI error ${response.status}: ${errBody.slice(0, 200)}`,
    );
  }
  if (!response.body) {
    throw new AiProviderError("workers-ai", 502, "Workers AI returned no stream body");
  }
  return sseToAppStream(response.body, extractWorkersAiDelta);
}

async function huggingFaceStream(
  messages: ChatMessage[],
  opts: CallOptions,
  cfg: HuggingFaceConfig,
): Promise<ReadableStream<Uint8Array>> {
  const response = await fetch(`${HF_API_BASE}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
      Accept: "text/event-stream",
    },
    signal: AbortSignal.timeout(opts.timeoutMs ?? 90_000),
    body: JSON.stringify({
      model: cfg.model,
      messages,
      max_tokens: opts.maxTokens ?? 512,
      temperature: opts.temperature ?? 0.7,
      top_p: opts.topP ?? 0.9,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new AiProviderError(
      "huggingface",
      response.status,
      `HuggingFace error ${response.status}: ${errBody.slice(0, 200)}`,
      response.headers.get("retry-after") ?? undefined,
    );
  }
  if (!response.body) {
    throw new AiProviderError("huggingface", 502, "HuggingFace returned no stream body");
  }
  return sseToAppStream(response.body, extractHuggingFaceDelta);
}

/**
 * Streams the model with automatic provider fallback, normalising both
 * providers to the app's `{"chunk": "..."}` SSE contract.
 *
 * Order: Workers AI stream → HuggingFace stream → HuggingFace buffered
 * (simulated) → Workers AI buffered (simulated) → clear error.
 */
export async function streamModel(
  messages: ChatMessage[],
  opts: CallOptions = {},
): Promise<StreamResult> {
  const cfg = getAiConfig();

  if (cfg.workersAi) {
    try {
      const stream = await workersAiStream(messages, opts, cfg.workersAi);
      logServed(opts.label, "workers-ai", cfg.workersAi.model);
      return { provider: "workers-ai", stream };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn(`[ai] Workers AI stream failed, falling back: ${msg}`);
    }
  }

  if (cfg.huggingface) {
    try {
      const stream = await huggingFaceStream(messages, opts, cfg.huggingface);
      logServed(opts.label, "huggingface", cfg.huggingface.model);
      return { provider: "huggingface", stream };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn(`[ai] HuggingFace stream failed, falling back to buffered: ${msg}`);
    }

    // Buffered fallback — preserves the legacy simulated stream behaviour.
    const text = await callHuggingFace(messages, opts, cfg.huggingface);
    logServed(opts.label, "huggingface", cfg.huggingface.model);
    return { provider: "huggingface", stream: simulateTextStream(text) };
  }

  if (cfg.workersAi) {
    const text = await callWorkersAi(messages, opts, cfg.workersAi);
    logServed(opts.label, "workers-ai", cfg.workersAi.model);
    return { provider: "workers-ai", stream: simulateTextStream(text) };
  }

  throw new Error(
    "No AI provider configured — set CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_AI_TOKEN (Workers AI) or HUGGINGFACE_TOKEN",
  );
}
