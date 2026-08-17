-- 20260906: Church website enhancements (bookshop support, pretty slugs,
-- view analytics, manage-policy widening) + pastoral follow-ups + app events.

-- ── 1. church_websites: tenant scoping, slug, view count ─────────────────────
ALTER TABLE public.church_websites ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.church_websites ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE public.church_websites ADD COLUMN IF NOT EXISTS view_count BIGINT NOT NULL DEFAULT 0;

-- Backfill tenant_id + slug from the owning church (all existing websites are churches).
UPDATE public.church_websites w
SET tenant_id = c.tenant_id
FROM public.churches c
WHERE w.church_id = c.id AND w.tenant_id IS NULL;

UPDATE public.church_websites w
SET slug = c.slug
FROM public.churches c
WHERE w.church_id = c.id AND (w.slug IS NULL OR w.slug = '');

-- Bookshops: seed a slug for existing bookshop tenants so /c/<slug> works.
UPDATE public.church_websites w
SET slug = b.slug
FROM public.bookshops b
WHERE w.tenant_id = b.tenant_id AND w.church_id IS NULL AND (w.slug IS NULL OR w.slug = '');

CREATE UNIQUE INDEX IF NOT EXISTS church_websites_slug_key ON public.church_websites (slug) WHERE slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS church_websites_tenant_idx ON public.church_websites (tenant_id);

-- ── 2. Widen the manage policy to all leadership roles, matched by tenant ────
DROP POLICY IF EXISTS "church_websites_manage" ON public.church_websites;
CREATE POLICY church_websites_manage ON public.church_websites
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'coa_employee',
          'treasurer', 'secretary', 'assistant_pastor',
          'bookshop_owner', 'merchant'
        )
        AND (p.tenant_id::uuid = church_websites.tenant_id OR p.church_id = church_websites.church_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'coa_employee',
          'treasurer', 'secretary', 'assistant_pastor',
          'bookshop_owner', 'merchant'
        )
        AND (p.tenant_id::uuid = church_websites.tenant_id OR p.church_id = church_websites.church_id)
    )
  );

-- ── 3. Anonymous view counter (published rows only) ──────────────────────────
CREATE OR REPLACE FUNCTION increment_website_view(p_website_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_website_id IS NULL THEN
    RETURN 0;
  END IF;
  UPDATE public.church_websites
     SET view_count = view_count + 1
   WHERE id = p_website_id
     AND is_published = true
   RETURNING view_count INTO v_count;
  RETURN COALESCE(v_count, 0)::INTEGER;
END;
$$;

-- ── 4. Pastoral follow-ups (visits / phone / WhatsApp logs) ──────────────────
CREATE TABLE IF NOT EXISTS public.pastoral_followups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  followup_type TEXT NOT NULL DEFAULT 'visit', -- visit | phone | whatsapp | sms | email | in_church
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'open',        -- open | done | cancelled
  follow_up_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pastoral_followups_tenant ON public.pastoral_followups (tenant_id);
CREATE INDEX IF NOT EXISTS idx_pastoral_followups_member ON public.pastoral_followups (member_id);
CREATE INDEX IF NOT EXISTS idx_pastoral_followups_status ON public.pastoral_followups (status);

ALTER TABLE public.pastoral_followups ENABLE ROW LEVEL SECURITY;

-- Leadership of the tenant can read; the member themselves can see their own.
CREATE POLICY pastoral_followups_read ON public.pastoral_followups
  FOR SELECT TO authenticated
  USING (
    auth.uid() = member_id
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'coa_employee',
          'treasurer', 'secretary', 'assistant_pastor'
        )
        AND p.tenant_id::uuid = pastoral_followups.tenant_id
    )
  );

-- Leadership writes (insert/update/delete), always tenant-scoped.
CREATE POLICY pastoral_followups_write ON public.pastoral_followups
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'coa_employee',
          'treasurer', 'secretary', 'assistant_pastor'
        )
        AND p.tenant_id::uuid = pastoral_followups.tenant_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN (
          'admin', 'pastor', 'bishop', 'leader', 'general_treasurer',
          'general_secretary', 'superadmin', 'employee', 'coa_employee',
          'treasurer', 'secretary', 'assistant_pastor'
        )
        AND p.tenant_id::uuid = pastoral_followups.tenant_id
    )
  );

-- ── 5. App events (lightweight analytics — give funnel + key actions) ────────
CREATE TABLE IF NOT EXISTS public.app_events (
  id BIGSERIAL PRIMARY KEY,
  event TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  tenant_id TEXT,
  properties JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_events_event ON public.app_events (event, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_user ON public.app_events (user_id, created_at DESC);

ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;

-- Users may insert their own events.
CREATE POLICY app_events_insert_own ON public.app_events
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Only the owner team reads analytics.
CREATE POLICY app_events_read_admin ON public.app_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'coa_employee')
    )
  );