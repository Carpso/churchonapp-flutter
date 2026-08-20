import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// HuggingFace free-tier inference is the ONLY AI provider for quiz generation.
// Router endpoint is OpenAI-compatible and resolves from the Supabase edge
// runtime (api-inference.huggingface.co does not — verified via dns-probe).
// Default is Llama-3.1-8B-Instruct — verified reachable on this account's
// free tier via the router and strong at structured JSON output.
// NEVER add another AI provider here (Gemini removed 2026-08-20 per request).
const HF_API_BASE = "https://router.huggingface.co/v1";
const HF_MODEL = Deno.env.get("HF_MODEL_ID") ?? "meta-llama/Llama-3.1-8B-Instruct";

interface QuizQuestion {
  question: string;
  options: string[];
  correct_answer: number;
  difficulty: string;
  category: string;
  scripture_reference: string;
}

function generateQuestionHash(q: QuizQuestion): string {
  // Simple deterministic hash from question text (lowercase, trimmed)
  const normalized = q.question.toLowerCase().trim();
  let hash = 0;
  for (let i = 0; i < normalized.length; i++) {
    const char = normalized.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0; // Convert to 32-bit integer
  }
  return `ai_${Math.abs(hash).toString(16)}`;
}

const VALID_DIFFICULTIES = new Set(["Easy", "Medium", "Hard"]);

/**
 * Structural quality gate. Rejects questions that would produce wrong,
 * ambiguous, or leaked answers:
 *  - correct_answer must be an integer index within options
 *  - exactly 4 options, all non-empty and distinct (case-insensitive)
 *  - the correct option must not appear inside the question text
 *  - a scripture reference is mandatory
 */
function validateQuestion(raw: Record<string, unknown>): QuizQuestion | null {
  if (typeof raw.question !== "string") return null;
  if (!Array.isArray(raw.options)) return null;

  const question = raw.question.trim();
  if (question.length < 10) return null;

  const options = (raw.options as unknown[])
    .filter((o): o is string => typeof o === "string")
    .map((o) => o.trim());

  if (options.length !== 4) return null;
  if (options.some((o) => o.length === 0)) return null;

  // Distinct options (case-insensitive) — duplicates make answers ambiguous.
  const seen = new Set<string>();
  for (const o of options) {
    const key = o.toLowerCase();
    if (seen.has(key)) return null;
    seen.add(key);
  }

  const correct = raw.correct_answer;
  if (typeof correct !== "number" || !Number.isInteger(correct)) return null;
  if (correct < 0 || correct >= options.length) return null;

  const reference = (raw.scripture_reference as string | undefined) ?? "";
  if (!reference.trim()) return null;

  const correctText = options[correct].toLowerCase();
  // Answer leaking into the question is a strong signal of a bad question.
  if (question.toLowerCase().includes(correctText) && correctText.length > 3) {
    return null;
  }

  const difficulty = VALID_DIFFICULTIES.has(raw.difficulty as string)
    ? (raw.difficulty as string)
    : "Medium";

  return {
    question,
    options,
    correct_answer: correct,
    difficulty,
    category: ((raw.category as string | undefined) || "General").trim() || "General",
    scripture_reference: reference.trim(),
  };
}

function buildPrompt(
  count: number,
  category?: string,
  difficulty?: string,
  excludeQuestions?: string[],
  topic?: string,
): string {
  const catHint = category ? `Focus on the "${category}" category. ` : "";
  const diffHint = difficulty
    ? `Target difficulty: "${difficulty}". `
    : "Mix of Easy, Medium, and Hard questions. ";
  const topicHint = topic
    ? `Topic/theme: "${topic}". Generate questions about this specific topic. `
    : "";
  const excludeHint =
    excludeQuestions && excludeQuestions.length > 0
      ? `Do NOT repeat or closely resemble any of these questions: ${excludeQuestions.slice(0, 20).join("; ")}. `
      : "";

  return `You are a world-class Bible quiz content generator. Generate exactly ${count} multiple-choice Bible quiz questions for a competitive quiz app.

${catHint}${diffHint}${topicHint}${excludeHint}
ACCURACY RULES (non-negotiable):
- Every question must be factually accurate per the KJV Bible. When in doubt, only use facts you are certain of — never guess.
- The ${"`correct_answer`"} index MUST point to the option that exactly and uniquely answers the question. Double-check this mapping before answering.
- Scripture references MUST be real (book chapter:verse) and must actually support the answer.
- 4 options per question, exactly ONE correct; the other three must be plausible but clearly wrong.
- Options must all be different from each other (no duplicates, no near-identical wording).
- Never embed the answer (or a paraphrase of it) inside the question text.
- Avoid trick questions, ambiguous wording, and questions that depend on translation differences.
- If a question cannot be answered with certainty, do NOT include it — generate a different one instead.
- Mix testaments: some Old Testament, some New Testament.

Return ONLY a valid JSON array (no markdown, no code fences). Each item:
{
  "question": "Who built the ark?",
  "options": ["Noah", "Moses", "Abraham", "David"],
  "correct_answer": 0,
  "difficulty": "Easy",
  "category": "History",
  "scripture_reference": "Genesis 6:14"
}`;
}

