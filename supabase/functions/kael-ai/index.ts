import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

// ─── Providers ─────────────────────────────────────────────────────────────
// Primary: Google Gemini Flash (free tier, fast). Fallback: HuggingFace
// inference (free tier — model must NOT be PRO-gated; default zephyr-7b-beta).
const HF_API_BASE = "https://api-inference.huggingface.co/models";
const HF_MODEL = Deno.env.get("HF_MODEL_ID") ?? "HuggingFaceH4/zephyr-7b-beta";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";
const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

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
- Each church (tenant) has its own scoped data via tenant_id
- Users belong to a church via profiles.tenant_id
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

/** ChatML template (zephyr-7b-beta, Qwen2.5-Instruct etc. on HF free tier). */
function buildChatPrompt(
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
  systemPrompt: string,
): string {
  let prompt = `<|system|>\n${buildSystemPrompt(systemPrompt, userContext)}<|endoftext|>\n`;

  for (const turn of messages) {
    if (turn.role === "user") {
      prompt += `<|user|>\n${turn.content}<|endoftext|>\n`;
    } else {
      prompt += `<|assistant|>\n${turn.content}<|endoftext|>\n`;
    }
  }
  prompt += `<|assistant|>\n`;
  return prompt;
}

function buildDirectPrompt(prompt: string, systemPrompt: string): string {
  return `<|system|>\n${systemPrompt}<|endoftext|>\n<|user|>\n${prompt}<|endoftext|>\n<|assistant|>\n`;
}

// ─── Provider calls ────────────────────────────────────────────────────────

async function callGemini(
  apiKey: string,
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
  directPrompt: string | null,
  systemPrompt: string,
  isChat: boolean,
): Promise<string> {
  const contents = isChat
    ? messages.map((m) => ({
        role: m.role === "user" ? "user" : "model",
        parts: [{ text: String(m.content ?? "") }],
      }))
    : [{ role: "user", parts: [{ text: directPrompt ?? "" }] }];

  const resp = await fetch(
    `${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: buildSystemPrompt(systemPrompt, userContext) }] },
        contents,
        generationConfig: { temperature: 0.7, maxOutputTokens: 1024 },
      }),
    },
  );

  if (!resp.ok) {
    throw new Error(`Gemini API error: ${resp.status} ${(await resp.text()).slice(0, 300)}`);
  }

  const data = await resp.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini returned an empty response");
  return text.trim();
}

async function callHuggingFace(
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
  directPrompt: string | null,
  systemPrompt: string,
  isChat: boolean,
): Promise<string> {
  const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
  if (!hfToken) throw new Error("HUGGINGFACE_TOKEN not configured on server");

  const prompt = isChat
    ? buildChatPrompt(messages, userContext, systemPrompt)
    : buildDirectPrompt(directPrompt ?? "", systemPrompt);

  const hfResponse = await fetch(`${HF_API_BASE}/${HF_MODEL}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${hfToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      inputs: prompt,
      parameters: {
        max_new_tokens: 512,
        temperature: 0.7,
        top_p: 0.9,
        do_sample: true,
        return_full_text: false,
      },
      options: {
        wait_for_model: true,
      },
    }),
  });

  if (!hfResponse.ok) {
    throw new Error(`HuggingFace API error: ${hfResponse.status} ${(await hfResponse.text()).slice(0, 300)}`);
  }

  const data = await hfResponse.json();
  const generatedText = Array.isArray(data)
    ? (data[0] as { generated_text?: string })?.generated_text?.trim()
    : null;
  if (!generatedText) throw new Error("HuggingFace returned an empty response");
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
    } else if (action === "summary") {
      systemPrompt = SUMMARIZER_SYSTEM_PROMPT;
    } else if (action === "dramatize") {
      systemPrompt = DRAMATIZER_SYSTEM_PROMPT;
    } else {
      systemPrompt = DEFAULT_SYSTEM_PROMPT;
    }

    // Primary provider: Gemini Flash.
    let text: string | null = null;
    const providerErrors: string[] = [];
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (geminiKey) {
      try {
        text = await callGemini(geminiKey, messages, userContext, directPrompt, systemPrompt, isChat);
      } catch (e) {
        providerErrors.push(e instanceof Error ? e.message : "Gemini error");
      }
    } else {
      providerErrors.push("GEMINI_API_KEY not configured");
    }

    // Fallback provider: HuggingFace free-tier model.
    if (!text) {
      try {
        text = await callHuggingFace(messages, userContext, directPrompt, systemPrompt, isChat);
      } catch (e) {
        providerErrors.push(e instanceof Error ? e.message : "HuggingFace error");
      }
    }

    if (!text) {
      const errorMsg = `Kael providers unavailable: ${providerErrors.join(" | ")}`;
      if (isChat) return sseErrorEvent(corsHeaders, errorMsg);
      return jsonResponse(corsHeaders, { error: errorMsg }, 502);
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
