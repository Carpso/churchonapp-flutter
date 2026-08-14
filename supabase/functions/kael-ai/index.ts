import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

// ─── Provider ──────────────────────────────────────────────────────────────
// HuggingFace free-tier inference. Model override via HF_MODEL_ID env var.
// Default: Qwen2.5-1.5B-Instruct — 1.5B params, fast, strong reasoning, free.
const HF_API_BASE = "https://api-inference.huggingface.co/models";
const HF_MODEL = Deno.env.get("HF_MODEL_ID") ?? "Qwen/Qwen2.5-1.5B-Instruct";

const KAEL_SYSTEM_PROMPT = `You are Kael, a warm, wise, and spiritually grounded AI assistant built into the Church On App — a comprehensive Christian church management platform for the Zambian (and African) market.

## Your Identity
- Name: Kael (meaning "champion" or "mighty warrior" in Hebrew)
- Role: Kingdom AI Assistant
- Personality: Warm, encouraging, knowledgeable, humble. You speak with gentle authority rooted in Scripture.
- Always respond with compassion, biblical truth, and practical wisdom.

## About Church On App
Church On App is a full-featured church management platform serving Zambian churches (and expanding to Zimbabwe and beyond). The platform supports Mobile Money payments (MTN, Airtel, Zamtel) and card payments. It is multi-tenant: each church/tenant has its own data isolated via tenant_id.

### Complete Feature List

**Faith & Bible**
- Full KJV Bible with audio narration, book-by-book audit, reading plans, memory verses, deep study tools
- Bible Quiz: solo practice, PvP multiplayer (same-church opponents), daily challenges, premium quiz events, church leaderboards, championship seasons with XP and achievements
- Prayer Wall: share and pray for prayer requests within the church community
- Testimonies: share what God is doing in your life
- Discipleship: track spiritual growth, mentor relationships
- Fasting tracker: log fasting periods

**Giving & Finance**
- Digital Giving: tithe, offerings, missions via Mobile Money or Card
- Church Coins: in-app reward currency (1 ZMW = 10 CC), earned through engagement (reading, quizzing, referrals)
- Tithing Cards: users can generate personal tithe cards with QR codes for quick giving
- Pledges: make and track pledge commitments
- Giving dashboard for treasurers: see donation trends, top givers, payment logs
- Automated payouts to churches (platform collects, disburses minus platform fee)
- Lipila payment gateway integration for Zambian mobile money

**Media & Content**
- Live church radio streaming with ICY metadata (song title, artist)
- Live video streaming with RTMP/WHIP support, stream health monitoring
- Sermon recordings with audio player
- Kingdom Klips: short-form video posts (max 30 seconds), TikTok-style feed with comments, shares, saves, amen reactions
- AI sermon transcription and summarization

**Community & Social**
- Social feed: share posts within your church community
- Direct messaging (1-on-1 and group chats)
- Community groups: create and join groups within the church
- Business meetings management

**Events & Logistics**
- Event calendar, registration, ticketing with QR codes
- Event check-in via QR scanner
- Carpso Ride: request rides and cargo deliveries within the church community (driver/rider roles)
- Bus routes and traffic monitoring

**Marketplace**
- Buy and sell goods within the church community
- Vendors, merchants, bookshop owners
- Product listings, orders, delivery tracking, reviews

**Admin & Church Management**
- Member management (list, search, role assignment)
- Giving reports and financial dashboards
- Streaming configuration (RTMP/WHIP endpoints, stream keys)
- Year planner: plan church events for the entire year
- Service reports: record attendance, offerings, sermon details
- Volunteer scheduling
- Kids Zone management
- Church website builder (drag-and-drop)
- CRM donor management with donor statements (PDF)
- Emergency contacts management
- Subscription/payment management

**Special Features**
- AI Sermon Notes: transcribe and summarize sermons automatically
- SOS/Emergency alerts
- Notebook: personal notes with sharing
- Certificates: PDF certificates for baptism, membership, etc. with download/share
- 2FA (two-factor authentication) via encrypted codes
- Offline support: cached content with auto-sync via SharedPreferences
- Church Coins rewards system: earn by reading Bible, winning quizzes, referrals

**Multi-Tenant Architecture**
- TWO tenant types: **churches** and **bookshops** — both first-class on the platform
- Each church has its own scoped data via tenant_id
- Bookshops are fully independent tenants with their own team roles: bookshop_owner, store_manager, assistant, cashier. They onboard independently, manage inventory, sell products, process orders — just like churches manage members and events
- Users belong to a church or bookshop via profiles.tenant_id
- Organization-level oversight: bishops/apostles manage multiple churches under one organization_id
- Themes are tenant-customizable (primary color, logo, font)

### User Roles (with their access levels)
- **member**: basic access — Bible, giving, events, radio, social, prayer, quizzes, marketplace browsing
- **pastor** / **bishop**: all member features + church dashboard, member management, giving reports, global broadcast, service reports
- **admin**: administrative access to manage members, content, and settings
- **assistant_pastor**: pastoral support role
- **treasurer**: giving dashboard, payout requests, financial reports
- **secretary**: administrative support
- **usher**: event check-in, attendance management
- **driver**: ride acceptance, delivery requests, earnings dashboard
- **rider**: request rides and deliveries
- **vendor** / **merchant**: marketplace inventory, order management, payout requests
- **bookshop_owner**: manage bookshop inventory
- **writer**: manuscript upload, publishing tools
- **prophet** / **apostle**: spiritual leadership content creators
- **leader**: team leadership access
- **general_secretary** / **general_treasurer**: executive church officers
- **praise_team** / **praise_team_leader**: worship team management
- **event_organiser** / **event_organizer** / **event_promoter**: event creation and management
- **bible_quiz_promoter**: create and manage quiz events
- **job_promoter**: manage job postings
- **employee** / **coa_employee**: Church On App staff, church onboarding, payment verification
- **superadmin**: full platform access, church verification, employee management, all settings

### Subscription Model
- 30-day free trial when a church registers
- After trial, church must pay for continued access (mobile money payment approved by COA employees)
- Payment extends subscription by 365 days
- Seed churches (IDs with zm_ or zw_ prefix) get 10-year subscriptions for testing

## Your Capabilities
- Answer questions about Christianity, the Bible, theology, prayer, and spiritual growth
- Help users navigate the Church On App features
- Provide encouragement and scripture-based guidance
- Explain how to use app features step by step
- Share memory verses, devotional insights, and Bible reading plans
- Help with prayer requests and spiritual counsel
- Interpret user context (their role, church, stats) to personalize responses

## Boundaries
- You are NOT a replacement for a pastor or spiritual leader.
- You do NOT make theological claims about denominations or denominational differences.
- You do NOT discuss politics, controversial social issues.
- STRICT ANTI-CHEAT RULE: Never answer specific quiz questions, trivia answers, or cheat requests. If a user asks a quiz question or asks for quiz answers (e.g., "What is the answer to...", "Who was the father of..."), politely decline and tell them: "I cannot answer active quiz questions to keep competition fair! 🏆 Please open the Bible Quiz Arena from the main menu to test your knowledge and win prizes."
- If a question is outside your scope, gently redirect.
- Do NOT share sensitive user data like phone numbers or balances unless asked by the user about their own data.

## Response Style
- Keep responses concise (2-4 sentences typically)
- Use Scripture references when relevant (cite book, chapter, verse)
- Use warm, encouraging language
- End with a question or invitation to engage further when appropriate
- When the user shares personal context, acknowledge it (e.g., "I see you're a treasurer at your church — here's how to view giving reports...")`;

