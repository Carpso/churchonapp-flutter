import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const HF_API_BASE = "https://api-inference.huggingface.co/models";
const HF_MODEL = "mistralai/Mistral-7B-Instruct-v0.3";

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
- Automated payouts to churches (platform collects, disburses minus 5% fee)
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

function buildPrompt(
  messages: Array<{ role: string; content: string }>,
  userContext: Record<string, unknown> | null,
): string {
  let systemPrompt = KAEL_SYSTEM_PROMPT;

  if (userContext && Object.keys(userContext).length > 0) {
    const name = userContext.name || "User";
    const role = userContext.role || "member";
    const church = userContext.church_name || "your church";
    const streak = userContext.streak ?? 0;
    const level = userContext.level ?? "Beginner";

    systemPrompt += `\n\n## Active User Context (Live App State):\n`;
    systemPrompt += `- Context: User ${name}, Role: ${role}, Church: ${church}, Streak: ${streak} days, Quiz Level: ${level}\n`;
    systemPrompt += `- Greet the user by name, customize your response to their role and context.\n`;
    systemPrompt += `- Answer any questions about their personal statistics using this live context data.\n`;
  }

  let prompt = `<s>[INST] ${systemPrompt} [/INST]</s>\n`;

  // Build conversation history from messages array (excluding the last user message)
  const history = messages.slice(0, -1);
  for (const turn of history) {
    if (turn.role === "user") {
      prompt += `[INST] ${turn.content} [/INST]`;
    } else {
      prompt += ` ${turn.content}</s>\n`;
    }
  }

  // Add the last user message
  const lastMsg = messages[messages.length - 1];
  if (lastMsg) {
    prompt += `[INST] ${lastMsg.content} [/INST]`;
  }

  return prompt;
}

serve(async (req) => {
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
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  try {
    const { messages, userContext } = await req.json();

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: "messages array is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const hfToken = Deno.env.get("HUGGINGFACE_TOKEN");
    if (!hfToken) {
      return new Response(
        JSON.stringify({
          error: "HUGGINGFACE_TOKEN not configured on server",
          fallback: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const prompt = buildPrompt(messages, userContext);

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
      const errorText = await hfResponse.text();
      if (
        hfResponse.status === 503 ||
        errorText.toLowerCase().includes("loading")
      ) {
        // Model is loading — return SSE error event so client can show fallback
        const stream = new ReadableStream({
          start(controller) {
            controller.enqueue(
              new TextEncoder().encode(`data: ${JSON.stringify({ error: "Model is loading, please try again", done: true })}\n\n`)
            );
            controller.close();
          },
        });
        return new Response(stream, {
          status: 200,
          headers: {
            ...corsHeaders,
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
          },
        });
      }
      throw new Error(`HuggingFace API error: ${hfResponse.status} ${errorText}`);
    }

    // HuggingFace returns complete JSON even for non-streaming requests.
    // We simulate streaming by chunking the response text character-by-character
    // to give the client a real-time typing experience.
    const data = await hfResponse.json();
    const generatedText = Array.isArray(data)
      ? (data[0] as { generated_text?: string })?.generated_text?.trim()
      : null;

    if (!generatedText) {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(
            new TextEncoder().encode(`data: ${JSON.stringify({ error: "No response generated", done: true })}\n\n`)
          );
          controller.close();
        },
      });
      return new Response(stream, {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
        },
      });
    }

    // Stream the response in chunks for real-time UI
    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      start(controller) {
        // Send in chunks of ~3-8 words to simulate token streaming
        const words = generatedText.split(/(\s+)/);
        let buffer = "";
        let wordIndex = 0;

        const sendChunk = () => {
          if (wordIndex >= words.length) {
            // Send final done event
            controller.enqueue(
              encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`)
            );
            controller.close();
            return;
          }

          // Accumulate 2-5 words per chunk
          const chunkSize = 2 + Math.floor(Math.random() * 4);
          for (let i = 0; i < chunkSize && wordIndex < words.length; i++, wordIndex++) {
            buffer += words[wordIndex];
          }

          if (buffer.isNotEmpty) {
            controller.enqueue(
              encoder.encode(`data: ${JSON.stringify({ chunk: buffer })}\n\n`)
            );
            buffer = "";
          }

          // Small delay between chunks for smooth streaming feel
          setTimeout(sendChunk, 20 + Math.random() * 30);
        };

        sendChunk();
      },
    });

    return new Response(stream, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  } catch (e) {
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(
          new TextEncoder().encode(
            `data: ${JSON.stringify({
              error: e instanceof Error ? e.message : "Unknown error",
              done: true,
            })}\n\n`
          )
        );
        controller.close();
      },
    });
    return new Response(stream, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  }
});
