-- ============================================================================
-- 20261147_radio_stories_join.sql
-- 1. Radio: remove junk station (config is COA-only; tenants just listen).
-- 2. Stories: make `tenant_id` server-authoritative + default 24h expiry so a
--    posted story is actually visible to the church (it was written from a
--    possibly-null in-memory profile → NULL tenant → nobody saw it).
-- 3. Join: invite-code lookup was owner-only RLS, so an invited member could
--    never validate the shared link/code. Add a SECURITY DEFINER RPC.
-- ============================================================================

-- ── 1. Radio data hygiene ───────────────────────────────────────────────────
DELETE FROM public.radio_stations WHERE name ILIKE '%test%';

-- ── 2. Stories: server-side tenant + expiry ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_story_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tenant_id IS NULL THEN
    SELECT p.tenant_id INTO NEW.tenant_id
      FROM public.profiles p WHERE p.id = NEW.user_id;
  END IF;
  IF NEW.expires_at IS NULL THEN
    NEW.expires_at := now() + interval '24 hours';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_story_defaults_ins ON public.social_stories;
CREATE TRIGGER trg_story_defaults_ins
  BEFORE INSERT ON public.social_stories
  FOR EACH ROW EXECUTE FUNCTION public.set_story_defaults();

DROP TRIGGER IF EXISTS trg_story_defaults_upd ON public.social_stories;
CREATE TRIGGER trg_story_defaults_upd
  BEFORE UPDATE ON public.social_stories
  FOR EACH ROW EXECUTE FUNCTION public.set_story_defaults();

-- ── 3. Invite-code lookup (any authenticated user) ──────────────────────────
CREATE OR REPLACE FUNCTION public.lookup_invite_code(p_code text)
RETURNS TABLE (
  tenant_id   uuid,
  tenant_name text,
  country     text,
  code_type   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (g.metadata->>'tenant_id')::uuid AS tenant_id,
         t.name                            AS tenant_name,
         t.country                         AS country,
         g.code_type                       AS code_type
    FROM public.generated_codes g
    LEFT JOIN public.tenants t ON t.id = (g.metadata->>'tenant_id')::uuid
   WHERE g.code_value = p_code
     AND g.code_type IN ('tenant', 'church')
   LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.lookup_invite_code(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.lookup_invite_code(text) FROM public;
GRANT EXECUTE ON FUNCTION public.lookup_invite_code(text) TO authenticated;