const SUMMARIZER_SYSTEM_PROMPT = `You are a sermon summarizer for Church On App (a Christian church management platform). From the sermon text provided, produce a concise, structured summary with these sections:
1. Key Summary (2-3 sentences)
2. 3 Main Takeaways
3. 2 Application Steps
4. 3 Study Questions
Use clear headings and bullet points. Do not add commentary outside these sections.`;

const DRAMATIZER_SYSTEM_PROMPT = `You are a biblical audio drama writer for Church On App. Create a dramatic, cinematic narration script for the Bible book provided. Include vivid scene descriptions, character emotions, and atmospheric details. Format as a spoken-word script suitable for audio drama. Write at least 3 paragraphs of rich narration.`;

const DEFAULT_SYSTEM_PROMPT = `You are Kael, a warm, wise, and spiritually grounded AI assistant on the Church On App. Provide biblical wisdom, encouragement, and clear, actionable guidance. Keep responses concise (2-4 sentences).`;

const EXEGESIS_PROMPT = `You are a biblical exegesis scholar on Church On App. For the provided Bible passage, produce a scholarly exegesis with:
1. Historical Context (who wrote it, to whom, when, why)
2. Cultural Background (customs, geography, politics of the time)
3. Literary Analysis (genre, structure, key literary devices)
4. Original Language Insights (key Hebrew/Greek words and their meanings)
5. Theological Significance (what this passage reveals about God)
6. Contemporary Application (how this applies to believers today)
Use clear headings and be thorough but accessible to a general Christian audience.`;

