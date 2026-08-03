import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabaseAuth = createClient(supabaseUrl, supabaseKey)

  const token = authHeader.replace("Bearer ", "")
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token)
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    })
  }

  try {
    const { studyId, tenantId, title, date, time } = await req.json()
    
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get all members of the tenant
    const { data: members } = await supabase
      .from('profiles')
      .select('id')
      .eq('tenant_id', tenantId)

    if (!members || members.length === 0) {
      return new Response(JSON.stringify({ success: true, notified: 0 }), { headers: { 'Content-Type': 'application/json' } })
    }

    const notifications = members.map((m: { id: string }) => ({
      user_id: m.id,
      title: '📖 New Bible Study',
      body: `${title} - ${date} at ${time}`,
      data: { type: 'bible_study', study_id: studyId },
    }))

    const { error } = await supabase.from('notifications').insert(notifications)
    if (error) throw error

    return new Response(
      JSON.stringify({ success: true, notified: notifications.length }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
