// Shared CORS configuration for all Edge Functions.
// In production, restrict origins to your actual domains.
// For local dev, allow localhost variants.

const ALLOWED_ORIGINS = [
  "https://churchonapp.com",
  "https://www.churchonapp.com",
  "https://app.churchonapp.com",
  "http://localhost:3000",
  "http://localhost:8080",
];

export function getCorsHeaders(requestOrigin: string | null): Record<string, string> {
  const origin = ALLOWED_ORIGINS.includes(requestOrigin ?? "")
    ? requestOrigin!
    : ALLOWED_ORIGINS[0]; // fallback to production domain

  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-webhook-signature",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Vary": "Origin",
  };
}
