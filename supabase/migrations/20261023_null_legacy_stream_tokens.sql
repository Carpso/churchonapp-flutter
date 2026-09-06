-- Legacy per-church Cloudflare API tokens were stored in church_stream_config.cloudflare_api_token
-- but the Edge Function now reads the global CLOUDFLARE_API_TOKEN from Deno.env.
-- Nuke the column values so a compromised church admin row no longer leaks a token.
-- Keep the column (avoid breaking old clients) but ensure it is always NULL.

update public.church_stream_config
  set cloudflare_api_token = null
  where cloudflare_api_token is not null;

-- Optional: add a check to prevent future writes (commented, keep column nullable for back-compat)
-- alter table public.church_stream_config add constraint church_stream_config_no_per_church_token
--   check (cloudflare_api_token is null);
