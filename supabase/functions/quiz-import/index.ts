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
//   { fileName: string, dataBase64: string }    -> decode file, HF extracts
//   { questions: [...] }                        -> validated + inserted as-is
//
// Returns { inserted, skipped, total_generated, batch_id, errors[] }.
//
// AI provider: HuggingFace free-tier inference ONLY (router endpoint, OpenAI
// compatible). NEVER add another provider (Gemini removed 2026-08-20).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

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
  const normalized = q.question.toLowerCase().trim();
  let hash = 0;
  for (let i = 0; i < normalized.length; i++) {
    const char = normalized.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return `ai_${Math.abs(hash).toString(16)}`;
}

const VALID_DIFFICULTIES = new Set(["Easy", "Medium", "Hard"]);

function validateQuestion(item: Record<string, unknown>): QuizQuestion | null {
  if (typeof item.question !== "string") return null;
  if (!Array.isArray(item.options)) return null;

  const question = item.question.trim();
  if (question.length < 10) return null;

  const opts = item.options.map((o) => String(o).trim());
  if (opts.length !== 4) return null;
  if (opts.some((o) => o.length === 0)) return null;

  const seen = new Set<string>();
  for (const o of opts) {
    const key = o.toLowerCase();
    if (seen.has(key)) return null;
    seen.add(key);
  }

  const correct = item.correct_answer;
  if (typeof correct !== "number" || !Number.isInteger(correct)) return null;
  if (correct < 0 || correct >= opts.length) return null;

  const reference =
    typeof item.scripture_reference === "string" ? item.scripture_reference.trim() : "";
  if (!reference) return null;

  const correctText = opts[correct].toLowerCase();
  if (question.toLowerCase().includes(correctText) && correctText.length > 3) {
    return null;
  }

  return {
    question,
    options: opts,
    correct_answer: correct,
    difficulty: VALID_DIFFICULTIES.has(String(item.difficulty))
      ? String(item.difficulty)
      : "Medium",
    category: typeof item.category === "string" && item.category.trim()
      ? item.category.trim()
      : "General",
    scripture_reference: reference,
  };
}

function decodeXmlEntities(s: string): string {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&");
}

/**
 * Best-effort text extraction from a BINARY document.
 *
 * Uses runtime dynamic imports so a library/network failure only disables
 * binary parsing — it can never break the plain-text path.
 *   - PDF  -> `unpdf` (serverless pdf.js build)
 *   - DOCX -> `fflate` unzip + strip `word/document.xml`
 *   - DOC  -> naive printable-run scan (legacy OLE, best-effort)
 */
async function extractTextFromBinary(
  bytes: Uint8Array,
  fileName: string,
): Promise<string | null> {
  const ext = (fileName.split(".").pop() ?? "").toLowerCase();

  try {
    if (ext === "pdf") {
      const unpdf = await import("https://esm.sh/unpdf@0.12.1");
      const pdf = await unpdf.getDocumentProxy(bytes);
      const { text } = await unpdf.extractText(pdf, { mergePages: true });
      const joined = Array.isArray(text) ? text.join("\n") : String(text ?? "");
      return joined.trim().length > 0 ? joined : null;
    }

    if (ext === "docx") {
      const { unzipSync, strFromU8 } = await import(
        "https://esm.sh/fflate@0.8.2"
      );
      const files = unzipSync(bytes);
      const doc = files["word/document.xml"];
      if (!doc) return null;
      const xml = strFromU8(doc)
        .replace(/<\/w:p>/g, "\n")
        .replace(/<w:br[^>]*\/>/g, "\n")
        .replace(/<w:tab[^>]*\/>/g, "\t");
      const stripped = decodeXmlEntities(xml.replace(/<[^>]+>/g, ""));
      return stripped.trim().length > 0 ? stripped : null;
    }

    if (ext === "doc") {
      // Legacy OLE .doc — pull the printable ASCII runs. Lossy, but recovers
      // most question text without any native dependency.
      const raw = new TextDecoder("latin1").decode(bytes);
      const runs = raw.match(/[\x20-\x7E]{4,}/g) ?? [];
      const text = runs.join("\n");
      return text.trim().length > 120 ? text : null;
    }
  } catch (e) {
    console.error(`[quiz-import] binary extraction failed for .${ext}:`, e);
    return null;
  }

  return null;
}