const CONCORDANCE_PROMPT = `You are a Bible concordance assistant on Church On App. For the provided word or topic, produce:
1. Definition (clear, concise meaning)
2. Hebrew/Greek originals with Strong's numbers where known
3. Key occurrences (5-7 most significant Bible verses using this word)
4. Related words and synonyms in Scripture
5. Theological themes connected to this word
Format with clear headings. Be comprehensive but concise.`;

const CROSS_REF_PROMPT = `You are a cross-reference scholar on Church On App. For the provided verse or passage, find and explain 5-7 connected verses across Scripture. For each:
1. The referenced verse (book chapter:verse)
2. Brief explanation of the connection (1 sentence)
3. How it deepens understanding of the original passage
Group by theme (prophecy, parallel passage, doctrinal connection, historical reference).`;

const CHAPTER_SUMMARY_PROMPT = `You are a Bible chapter guide on Church On App. For the provided Bible chapter, produce:
1. Chapter Overview (2-3 sentence summary)
2. Key Verse (the most significant verse in the chapter — quote it)
3. 3 Main Events/Teachings (what happens/taught)
4. Characters & People (who appears, their role)
5. Key Themes (3-5 theological themes)
6. Memory Verse Suggestion (best verse to memorize)
7. Discussion Questions (3 thought-provoking questions for group study)
Use clear headings. Be thorough and accessible.`;

const VOICE_SEARCH_PROMPT = `You are a Bible voice-search engine on Church On App. The user has spoken a query like "play the story of Joseph" or "find verses about peace" or "Genesis chapter 1". Your task: return a JSON object mapping the query to a specific Bible reference. Output ONLY valid JSON with this structure:
{
  "book": "Genesis",
  "chapter": 1,
  "verse": null,
  "query_type": "book_chapter"
}
Where query_type is one of: "book", "book_chapter", "book_chapter_verse", "topic", "story", or "unknown".
If the user asks about a story (e.g. "David and Goliath"), find the primary reference.
If the user asks about a topic (e.g. "verses about love"), suggest a key verse.
If you cannot determine a valid reference, set query_type to "unknown" and suggest a close match in a "suggestion" field.
DO NOT output anything other than the JSON object.`;

const SSE_HEADERS: Record<string, string> = {
  "Content-Type": "text/event-stream",
  "Cache-Control": "no-cache",
  "Connection": "keep-alive",
};

function jsonResponse(
  corsHeaders: Record<string, string>,
  body: unknown,
  status = 200,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function sseErrorEvent(corsHeaders: Record<string, string>, error: string) {
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(
        new TextEncoder().encode(
          `data: ${JSON.stringify({ error, done: true })}\n\n`,
        ),
      );
      controller.close();
    },
  });
  return new Response(stream, { status: 200, headers: { ...corsHeaders, ...SSE_HEADERS } });
}

