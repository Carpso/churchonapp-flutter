import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 405,
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limit: max 10 birthday emails per hour per user
    const { checkRateLimit } = await import("../_shared/rate-limit.ts");
    const rateLimit = await checkRateLimit(supabase, user.id, "birthday_email", 10, 60);
    if (!rateLimit.allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { user_id, email, name, age } = await req.json();

    if (!email || !name) {
      return new Response(
        JSON.stringify({ error: "email and name are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Get Resend API key from secrets
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const emailFrom = Deno.env.get("EMAIL_FROM") || "birthdays@churchonapp.com";

    if (!resendApiKey) {
      console.warn("RESEND_API_KEY not configured, skipping email");
      return new Response(
        JSON.stringify({ success: true, email_sent: false, reason: "no_api_key" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Age-appropriate subject lines
    let subject = `Happy Birthday, ${name}! 🎂`;
    let htmlContent = "";

    if (age > 0 && age <= 12) {
      subject = `Happy ${age}th Birthday, ${name}! 🎉`;
      htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; text-align: center; padding: 20px;">
          <h1 style="color: #6B46C1; font-size: 28px;">🎂 Happy ${age}th Birthday, ${name}! 🎉</h1>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            God has blessed you with another amazing year! We hope your special day is filled with joy, laughter, and lots of cake! 🎈
          </p>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            Keep growing in faith and wisdom — the Church On App family is cheering you on! ⭐
          </p>
          <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 20px 0;">
          <p style="color: #A0AEC0; font-size: 12px;">With love from the Church On App Team</p>
        </div>
      `;
    } else if (age >= 13 && age <= 25) {
      subject = `Happy Birthday, ${name}! 🎉`;
      htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; text-align: center; padding: 20px;">
          <h1 style="color: #2D3748; font-size: 28px;">🎂 Happy Birthday, ${name}!</h1>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            Another year older, another year bolder! May God's favor follow you everywhere this year. 🙏
          </p>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            From all of us at Church On App — we celebrate YOU today!
          </p>
          <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 20px 0;">
          <p style="color: #A0AEC0; font-size: 12px;">With love from the Church On App Team</p>
        </div>
      `;
    } else {
      subject = `Happy Birthday, ${name}! 🎂`;
      htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; text-align: center; padding: 20px;">
          <h1 style="color: #2D3748; font-size: 28px;">🎂 Happy Birthday, ${name}!</h1>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            On your special day, we want you to know how much you mean to this community. May the Lord bless you with health, joy, and abundance in the year ahead. 🙏
          </p>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            "The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you." — Numbers 6:24-25
          </p>
          <p style="color: #4A5568; font-size: 16px; line-height: 1.6;">
            Happy ${age > 0 ? "${age}th " : ""}Birthday from the Church On App family! 🎉
          </p>
          <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 20px 0;">
          <p style="color: #A0AEC0; font-size: 12px;">With love from the Church On App Team</p>
        </div>
      `;
    }

    // Send email via Resend
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: emailFrom,
        to: [email],
        subject,
        html: htmlContent,
      }),
    });

    const emailResult = await emailResponse.json();

    if (!emailResponse.ok) {
      console.error("Resend error:", emailResult);
      return new Response(
        JSON.stringify({ success: false, error: emailResult.message || "Email send failed" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Log the email send
    await supabase.from("birthday_wishes").upsert(
      {
        user_id: user_id,
        wish_date: new Date().toISOString().split("T")[0],
        age: age || null,
      },
      { onConflict: "user_id,wish_date" }
    );

    return new Response(
      JSON.stringify({ success: true, email_sent: true, email_id: emailResult.id }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Birthday email error:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