function buildExtractionPrompt(text: string, fileName?: string): string {
  return `You are a Bible quiz content extractor. Extract every multiple-choice question from the ${fileName ? `document "${fileName}"` : "text"} below.

Rules:
- Produce a separate question for each quiz question found (dedupe repeats).
- Exactly 4 options per question, exactly ONE correct.
- The correct_answer index MUST point at the option that exactly answers the question — verify the mapping.
- Options must be distinct from each other; never duplicate an option.
- Add a real scripture reference (book chapter:verse) when the document gives one or you can infer it confidently.
- Difficulty: Easy / Medium / Hard. Category: short label (People, History, NT, OT, Miracles, Prophecy, Law, Language, Scripture...).
- Skip anything that is not a quiz question (headers, instructions, answers without questions).
- If a question's answer is uncertain or ambiguous, skip it — accuracy matters more than quantity.

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

async function callHuggingFaceExtraction(
  prompt: string,
): Promise<QuizQuestion[]> {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  if (!hfToken) throw new Error("HUGGINGFACE_TOKEN not configured");

  const requestBody = JSON.stringify({
    model: HF_MODEL,
    messages: [
      {
        role: "system",
        content:
          "You are a Bible quiz content extractor. Extract multiple-choice questions as a strict JSON array. Accuracy matters more than quantity.",
      },
      { role: "user", content: prompt },
    ],
    max_tokens: 2048,
    temperature: 0.4,
    top_p: 0.9,
  });

  let response = await fetch(`${HF_API_BASE}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${hfToken}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(60_000),
    body: requestBody,
  });

  // Cold start: model is loading → wait for it
  if (response.status === 503) {
    response = await fetch(`${HF_API_BASE}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${hfToken}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(120_000),
      body: requestBody,
    });
  }

  if (!response.ok) {
    const errBody = await response.text().catch(() => "");
    throw new Error(`HuggingFace error ${response.status}: ${errBody.slice(0, 300)}`);
  }

  const data = await response.json();
  const text = (data as { choices?: Array<{ message?: { content?: string } }> })
    ?.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error("HuggingFace returned empty response");

  const cleaned = text
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  let parsed: unknown[];
  try {
    parsed = JSON.parse(cleaned) as unknown[];
  } catch {
    const match = /\[[\s\S]*\]/.exec(cleaned);
    if (!match) throw new Error("Could not parse HuggingFace response as JSON array");
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
    const { text, fileName, dataBase64, questions: providedQuestions, setId, sourceFileUrl, sourceFileName, sourceFileType } = body as {
      text?: string;
      fileName?: string;
      dataBase64?: string;
      questions?: unknown[];
      setId?: string;
      sourceFileUrl?: string;
      sourceFileName?: string;
      sourceFileType?: string;
    };

    let parsed: QuizQuestion[] = [];

    if (Array.isArray(providedQuestions)) {
      for (const item of providedQuestions) {
        const q = validateQuestion(item as Record<string, unknown>);
        if (q) parsed.push(q);
      }
    } else if (typeof text === "string" && text.trim().length > 0) {
      parsed = await callHuggingFaceExtraction(buildExtractionPrompt(text));
    } else if (typeof dataBase64 === "string" && typeof fileName === "string") {
      // Decode the uploaded file. Plain-text formats are read directly; PDF /
      // DOCX / DOC go through binary extraction (best-effort, no native deps).
      let bytes: Uint8Array;
      try {
        bytes = Uint8Array.from(atob(dataBase64), (c) => c.charCodeAt(0));
      } catch (_) {
        return new Response(
          JSON.stringify({
            inserted: 0,
            skipped: 0,
            total_generated: 0,
            errors: ["Could not decode the uploaded file. Please try again or paste the questions as text."],
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        );
      }

      const ext = (fileName.split(".").pop() ?? "").toLowerCase();
      const isBinary = ext === "pdf" || ext === "docx" || ext === "doc";

      let fileText = "";
      if (isBinary) {
        fileText = (await extractTextFromBinary(bytes, fileName)) ?? "";
      } else {
        try {
          fileText = new TextDecoder().decode(bytes);
        } catch (_) {
          fileText = "";
        }
      }

      if (!fileText.trim()) {
        return new Response(
          JSON.stringify({
            inserted: 0,
            skipped: 0,
            total_generated: 0,
            errors: [
              isBinary
                ? `Could not read text from "${fileName}". If the document is a scanned/image PDF, paste the questions as text instead.`
                : "The file contained no readable text. Please paste the questions as text instead.",
            ],
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        );
      }
      parsed = await callHuggingFaceExtraction(buildExtractionPrompt(fileText, fileName));
    } else {
      return new Response(
        JSON.stringify({ error: "Provide text, fileName+dataBase64, or questions" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
      );
    }

    if (parsed.length === 0) {
      // If importing into a hosting set, surface the failure on the set row so
      // the host console can show why extraction produced nothing.
      if (setId) {
        await supabase
          .from("quiz_question_sets")
          .update({ extract_status: "failed", extract_error: "No valid questions found" })
          .eq("id", setId);
      }
      return new Response(
        JSON.stringify({ inserted: 0, skipped: 0, total_generated: 0, errors: ["No valid questions found"] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // ── HOSTING PIPELINE: write into quiz_set_questions ─────────────────────
    // The church-hosted tournament flow stores questions in `quiz_set_questions`
    // (NOT the legacy `quiz_questions` bank). The caller passes the set id
    // created by `create_quiz_set()`.
    if (setId) {
      const { data: setRow } = await supabase
        .from("quiz_question_sets")
        .select("id, tenant_id, extracted_count")
        .eq("id", setId)
        .maybeSingle();
      if (!setRow) {
        return new Response(
          JSON.stringify({ error: "Question set not found", inserted: 0 }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 },
        );
      }

      await supabase
        .from("quiz_question_sets")
        .update({
          extract_status: "processing",
          extract_error: null,
          ...(sourceFileUrl ? { source_file_url: sourceFileUrl } : {}),
          ...(sourceFileName ? { source_file_name: sourceFileName } : {}),
          ...(sourceFileType ? { source_file_type: sourceFileType } : {}),
        })
        .eq("id", setId);

      const { data: existingRows } = await supabase
        .from("quiz_set_questions")
        .select("prompt")
        .eq("set_id", setId);
      const seenPrompts = new Set(
        (existingRows ?? []).map((r) => String(r.prompt ?? "").toLowerCase().trim()),
      );

      let setInserted = 0;
      const setErrors: string[] = [];
      for (const q of parsed) {
        const prompt = q.question.trim();
        const key = prompt.toLowerCase();
        if (seenPrompts.has(key)) continue;
        const { error } = await supabase.from("quiz_set_questions").insert({
          set_id: setId,
          tenant_id: setRow.tenant_id,
          verse_reference: q.scripture_reference,
          category: q.category,
          difficulty: q.difficulty,
          prompt,
          options: q.options,
          correct_answers: [q.options[q.correct_answer]],
          points: q.difficulty === "Hard" ? 30 : q.difficulty === "Medium" ? 20 : 10,
          is_study_visible: true,
        });
        if (error) {
          setErrors.push(error.message);
        } else {
          seenPrompts.add(key);
          setInserted++;
        }
      }

      await supabase
        .from("quiz_question_sets")
        .update({
          extract_status: setInserted > 0 || seenPrompts.size > 0 ? "ready" : "failed",
          extracted_count: seenPrompts.size,
          extract_error: setErrors.length ? setErrors.slice(0, 3).join("; ").slice(0, 300) : null,
        })
        .eq("id", setId);

      return new Response(
        JSON.stringify({
          inserted: setInserted,
          skipped: parsed.length - setInserted,
          total_generated: parsed.length,
          set_id: setId,
          errors: setErrors.slice(0, 20),
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

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
