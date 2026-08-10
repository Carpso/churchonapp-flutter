import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") || "Church On App <noreply@churchonapp.com>";

function escapeHtml(str: string): string {
  if (!str) return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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

  // Per-type role gate (not blanket):
  //   user-triggered types → any authenticated user
  //   church-level types    → leadership (bishop/pastor/admin/superadmin/coa_employee)
  //   admin-only types       → superadmin / coa_employee only
  const { data: profile, error: profileError } = await supabaseAuth
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  const role = profile?.role ?? "member";
  const isLeadership = ["superadmin", "coa_employee", "bishop", "pastor", "admin"].includes(role);
  const isSuper = role === "superadmin" || role === "coa_employee";

  // Gate will be applied per-type inside the switch block; store for reference.
  // (profile fetch shared for logging; type-specific gating below)

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ success: false, error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const { type, to, userName, ...data } = body;

    // Per-type role gate — only reject types that require higher privilege.
    // Types not listed (or with empty gate) are open to any authenticated user.
    const typeGates: Record<string, string[]> = {
      security_alert: ["superadmin", "coa_employee"],
      church_approval: ["superadmin", "coa_employee", "bishop", "pastor", "admin"],
      subscription_warning: ["superadmin", "coa_employee", "bishop", "pastor", "admin"],
    };
    const gate = typeGates[type];
    if (gate && gate.length > 0 && !gate.includes(role)) {
      return new Response(JSON.stringify({ success: false, error: `Email type "${type}" requires higher role (${gate.join(", ")}). Your role: ${role}` }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let subject = "";
    let html = "";

    switch (type) {
      case "security_alert":
        subject = `Security Alert: ${data.eventType}`;
        html = securityAlertTemplate(userName, data.eventType, data.details, data.ipAddress);
        break;

      case "welcome":
        subject = "Welcome to Church On App!";
        html = welcomeTemplate(userName, data.churchName);
        break;

      case "payment_receipt":
        subject = `Payment Receipt - K${data.amount}`;
        html = paymentReceiptTemplate(userName, data.amount, data.paymentType, data.reference, data.churchName);
        break;

      case "church_approval":
        subject = data.isApproved ? "Church Registration Approved" : "Church Registration Update";
        html = churchApprovalTemplate(userName, data.churchName, data.isApproved, data.rejectionReason);
        break;

      case "event_confirmation":
        subject = `Event Registration Confirmed - ${data.eventName}`;
        html = eventConfirmationTemplate(userName, data.eventName, data.eventDate, data.eventLocation);
        break;

      case "subscription_warning":
        subject = `Subscription Expiring Soon - ${data.daysRemaining} Days Left`;
        html = subscriptionWarningTemplate(userName, data.churchName, data.daysRemaining);
        break;

      default:
        return new Response(JSON.stringify({ success: false, error: "Unknown email type" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [to],
        subject,
        html,
      }),
    });

    const result = await response.json();

    if (!response.ok) {
      console.error("Resend error:", result);
      return new Response(JSON.stringify({ success: false, error: result.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    await supabase.from("email_logs").insert({
      recipient_email: to,
      subject,
      email_type: type,
      status: "sent",
      resend_id: result.id,
      metadata: data,
    });

    return new Response(JSON.stringify({ success: true, id: result.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Email send error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function securityAlertTemplate(userName: string, eventType: string, details: string, ipAddress?: string): string {
  const safeUser = escapeHtml(userName);
  const safeEvent = escapeHtml(eventType);
  const safeDetails = escapeHtml(details || 'No additional details');
  const safeIp = ipAddress ? escapeHtml(ipAddress) : '';
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:#DC2626;color:white;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">⚠️ Security Alert</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${safeUser},</p>
          <p>We detected a <strong>${safeEvent}</strong> on your account.</p>
          <div style="background:#FEF2F2;border-left:4px solid #DC2626;padding:15px;margin:15px 0;">
            <p style="margin:0;"><strong>Event:</strong> ${safeEvent}</p>
            <p style="margin:5px 0 0;"><strong>Details:</strong> ${safeDetails}</p>
            ${safeIp ? `<p style="margin:5px 0 0;"><strong>IP Address:</strong> ${safeIp}</p>` : ''}
          </div>
          <p>If this was you, no action is needed. If you don't recognize this activity, please change your password immediately and contact support.</p>
          <p style="color:#666;font-size:12px;">Church On App Security Team</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

function welcomeTemplate(userName: string, churchName?: string): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:#FFD700;color:#1A1A1A;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">Welcome to Church On App!</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${userName},</p>
          <p>Welcome to Church On App! We're excited to have you join our community of believers.</p>
          ${churchName ? `<p>You've been connected to <strong>${churchName}</strong>.</p>` : ''}
          <p>Here's what you can do:</p>
          <ul>
            <li>Give tithes and offerings digitally</li>
            <li>Join Bible study groups</li>
            <li>Attend events and get tickets</li>
            <li>Connect with your church community</li>
            <li>Earn Loyalty Coins for daily activities</li>
          </ul>
          <p>Start your journey today!</p>
          <p style="color:#666;font-size:12px;">With love from the Church On App Team</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

function paymentReceiptTemplate(userName: string, amount: string, paymentType: string, reference: string, churchName?: string): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:#059669;color:white;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">Payment Confirmed</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${userName},</p>
          <p>Your payment has been successfully processed.</p>
          <div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:20px;margin:15px 0;">
            <table style="width:100%;border-collapse:collapse;">
              <tr><td style="padding:5px 0;color:#666;">Amount:</td><td style="padding:5px 0;font-weight:bold;font-size:18px;">K${amount}</td></tr>
              <tr><td style="padding:5px 0;color:#666;">Type:</td><td style="padding:5px 0;">${paymentType}</td></tr>
              <tr><td style="padding:5px 0;color:#666;">Reference:</td><td style="padding:5px 0;font-family:monospace;">${reference}</td></tr>
              ${churchName ? `<tr><td style="padding:5px 0;color:#666;">Church:</td><td style="padding:5px 0;">${churchName}</td></tr>` : ''}
            </table>
          </div>
          <p style="color:#666;font-size:12px;">Thank you for your generous giving!</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

function churchApprovalTemplate(userName: string, churchName: string, isApproved: boolean, rejectionReason?: string): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:${isApproved ? '#059669' : '#DC2626'};color:white;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">${isApproved ? 'Church Approved!' : 'Church Registration Update'}</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${userName},</p>
          ${isApproved
            ? `<p>Congratulations! <strong>${churchName}</strong> has been approved on Church On App.</p><p>You can now start onboarding your church and inviting members.</p>`
            : `<p>We regret to inform you that <strong>${churchName}</strong> was not approved.</p>${rejectionReason ? `<p>Reason: ${rejectionReason}</p>` : ''}<p>Please review the requirements and reapply.</p>`
          }
        </div>
      </div>
    </body>
    </html>
  `;
}

function eventConfirmationTemplate(userName: string, eventName: string, eventDate: string, eventLocation?: string): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:#FFD700;color:#1A1A1A;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">Event Confirmed!</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${userName},</p>
          <p>You're registered for <strong>${eventName}</strong>!</p>
          <div style="background:#F5F3FF;border:1px solid #DDD6FE;border-radius:10px;padding:15px;margin:15px 0;">
            <p style="margin:0;"><strong>Date:</strong> ${eventDate}</p>
            ${eventLocation ? `<p style="margin:5px 0 0;"><strong>Location:</strong> ${eventLocation}</p>` : ''}
          </div>
          <p>See you there!</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

function subscriptionWarningTemplate(userName: string, churchName: string, daysRemaining: number): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
      <div style="max-width:600px;margin:0 auto;background:white;padding:30px;">
        <div style="background:#FFD700;color:#1A1A1A;padding:20px;border-radius:10px 10px 0 0;text-align:center;">
          <h1 style="margin:0;font-size:20px;">Subscription Expiring Soon</h1>
        </div>
        <div style="padding:20px;">
          <p>Hello ${userName},</p>
          <p>Your subscription for <strong>${churchName}</strong> expires in <strong>${daysRemaining} days</strong>.</p>
          <p>Please renew to continue enjoying all features of Church On App.</p>
          <p>Contact support if you need assistance.</p>
        </div>
      </div>
    </body>
    </html>
  `;
}
