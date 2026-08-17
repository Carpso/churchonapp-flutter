// quiz-import — bulk import Bible quiz questions from pasted text, .txt,
// .pdf, .doc/.docx files.
//
// Access (mirrors can_manage_quiz_content RPC):
//   - superadmin / coa_employee / employee
//   - any user whose church has leased the Quiz Engine
//     (coin_redemptions redemption_type = 'quiz_engine_lease')
//
// Contract (JSON POST):
//   { text: string }                            -> parse text directly
//   { fileName: string, dataBase64: string }    -> decode file, Gemini extracts
//   { questions: [...] }                        -> validated + inserted as-is
//
// Returns { inserted, skipped, total_generated, batch_id, errors[] }.

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
  const normalized = q.question.toLowerCase().trim();
  let hash = 0;
  for (let i = 0; i < normalized.length; i++) {
    const char = normalized.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return `ai_${Math.abs(hash).toString(16)}`;
}

function validateQuestion(item: Record<string, unknown>): QuizQuestion | null {
  if (
    typeof item.question !== "string" ||
    item.question.trim().length < 5 ||
    !Array.isArray(item.options) ||
    item.options.length !== 4 ||
    typeof item.correct_answer !== "number" ||
    item.correct_answer < 0 ||
    item.correct_answer > 3
  ) {
    return null;
  }
  const opts = item.options.map((o) => String(o).trim());
  if (opts.some((o) => o.length === 0)) return null;
  return {
    question: item.question.trim(),
    options: opts,
    correct_answer: item.correct_answer,
    difficulty: ["Easy", "Medium", "Hard"].includes(String(item.difficulty))
      ? String(item.difficulty)
      : "Medium",
    category: typeof item.category === "string" && item.category.trim()
      ? item.category.trim()
      : "General",
    scripture_reference:
      typeof item.scripture_reference === "string"
        ? item.scripture_reference.trim()
        : "",
  };
}

function buildExtractionPrompt(text: string, fileName?: string): string {
  return `You are a Bible quiz content extractor. Extract every multiple-choice question from the ${fileName ? `document "${fileName}"` : "text"} below.

Rules:
- Produce a separate question for each quiz question found (dedupe repeats).
- Exactly 4 options per question, exactly ONE correct.
- Add a real scripture reference (book chapter:verse) when the document gives one or you can infer it confidently.
- Difficulty: Easy / Medium / Hard. Category: short label (People, History, NT, OT, Miracles, Prophecy, Law, Language, Scripture...).
- Skip anything that is not a quiz question (headers, instructions, answers without questions).

Return ONLY a valid JSON array (no markdown, no code fences). Each item:
{
  "question": "...",
  "options": ["...", "...", "...", "..."],
  "correct_answer": 0,
  "difficulty": "Easy",
  "category": "History",
  "scripture_reference": "Genesis 6:14"
}

DOCUMENT TEXT:
"""${text.slice(0, 120000)}"""`;
}

async function callGeminiExtraction(
  apiKey: string,
  prompt: string,
  fileData?: { mimeType: string; data: string },
): Promise<QuizQuestion[]> {
  const parts: Record<string, unknown>[] = [{ text: prompt }];
  if (fileData) {
    parts.push({ inline_data: fileData });
  }
  const response = await fetch(
    `${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: {
          temperature: 0.4,
          topP: 0.95,
          maxOutputTokens: 16384,
          responseMimeType: "application/json",
        },
      }),
    },
  );

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Gemini API error ${response.status}: ${errText.slice(0, 500)}`);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text) throw new Error("Gemini returned empty response");

  const cleaned = text
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  let parsed: unknown[];
  try {
    parsed = JSON.parse(cleaned) as unknown[];
  } catch {
    const match = /\[[\s\S]*\]/.exec(cleaned);
    if (!match) throw new Error("Could not parse Gemini response as JSON array");
    parsed = JSON.parse(match[0]) as unknown[];
  }

  const valid: QuizQuestion[] = [];
  for (const item of parsed) {
    const q = validateQuestion(item as Record<string, unknown>);
    if (q) valid.push(q);
  }
  return valid;
}

