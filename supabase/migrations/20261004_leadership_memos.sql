-- =====================================================
-- 20261004 — Leadership memos (Bishop Hub secure notices)
--
-- Replaces the hardcoded single "CONFIDENTIAL: New Mission Directive" row
-- in the Bishop Hub with a real, org-scoped, bishop-authored table.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.leadership_memos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.leadership_memos ENABLE ROW LEVEL SECURITY;

-- SELECT: org leaders (church tenants inside the org), org members, or the author.
DROP POLICY IF EXISTS "memos_select_org" ON public.leadership_memos;
CREATE POLICY "memos_select_org" ON public.leadership_memos
  FOR SELECT TO authenticated
  USING (
    author_id = auth.uid()
    OR org_id IS NULL
    OR org_id IN (
      SELECT p.organization_id FROM public.profiles p WHERE p.id = auth.uid()
    )
    OR org_id IN (
      SELECT c.organization_id FROM public.churches c
      WHERE c.id IN (SELECT t.tenant_id::uuid FROM public.profiles t WHERE t.id = auth.uid())
    )
  );

-- INSERT: bishop-level roles only (bishops, apostles, COA staff).
DROP POLICY IF EXISTS "memos_insert_bishop" ON public.leadership_memos;
CREATE POLICY "memos_insert_bishop" ON public.leadership_memos
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = author_id
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('bishop', 'apostle', 'superadmin', 'coa_employee', 'employee')
    )
  );

-- UPDATE/DELETE: author only (leaders can retract their own notice).
DROP POLICY IF EXISTS "memos_update_author" ON public.leadership_memos;
CREATE POLICY "memos_update_author" ON public.leadership_memos
  FOR UPDATE TO authenticated
  USING (author_id = auth.uid());

DROP POLICY IF EXISTS "memos_delete_author" ON public.leadership_memos;
CREATE POLICY "memos_delete_author" ON public.leadership_memos
  FOR DELETE TO authenticated
  USING (author_id = auth.uid());

REVOKE ALL ON public.leadership_memos FROM anon;