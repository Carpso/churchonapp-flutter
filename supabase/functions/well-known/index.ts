import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const assetlinks = [
  {
    "relation": [
      "delegate_permission/common.handle_all_urls"
    ],
    "target": {
      "namespace": "android_app",
      "package_name": "com.churchonapp.app",
      "sha256_cert_fingerprints": [
        "BE:70:FA:D2:24:BC:B2:3D:64:0D:A8:69:4F:64:A5:94:3B:51:B5:A5:34:F9:F3:63:3F:FD:49:A0:1A:60:E0:B2"
      ]
    }
  }
];

const appleAppSiteAssociation = {
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "YOUR_APPLE_TEAM_ID.com.churchonapp.churchOnApp",
        "paths": [
          "*"
        ]
      }
    ]
  }
};

serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname;

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (path.endsWith('/assetlinks.json')) {
    return new Response(JSON.stringify(assetlinks), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      },
      status: 200,
    });
  }

  if (path.endsWith('/apple-app-site-association')) {
    return new Response(JSON.stringify(appleAppSiteAssociation), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      },
      status: 200,
    });
  }

  return new Response(
    JSON.stringify({ message: "Church On App Verification Edge Endpoint. Use /.well-known/assetlinks.json or /.well-known/apple-app-site-association" }),
    {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 404,
    }
  );
})
