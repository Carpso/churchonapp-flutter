import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
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
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { allowed } = await checkRateLimit(supabase, user.id, "lipila_payout", 10, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Role check: these roles may request arbitrary payouts.
    // Other roles (members) may only settle a verified COA transaction.
    const { data: profile } = await supabase
      .from("profiles").select("role").eq("id", user.id).maybeSingle();
    const canRequestPayout = ["superadmin", "coa_employee", "driver", "vendor", "bookshop_owner"].includes(profile?.role);

    // ── Server-side fee config (defense-in-depth) ────────────────────────
    // Mirrors FeeConfig.payoutNet(): deducts Lipila's disbursement fee plus
    // COA's payout fee (min K3) from the gross. Values are remote-configurable
    // via platform_settings so the server never trusts client-side math.
    const { data: feeRows } = await supabase
      .from("platform_settings")
      .select("key, value")
      .in("key", [
        "lipila_disbursement_fee_percent",
        "coa_payout_fee_percent",
        "min_fee_kwacha",
      ]);

    let disbFeePercent = 0.015;
    let coaPayoutFeePercent = 0.01;
    let minFeeKwacha = 3.0;
    for (const row of feeRows ?? []) {
      const parsed = Number(row.value);
      if (Number.isNaN(parsed)) continue;
      if (row.key === "lipila_disbursement_fee_percent") disbFeePercent = parsed;
      else if (row.key === "coa_payout_fee_percent") coaPayoutFeePercent = parsed;
      else if (row.key === "min_fee_kwacha") minFeeKwacha = parsed;
    }

    const payoutNet = (gross: number): number => {
      const disbursement = gross * disbFeePercent;
      const coaPayout = Math.max(gross * coaPayoutFeePercent, minFeeKwacha);
      return gross - disbursement - coaPayout;
    };
    // Allow 1 kwacha slack for double-precision rounding on the client.
    const exceedsNet = (requested: number, maxNet: number): boolean =>
      requested > maxNet + 1.0;

    const { accountNumber, amount, narration, referenceId, reference, grossAmount } = await req.json();

    if (!accountNumber || !amount || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid payout parameters" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!/^260\d{9}$/.test(accountNumber)) {
      return new Response(JSON.stringify({ error: "Invalid mobile money number. Must be a valid Zambian number (260XXXXXXXXX)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payoutRef = referenceId ?? crypto.randomUUID();

    // Trusted roles must prove the payout was properly netted: the requested
    // amount may never exceed payoutNet(grossAmount). Catches accidental raw
    // (un-netted) amounts and enforces FeeConfig server-side.
    if (canRequestPayout) {
      if (typeof grossAmount !== "number" || !(grossAmount > 0)) {
        return new Response(JSON.stringify({ error: "grossAmount is required for payouts" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (exceedsNet(amount, payoutNet(grossAmount))) {
        return new Response(JSON.stringify({
          error: "Forbidden: payout amount exceeds net payout for the given gross amount",
        }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Non-payout roles must pass server-side verification of a real,
    // completed transaction owned by the caller before any money moves.
    if (!canRequestPayout) {
      if (!reference) {
        return new Response(JSON.stringify({ error: "Forbidden: settlement reference required" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: txn } = await supabase
        .from("transactions")
        .select("id, amount, status, user_id, recipient_phone, payout_ref")
        .eq("reference", reference)
        .maybeSingle();

      if (!txn || txn.user_id !== user.id || txn.status !== "completed") {
        return new Response(JSON.stringify({ error: "Forbidden: settlement not authorized" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // ── Security hardening: payouts must be anchored to a REAL collection ──
      // The `transactions` row is client-insertable, so `status = completed`
      // alone proves nothing. Require a matching coa_payments row (created by
      // lipila-collect via service role) that reached a confirmed status.
      // coa_payments UPDATE is superadmin-only, so a member cannot forge this.
      const { data: payment } = await supabase
        .from("coa_payments")
        .select("status, amount, phone_number")
        .eq("payment_ref", reference)
        .maybeSingle();
      const confirmedStatuses = ["approved", "completed", "confirmed", "settled"];
      const paymentStatus = (payment?.status ?? "").toLowerCase();
      if (!payment || !confirmedStatuses.includes(paymentStatus)) {
        return new Response(JSON.stringify({
          error: "Forbidden: no verified collection for this reference",
        }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      // Never pay out more than the verified collection (defense in depth).
      if (typeof payment.amount === "number" && Number(txn.amount) > payment.amount + 1.0) {
        return new Response(JSON.stringify({ error: "Forbidden: payout exceeds verified collection" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const norm = (p: string): string => {
        let s = (p ?? "").replace(/\D/g, "");
        if (s.startsWith("0")) s = "260" + s.slice(1);
        else if (s.length === 9) s = "260" + s;
        return s;
      };
      if (norm(txn.recipient_phone) !== norm(accountNumber)) {
        return new Response(JSON.stringify({ error: "Forbidden: payout recipient mismatch" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      // Payout must stay within the FeeConfig-netted ceiling of the gross.
      // The client sends payoutNet(amount); reject anything above that.
      if (exceedsNet(amount, payoutNet(txn.amount))) {
        return new Response(JSON.stringify({
          error: "Forbidden: payout exceeds net transaction amount after fees",
        }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Idempotency: claim the settlement atomically so it can never be paid twice.
      const { data: claimed } = await supabase
        .from("transactions")
        .update({ payout_ref: payoutRef })
        .eq("reference", reference)
        .eq("payout_ref", null)
        .select("id")
        .maybeSingle();
      if (!claimed) {
        return new Response(JSON.stringify({ success: true, alreadySettled: true, reference: payoutRef }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const apiKey = Deno.env.get("LIPILA_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Lipila API key not configured on server" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const baseUrl = apiKey.startsWith("lsk_")
      ? "https://blz.lipila.io/api"
      : "https://api.lipila.dev/api";

    const callbackUrl = Deno.env.get("LIPILA_PAYOUT_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;

    const payoutRes = await fetch(`${baseUrl}/v1/payouts/mobile-money`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        callbackUrl,
        referenceId: payoutRef,
        amount,
        narration: narration ?? "COA payout",
        accountNumber,
        currency: "ZMW",
        email: "payouts@churchonapp.com",
      }),
    });

    const payoutData = await payoutRes.json();

    if (!payoutRes.ok) {
      console.error("Lipila payout failed:", payoutData);
      return new Response(JSON.stringify({ error: "Payout failed", details: payoutData }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, reference: payoutRef, data: payoutData }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