async function canManage(supabase: any, userId: string): Promise<boolean> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("role, tenant_id")
    .eq("id", userId)
    .maybeSingle();
  const role = profile?.role ?? "member";
  if (["superadmin", "coa_employee", "employee"].includes(role)) return true;
  if (!profile?.tenant_id) return false;

  const { data: leased } = await supabase
    .from("coin_redemptions")
    .select("id, user_id, profiles(tenant_id)")
    .eq("redemption_type", "quiz_engine_lease")
    .eq("profiles.tenant_id", profile.tenant_id)
    .limit(1);
  return (leased ?? []).length > 0;
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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  if (!(await canManage(supabase, user.id))) {
    return new Response(
      JSON.stringify({
        error: "Forbidden: superadmin/coa_employee/employee or a Quiz Engine leasing church required",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 403 },
    );
  }

  try {
    const body = await req.json();
    const { text, fileName, dataBase64, questions: providedQuestions } = body as {
      text?: string;
      fileName?: string;
      dataBase64?: string;
      questions?: unknown[];
    };

    let parsed: QuizQuestion[] = [];

    if (Array.isArray(providedQuestions)) {
      // Client already parsed -> validate + insert.
      for (const item of providedQuestions) {
        const q = validateQuestion(item as Record<string, unknown>);
        if (q) parsed.push(q);
      }
    } else if (typeof text === "string" && text.trim().length > 0) {
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (!geminiKey) {
        return new Response(
          JSON.stringify({ error: "GEMINI_API_KEY not configured on server", inserted: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
        );
      }
      parsed = await callGeminiExtraction(geminiKey, buildExtractionPrompt(text));
    } else if (typeof dataBase64 === "string" && typeof fileName === "string") {
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (!geminiKey) {
        return new Response(
          JSON.stringify({ error: "GEMINI_API_KEY not configured on server", inserted: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
        );
      }
      const ext = fileName.toLowerCase().split(".").pop() ?? "";
      const mime =
        ext === "pdf" ? "application/pdf"
        : ext === "doc" ? "application/msword"
        : ext === "docx" ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        : "text/plain";
      parsed = await callGeminiExtraction(
        geminiKey,
        buildExtractionPrompt("", fileName),
        { mimeType: mime, data: dataBase64 },
      );
    } else {
      return new Response(
        JSON.stringify({ error: "Provide text, fileName+dataBase64, or questions" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
      );
    }

    if (parsed.length === 0) {
      return new Response(
        JSON.stringify({ inserted: 0, skipped: 0, total_generated: 0, errors: ["No valid questions found"] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // Dedup against existing hashes.
    const { data: existingQs } = await supabase
      .from("quiz_questions")
      .select("question_hash")
      .not("question_hash", "is", null);
    const existingHashes = new Set(
      (existingQs ?? []).map((q) => q.question_hash as string),
    );

    let insertedCount = 0;
    const skipped: string[] = [];
    const errors: string[] = [];
    const batchId = `import_${Date.now()}`;

    for (const q of parsed) {
      const hash = generateQuestionHash(q);
      if (existingHashes.has(hash)) {
        skipped.push(q.question.slice(0, 60));
        continue;
      }
      const { error } = await supabase.from("quiz_questions").insert({
        question: q.question,
        options: q.options,
        correct_answer: q.correct_answer,
        difficulty: q.difficulty,
        category: q.category,
        scripture_reference: q.scripture_reference,
        points:
          q.difficulty === "Hard" ? 30
          : q.difficulty === "Medium" ? 20
          : 10,
        style: "choice",
        is_superadmin_only: false,
        ai_generated: true,
        question_hash: hash,
        generator_batch_id: batchId,
      });
      if (error) {
        errors.push(error.message);
      } else {
        existingHashes.add(hash);
        insertedCount++;
      }
    }

    try {
      await supabase.from("quiz_generation_log").insert({
        user_id: user.id,
        batch_id: batchId,
        source: "import",
        inserted: insertedCount,
      });
    } catch (logErr) {
      console.error("quiz_generation_log insert failed:", logErr);
    }

    return new Response(
      JSON.stringify({
        inserted: insertedCount,
        skipped: skipped.length,
        total_generated: parsed.length,
        batch_id: batchId,
        errors: errors.slice(0, 20),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error", inserted: 0 }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});