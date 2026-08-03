import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { getCorsHeaders } from "../_shared/cors.ts"

const TURN_SERVER_URL = Deno.env.get("TURN_SERVER_URL") || "turn:turn.churchonapp.com:3478"
const TURN_SECRET = Deno.env.get("TURN_SECRET")

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"))

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get("authorization") || ""
    const jwt = authHeader.replace("Bearer ", "")
    if (!jwt) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey)

    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(jwt)
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (!TURN_SECRET) {
      return new Response(
        JSON.stringify({
          iceServers: [
          { urls: "stun:stun.l.google.com:19302" },
          { urls: "stun:stun1.l.google.com:19302" },
          { urls: "stun:stun2.l.google.com:19302" },
          { urls: "stun:stun3.l.google.com:19302" },
          { urls: "stun:stun4.l.google.com:19302" },
            { urls: "stun:stun2.l.google.com:19302" },
            { urls: "stun:stun3.l.google.com:19302" },
            { urls: "stun:stun4.l.google.com:19302" },
          ],
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      )
    }

    const encoder = new TextEncoder()
    const keyData = encoder.encode(TURN_SECRET)
    const cryptoKey = await crypto.subtle.importKey("raw", keyData, { name: "HMAC", hash: "SHA-1" }, false, ["sign"])

    const timestamp = Math.floor(Date.now() / 1000) + 86400
    const username = `${timestamp}:churchonapp`
    const message = encoder.encode(username)
    const signature = await crypto.subtle.sign("HMAC", cryptoKey, message)
    const credential = btoa(String.fromCharCode(...new Uint8Array(signature)))

    return new Response(
      JSON.stringify({
        iceServers: [
          {
            urls: TURN_SERVER_URL,
            username,
            credential,
          },
          { urls: "stun:stun.l.google.com:19302" },
          { urls: "stun:stun1.l.google.com:19302" },
          { urls: "stun:stun2.l.google.com:19302" },
          { urls: "stun:stun3.l.google.com:19302" },
          { urls: "stun:stun4.l.google.com:19302" },
        ],
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  } catch (e) {
    console.error("turn-credentials error:", e)
    return new Response(
      JSON.stringify({
        iceServers: [
          { urls: "stun:stun.l.google.com:19302" },
          { urls: "stun:stun1.l.google.com:19302" },
          { urls: "stun:stun2.l.google.com:19302" },
          { urls: "stun:stun3.l.google.com:19302" },
          { urls: "stun:stun4.l.google.com:19302" },
        ],
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  }
})