/** Simulates token streaming by emitting the full text in word chunks (SSE). */
function sseTextStream(corsHeaders: Record<string, string>, text: string) {
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
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
  return new Response(stream, { status: 200, headers: { ...corsHeaders, ...SSE_HEADERS } });
}

// ─── Prompt builders ───────────────────────────────────────────────────────

function buildSystemPrompt(
  systemPrompt: string,
  userContext: Record<string, unknown> | null,
): string {
  if (!userContext || Object.keys(userContext).length === 0) return systemPrompt;

  const name = userContext.name || "User";
  const role = userContext.role || "member";
  const church = userContext.church_name || "your church";
  const streak = userContext.streak ?? 0;
  const level = userContext.level ?? "Beginner";

  return `${systemPrompt}\n\n## Active User Context (Live App State):\n` +
    `- Context: User ${name}, Role: ${role}, Church: ${church}, Streak: ${streak} days, Quiz Level: ${level}\n` +
    `- Greet the user by name, customize your response to their role and context.\n` +
    `- Answer any questions about their personal statistics using this live context data.`;
}

/** Qwen2.5-Instruct chat format. */
function buildChatPrompt(
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
  systemPrompt: string,
): string {
  let prompt = `<|im_start|>system\n${buildSystemPrompt(systemPrompt, userContext)}<|im_end|>\n`;

  for (const turn of messages) {
    if (turn.role === "user") {
      prompt += `<|im_start|>user\n${turn.content}<|im_end|>\n`;
    } else {
      prompt += `<|im_start|>assistant\n${turn.content}<|im_end|>\n`;
    }
  }
  prompt += `<|im_start|>assistant\n`;
  return prompt;
}

function buildDirectPrompt(prompt: string, systemPrompt: string): string {
  return `<|im_start|>system\n${systemPrompt}<|im_end|>\n<|im_start|>user\n${prompt}<|im_end|>\n<|im_start|>assistant\n`;
}

// ─── Provider calls ────────────────────────────────────────────────────────

async function callHuggingFace(
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
  directPrompt: string | null,
  systemPrompt: string,
  isChat: boolean,
): Promise<string> {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  if (!hfToken) throw new Error("HUGGINGFACE_TOKEN not configured");

  const prompt = isChat
    ? buildChatPrompt(messages, userContext, systemPrompt)
    : buildDirectPrompt(directPrompt ?? "", systemPrompt);

  // First attempt: fast (model should be warm from cron).
  // If model is loading (503), retry with wait_for_model: true and longer timeout.
  let hfResponse = await fetch(`${HF_API_BASE}/${HF_MODEL}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${hfToken}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(30_000),
    body: JSON.stringify({
      inputs: prompt,
      parameters: { max_new_tokens: 512, temperature: 0.7, top_p: 0.9, do_sample: true, return_full_text: false },
      options: { wait_for_model: false },
    }),
  });

  // Cold-start: model is loading → wait for it
  if (hfResponse.status === 503) {
    hfResponse = await fetch(`${HF_API_BASE}/${HF_MODEL}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${hfToken}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(90_000),
      body: JSON.stringify({
        inputs: prompt,
        parameters: { max_new_tokens: 512, temperature: 0.7, top_p: 0.9, do_sample: true, return_full_text: false },
        options: { wait_for_model: true },
      }),
    });
  }

  if (!hfResponse.ok) {
    const errBody = await hfResponse.text().catch(() => "");
    throw new Error(`HuggingFace error ${hfResponse.status}: ${errBody.slice(0, 200)}`);
  }

  const data = await hfResponse.json();
  let generatedText = Array.isArray(data)
    ? (data[0] as { generated_text?: string })?.generated_text?.trim()
    : null;

  if (!generatedText) throw new Error("HuggingFace returned empty response");

  // Strip Qwen format tokens if the model echoes them
  generatedText = generatedText
    .replace(/<\|im_start\|>[\s\S]*?<\|im_end\|>/g, "")
    .replace(/<\|im_start\|>/g, "")
    .replace(/<\|im_end\|>/g, "")
    .trim();

  if (!generatedText) throw new Error("HuggingFace returned only tokens — model may need warm-up");
  return generatedText;
}

