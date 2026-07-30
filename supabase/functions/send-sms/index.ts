import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const AT_API_URL = 'https://api.africastalking.com/version1/messaging'
const SMS_CREDIT_COST = 1 // 1 SMS = 1 credit

interface SendSmsRequest {
  tenant_id: string
  phone_numbers: string[]
  message: string
  audience_label?: string
}

function formatPhone(phone: string): string {
  const cleaned = phone.replace(/\D/g, '')
  if (cleaned.startsWith('260')) return `+${cleaned}`
  if (cleaned.startsWith('0')) return `+260${cleaned.substring(1)}`
  if (cleaned.startsWith('9')) return `+260${cleaned}`
  return `+260${cleaned}`
}

serve(async (req) => {
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
    const { tenant_id, phone_numbers, message, audience_label }: SendSmsRequest = await req.json()

    if (!tenant_id || !phone_numbers?.length || !message) {
      return new Response(JSON.stringify({ error: 'Missing required fields: tenant_id, phone_numbers, message' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const totalCost = phone_numbers.length * SMS_CREDIT_COST

    // Check balance
    const { data: balanceData, error: balanceError } = await supabase.rpc('get_tenant_balance', {
      p_tenant_id: tenant_id,
    })

    if (balanceError) {
      return new Response(JSON.stringify({ error: `Balance check failed: ${balanceError.message}` }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    const currentBalance = (balanceData as number) ?? 0
    if (currentBalance < totalCost) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Insufficient SMS credits',
        balance: currentBalance,
        required: totalCost,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 402,
      })
    }

    // Deduct credits first (atomic)
    const { data: deducted, error: deductError } = await supabase.rpc('deduct_sms_credits', {
      p_tenant_id: tenant_id,
      p_credits: totalCost,
    })

    if (deductError || !deducted) {
      return new Response(JSON.stringify({ error: 'Failed to deduct SMS credits' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    // Send via Africa's Talking
    const atUsername = Deno.env.get('AFRICASTALKING_USERNAME') ?? ''
    const atApiKey = Deno.env.get('AFRICASTALKING_API_KEY') ?? ''
    const atFrom = Deno.env.get('AFRICASTALKING_FROM') ?? 'COA'

    const formattedPhones = phone_numbers.map(formatPhone)
    const atResponse = await fetch(AT_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'apiKey': atApiKey,
        'Accept': 'application/json',
      },
      body: new URLSearchParams({
        username: atUsername,
        to: formattedPhones.join(','),
        message: message,
        from: atFrom,
      }),
    })

    const atResult = await atResponse.json()

    // Log to sms_logs
    const successCount = atResult?.SMSMessageData?.Recipients?.filter((r: any) => r.status === 'Success').length ?? 0
    const failedCount = phone_numbers.length - successCount

    await supabase.from('sms_logs').insert({
      tenant_id,
      phone_numbers: formattedPhones,
      message,
      type: 'broadcast',
      status: atResponse.ok ? 'sent' : 'failed',
      audience_label: audience_label ?? 'all',
      credits_used: totalCost,
      gateway_response: atResult,
      sender_id: user.id,
      success_count: successCount,
      failed_count: failedCount > 0 ? failedCount : null,
    })

    // If all failed, refund credits
    if (successCount === 0 && !atResponse.ok) {
      await supabase.rpc('add_sms_credits', {
        p_tenant_id: tenant_id,
        p_credits: totalCost,
        p_payment_ref: 'refund-broadcast-fail',
      })

      return new Response(JSON.stringify({
        success: false,
        error: 'SMS gateway returned errors',
        gateway_result: atResult,
        credits_refunded: totalCost,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 502,
      })
    }

    // Partial failure: refund unsent credits
    if (failedCount > 0) {
      await supabase.rpc('add_sms_credits', {
        p_tenant_id: tenant_id,
        p_credits: failedCount * SMS_CREDIT_COST,
        p_payment_ref: 'refund-partial-fail',
      })
    }

    return new Response(JSON.stringify({
      success: true,
      sent: successCount,
      failed: failedCount,
      total_used: totalCost,
      remaining: currentBalance - totalCost + (failedCount * SMS_CREDIT_COST),
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
