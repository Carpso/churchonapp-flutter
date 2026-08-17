import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";

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

function buildGeminiPrompt(
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
Requirements:
- Every question must be factually accurate and based on Scripture
- 4 options per question, exactly ONE correct
- Include a real scripture reference (book chapter:verse) for each question
- Questions should be diverse — cover different books, themes, and difficulty levels
- Avoid trick questions or ambiguous wording
- Mix testaments: some Old Testament, some New Testament

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

async function callGeminiAPI(
  prompt: string,
  apiKey: string,
): Promise<QuizQuestion[]> {
  const response = await fetch(
    `${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.8,
          topP: 0.95,
          maxOutputTokens: 8192,
          responseMimeType: "application/json",
        },
      }),
    },
  );

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Gemini API error ${response.status}: ${errText}`);
  }

  const data = await response.json();
  const text =
    data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

  if (!text) {
    throw new Error("Gemini returned empty response");
  }

  // Parse the JSON array from the response
  const cleaned = text
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  let parsed: unknown[];
  try {
    parsed = JSON.parse(cleaned) as unknown[];
  } catch (_) {
    // Try to extract array from text
    const match = /\[[\s\S]*\]/.exec(cleaned);
    if (match) {
      parsed = JSON.parse(match[0]) as unknown[];
    } else {
      throw new Error("Could not parse Gemini response as JSON array");
    }
  }

  // Validate each question has required fields
  const valid: QuizQuestion[] = [];
  for (const item of parsed) {
    const q = item as Record<string, unknown>;
    if (
      typeof q.question === "string" &&
      Array.isArray(q.options) &&
      q.options.length === 4 &&
      typeof q.correct_answer === "number"
    ) {
      valid.push({
        question: q.question as string,
        options: q.options as string[],
        correct_answer: q.correct_answer as number,
        difficulty: (q.difficulty as string) || "Medium",
        category: (q.category as string) || "General",
        scripture_reference: (q.scripture_reference as string) || "",
      });
    }
  }

  return valid;
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

    // Call Gemini API
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return new Response(
        JSON.stringify({
          error: "GEMINI_API_KEY not configured on server",
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
    const prompt = buildGeminiPrompt(
      generateCount,
      category ?? undefined,
      difficulty ?? undefined,
      excludeQuestions,
      topic ?? undefined,
    );

    const questions = await callGeminiAPI(prompt, geminiKey);

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
