-- 20261033_fix_leadership_memo_leak.sql
-- Security: leadership_memos SELECT policy allowed `org_id IS NULL` rows to be
-- read by EVERY authenticated user. Local-mode bishops (no organization_id)
-- write memos with org_id = NULL, so their "secure" notices were published
-- platform-wide. Fix: drop the blanket `org_id IS NULL` visibility — a
-- null-org memo is now only visible to its own author. Org-scoped memos keep
-- the existing org-member/org-leader visibility.

DROP POLICY IF EXISTS "memos_select_org" ON public.leadership_memos;

CREATE POLICY "memos_select_org" ON public.leadership_memos
  FOR SELECT TO authenticated
  USING (
    author_id = auth.uid()
    OR org_id IN (
      SELECT p.organization_id FROM public.profiles p WHERE p.id = auth.uid()
    )
    OR org_id IN (
      SELECT c.organization_id FROM public.churches c
      WHERE c.id IN (SELECT t.tenant_id::uuid FROM public.profiles t WHERE t.id = auth.uid())
    )
  );