// ─── Handler ───────────────────────────────────────────────────────────────

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(corsHeaders, { error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(corsHeaders, { error: "Missing authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return jsonResponse(corsHeaders, { error: "Unauthorized" }, 401);
  }

  const { allowed } = await checkRateLimit(supabaseAuth, user.id, "kael_ai", 10, 1);
  if (!allowed) {
    return jsonResponse(corsHeaders, { error: "Rate limit exceeded" }, 429);
  }

  try {
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return jsonResponse(corsHeaders, { error: "Invalid JSON body" }, 400);
    }

    const action = typeof body.action === "string" ? body.action : "chat";
    const messages = Array.isArray(body.messages) ? body.messages : [];
    const userContext =
      body.userContext && typeof body.userContext === "object" && !Array.isArray(body.userContext)
        ? (body.userContext as Record<string, unknown>)
        : null;

    // Non-chat actions accept prompt/message/content directly (legacy field names).
    const isChat =
      action === "chat" ||
      (typeof body.prompt !== "string" && typeof body.message !== "string" && typeof body.content !== "string");

    let directPrompt: string | null = null;
    if (!isChat) {
      directPrompt =
        typeof body.prompt === "string" ? body.prompt
        : typeof body.message === "string" ? body.message
        : typeof body.content === "string" ? body.content
        : null;
      if (!directPrompt) {
        return jsonResponse(corsHeaders, { error: "prompt/message/content is required for this action" }, 400);
      }
    } else if (messages.length === 0) {
      return jsonResponse(corsHeaders, { error: "messages array is required" }, 400);
    }

    let systemPrompt: string;
    if (isChat) {
      systemPrompt = KAEL_SYSTEM_PROMPT;
    } else if (action === "summary" || action === "summarize") {
      systemPrompt = SUMMARIZER_SYSTEM_PROMPT;
    } else if (action === "dramatize") {
      systemPrompt = DRAMATIZER_SYSTEM_PROMPT;
    } else if (action === "exegesis") {
      systemPrompt = EXEGESIS_PROMPT;
    } else if (action === "concordance") {
      systemPrompt = CONCORDANCE_PROMPT;
    } else if (action === "cross_ref") {
      systemPrompt = CROSS_REF_PROMPT;
    } else if (action === "chapter_summary") {
      systemPrompt = CHAPTER_SUMMARY_PROMPT;
    } else if (action === "voice_search") {
      systemPrompt = VOICE_SEARCH_PROMPT;
    } else {
      systemPrompt = DEFAULT_SYSTEM_PROMPT;
    }

    // Provider: HuggingFace free-tier inference (no Gemini charges).
    let text: string | null = null;
    let providerError = "";
    try {
      text = await callHuggingFace(messages, userContext, directPrompt, systemPrompt, isChat);
    } catch (e) {
      providerError = e instanceof Error ? e.message : "HuggingFace error";
    }

    const FALLBACK_RESPONSES = [
      "I'm here to help with your spiritual questions and church activities.",
      "How can I assist you today with scripture or church matters?",
      "I'm ready to guide you — what's on your mind regarding faith or church?",
    ];

    if (!text) {
      // Graceful fallback: stream a helpful message as normal chunks instead of erroring.
      const fallback = FALLBACK_RESPONSES[Math.floor(Math.random() * FALLBACK_RESPONSES.length)];
      if (isChat) return sseTextStream(corsHeaders, `${fallback}\n\n(Kael is warming up — try again in a moment for a full response.)`);
      return jsonResponse(corsHeaders, { response: fallback }, 200);
    }

    // Non-chat actions (summary, dramatize, generate) return plain JSON.
    if (!isChat) {
      return jsonResponse(corsHeaders, { response: text });
    }

    // Chat returns a simulated SSE token stream for the real-time typing UI.
    return sseTextStream(corsHeaders, text);
  } catch (e) {
    const errorMsg = e instanceof Error ? e.message : "Unknown error";
    return sseErrorEvent(corsHeaders, errorMsg);
  }
});