/**
 * HuggingFace free-tier fallback generator. Small-batch loop because the
 * free inference API has tight max-token limits (a 1.5B model cannot emit
 * 100 valid questions in a single call). Each round requests `perCall`
 * questions; only structurally valid ones (validateQuestion) are kept.
 */
async function callHuggingFace(
  prompt: string,
  perCall: number,
  maxRounds: number,
): Promise<QuizQuestion[]> {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  if (!hfToken) throw new Error("HUGGINGFACE_TOKEN not configured");

  const systemMsg = `You are a Bible quiz question writer. Produce only factually accurate Bible questions with 4 options and exactly one correct answer index (0-3). Difficulty: Easy, Medium, or Hard. Categories: History, People, Scripture, New Testament, Miracles, Prophecy, Law, Language, Angels, General.`;

  const roundPrompt = `${prompt}

Return ${perCall} questions. Strictly output ONLY a valid JSON array (no markdown, no code fences), exactly this shape:
[{"question": "...", "options": ["A", "B", "C", "D"], "correct_answer": 0, "difficulty": "Easy", "category": "History", "scripture_reference": "Genesis 6:14"}]`;

  const collected: QuizQuestion[] = [];
  for (let round = 0; round < maxRounds; round++) {
    // Router is OpenAI-compatible; api-inference.huggingface.co does not
    // resolve from the Supabase edge runtime (verified via dns-probe).
    const requestBody = JSON.stringify({
      model: HF_MODEL,
      messages: [
        { role: "system", content: systemMsg },
        { role: "user", content: roundPrompt },
      ],
      max_tokens: 1024,
      temperature: 0.7,
      top_p: 0.9,
    });

    let hfResponse = await fetch(`${HF_API_BASE}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${hfToken}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(60_000),
      body: requestBody,
    });

    // Cold start: model is loading → wait for it
    if (hfResponse.status === 503) {
      hfResponse = await fetch(`${HF_API_BASE}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${hfToken}`,
          "Content-Type": "application/json",
        },
        signal: AbortSignal.timeout(90_000),
        body: requestBody,
      });
    }

    if (!hfResponse.ok) {
      const errBody = await hfResponse.text().catch(() => "");
      throw new Error(`HuggingFace error ${hfResponse.status}: ${errBody.slice(0, 200)}`);
    }

    const data = await hfResponse.json();
    const generatedText = (data as { choices?: Array<{ message?: { content?: string } }> })
      ?.choices?.[0]?.message?.content?.trim();
    if (!generatedText) {
      // A full round that yields no text is a model problem — bail.
      if (round > 0) break;
      continue;
    }

    const cleaned = generatedText
      .replace(/```json\s*/g, "")
      .replace(/```\s*/g, "")
      .replace(/<\|im_start\|>[\s\S]*?<\|im_end\|>/g, "")
      .replace(/<\|im_start\|>/g, "")
      .replace(/<\|im_end\|>/g, "")
      .trim();

    let parsed: unknown[] = [];
    try {
      parsed = JSON.parse(cleaned) as unknown[];
    } catch {
      const match = /\[[\s\S]*\]/.exec(cleaned);
      if (match) {
        try {
          parsed = JSON.parse(match[0]) as unknown[];
        } catch {
          parsed = [];
        }
      }
    }

    let validInRound = 0;
    for (const item of parsed) {
      const q = validateQuestion(item as Record<string, unknown>);
      if (q) {
        collected.push(q);
        validInRound++;
      }
    }

    // Early exit: two consecutive rounds yielding nothing valid → stop.
    if (validInRound === 0 && collected.length > 0) break;
  }

  return collected;
}

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Auth check
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization header" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  // Parse body early — the `auto` flag decides whether regular members may
  // trigger generation (client-side "pool running low" auto-refill).
  let body: {
    count?: number;
    category?: string | null;
    difficulty?: string | null;
    excludeQuestions?: string[];
    topic?: string | null;
    auto?: boolean;
  } = {};
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  const auto = body.auto === true;

  // Check role — privileged roles may generate on demand; regular members may
  // only auto-trigger (rate-limited below).
  const profile = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  const role = profile?.data?.role ?? "member";
  const isPrivileged =
    role === "superadmin" || role === "coa_employee" || role === "employee";

  if (!isPrivileged && !auto) {
    return new Response(JSON.stringify({ error: "Forbidden: superadmin/coa_employee only" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 403,
    });
  }

  try {
    const {
      count = 50,
      category = null,
      difficulty = null,
      excludeQuestions = [],
      topic = null,
    } = body;

    // Limit batch size
    const batchSize = Math.min(Math.max(1, count), 100);

    // ── Auto-trigger throttle (members only) ──────────────────────────────
    // 1. Pool must be under 200 questions (a genuinely low pool).
    // 2. At most 1 auto-batch per user every 15 minutes.
    if (auto && !isPrivileged) {
      const { count: poolCount } = await supabase
        .from("quiz_questions")
        .select("id", { count: "exact", head: true });
      const pool = poolCount ?? 0;
      if (pool >= 200) {
        return new Response(
          JSON.stringify({ success: true, inserted: 0, skipped: "pool_full" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        );
      }
      const { count: recentCount } = await supabase
        .from("quiz_generation_log")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .eq("source", "auto")
        .gte("created_at", new Date(Date.now() - 15 * 60 * 1000).toISOString());
      if ((recentCount ?? 0) >= 1) {
        return new Response(
          JSON.stringify({ success: true, inserted: 0, skipped: "rate_limited" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        );
      }
    }

    // Fetch existing question hashes for dedup
    const { data: existingQs } = await supabase
      .from("quiz_questions")
      .select("question_hash")
      .not("question_hash", "is", null);

    const existingHashes = new Set(
      (existingQs ?? []).map((q) => q.question_hash as string),
    );

    // HuggingFace free-tier inference is the ONLY AI provider.
    const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
    if (!hfToken) {
      return new Response(
        JSON.stringify({
          error: "HUGGINGFACE_TOKEN not configured on server",
          inserted: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate extra to account for dedup losses
    const generateCount = Math.min(batchSize * 2, 200);
    const prompt = buildPrompt(
      generateCount,
      category ?? undefined,
      difficulty ?? undefined,
      excludeQuestions,
      topic ?? undefined,
    );

    // HF free tier: one call for the whole batch (probe: 3 Qs ≈ 9s warm,
    // ~90s cold), capped at 8 per call; at most 3 rounds to stay within
    // the edge function wall-clock budget.
    const perCall = Math.min(batchSize, 8);
    const maxRounds = 3;
    const questions = await callHuggingFace(prompt, perCall, maxRounds);
    const provider = "huggingface";
    if (questions.length === 0) {
      return new Response(
        JSON.stringify({ error: "Question generation failed: no provider produced questions", inserted: 0 }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Insert questions with hash dedup
    let insertedCount = 0;
    const batchId = `batch_${Date.now()}`;

    for (const q of questions) {
      if (insertedCount >= batchSize) break; // Stop at requested count

      const hash = generateQuestionHash(q);

      // Skip if hash already exists
      if (existingHashes.has(hash)) continue;

      const { error } = await supabase.from("quiz_questions").insert({
        question: q.question,
        options: q.options,
        correct_answer: q.correct_answer,
        difficulty: q.difficulty,
        category: q.category,
        scripture_reference: q.scripture_reference,
        points:
          q.difficulty === "Hard"
            ? 30
            : q.difficulty === "Medium"
              ? 20
              : 10,
        style: "choice",
        is_superadmin_only: false,
        ai_generated: true,
        question_hash: hash,
        generator_batch_id: batchId,
      });

      if (!error) {
        existingHashes.add(hash);
        insertedCount++;
      }
    }

    // Audit + rate-limit log (service role).
    try {
      await supabase.from("quiz_generation_log").insert({
        user_id: user.id,
        batch_id: batchId,
        source: auto ? "auto" : "manual",
        inserted: insertedCount,
      });
    } catch (logErr) {
      console.error("quiz_generation_log insert failed:", logErr);
    }

    return new Response(
      JSON.stringify({
        success: true,
        inserted: insertedCount,
        total_generated: questions.length,
        batch_id: batchId,
        provider,
        category: category ?? "mixed",
        difficulty: difficulty ?? "mixed",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({
        error: e instanceof Error ? e.message : "Unknown error",
        inserted: 0,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
