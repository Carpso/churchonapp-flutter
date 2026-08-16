import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { getCorsHeaders } from "../_shared/cors.ts";

// Official bundle catalogue (Kwacha price → SMS credits). The client only
// sends the credits count; the price is re-derived SERVER-SIDE so a forged
// amount can never change what is charged against a confirmed payment.
const BUNDLES: Record<number, number> = {
  100: 50,   // K50 → 100 credits
  250: 100,  // K100 → 250 credits
  600: 250,  // K250 → 600 credits
};

// Payment states that count as a confirmed collection (mirrors lipila-payout).
const CONFIRMED_STATUSES = ['approved', 'completed', 'confirmed', 'settled'];

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 401,
    })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const supabase = createClient(supabaseUrl, supabaseServiceKey)

  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 401,
    })
  }

  try {
    const { tenant_id, credits, payment_ref } = await req.json()

    if (!tenant_id || !credits || !payment_ref) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Verify user has access to this tenant
    const { data: profile } = await supabase
      .from('profiles')
      .select('tenant_id')
      .eq('id', user.id)
      .single()

    if (!profile || profile['tenant_id'] !== tenant_id) {
      return new Response(JSON.stringify({ error: 'Access denied to this tenant' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    // Server-side price derivation — never trust the client's amount.
    const expectedPrice = BUNDLES[credits]
    if (!expectedPrice) {
      return new Response(JSON.stringify({ error: 'Invalid credit bundle' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Idempotency: a payment reference may only grant credits once.
    const { data: existing } = await supabase
      .from('tenant_sms_transactions')
      .select('id')
      .eq('payment_ref', payment_ref)
      .eq('type', 'purchase')
      .maybeSingle()
    if (existing) {
      return new Response(JSON.stringify({
        success: true,
        credits_added: credits,
        amount_paid: expectedPrice,
        payment_ref,
        already_applied: true,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Anchor on a CONFIRMED coa_payments collection — a client-supplied
    // payment_ref with no real payment can never mint credits.
    const { data: payment } = await supabase
      .from('coa_payments')
      .select('id, status, amount, user_id')
      .eq('payment_ref', payment_ref)
      .maybeSingle()

    if (!payment) {
      return new Response(JSON.stringify({
        error: 'Payment reference not found. Wait for the payment to be confirmed.',
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    if (!CONFIRMED_STATUSES.includes(payment['status'])) {
      return new Response(JSON.stringify({
        error: `Payment not confirmed yet (status: ${payment['status']}). Try again shortly.`,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 402,
      })
    }

    const paidAmount = Number(payment['amount'] ?? 0)
    if (paidAmount < expectedPrice) {
      return new Response(JSON.stringify({
        error: `Payment amount (K${paidAmount}) is less than the bundle price (K${expectedPrice}).`,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 402,
      })
    }

    // Add credits
    const { error: addError } = await supabase.rpc('add_sms_credits', {
      p_tenant_id: tenant_id,
      p_credits: credits,
      p_payment_ref: payment_ref,
    })

    if (addError) {
      return new Response(JSON.stringify({ error: `Failed to add credits: ${addError.message}` }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    return new Response(JSON.stringify({
      success: true,
      credits_added: credits,
      amount_paid: expectedPrice,
      payment_ref,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({
      success: false,
      error: (error as Error).message,
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})