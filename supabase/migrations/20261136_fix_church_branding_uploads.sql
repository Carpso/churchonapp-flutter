-- ============================================================================
-- 20261136_fix_church_branding_uploads.sql
-- ROOT CAUSE of "church logo not working" + "hero background not uploading":
--
--   `church_branding_screen.dart` saves branding with
--       .update({ column: url, 'updated_at': <now> })
--   but `churches` had NO `updated_at` column (only `logo_url` / `banner_url`).
--   PostgREST therefore rejected the whole UPDATE (42703 column does not
--   exist), so BOTH the logo and the hero banner silently failed to persist —
--   the R2 upload succeeded but the row was never written.
--
-- Adding the column fixes every call site at once (this is the same shape used
-- by other tables, e.g. the quiz-events updated_at trigger).
-- ============================================================================

ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Keep it fresh automatically so callers never have to pass it.
CREATE OR REPLACE FUNCTION public.touch_churches_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_churches_updated_at ON public.churches;
CREATE TRIGGER trg_churches_updated_at
  BEFORE UPDATE ON public.churches
  FOR EACH ROW EXECUTE FUNCTION public.touch_churches_updated_at();

-- Also let tenant leaders actually UPDATE their own church row. Branding is a
-- leadership action; without an UPDATE policy the write is a silent no-op.
DROP POLICY IF EXISTS "churches_leadership_update" ON public.churches;
CREATE POLICY "churches_leadership_update"
  ON public.churches FOR UPDATE TO authenticated
  USING (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'super_admin', 'coa_employee', 'employee',
                       'bishop', 'apostle', 'prophet', 'general_secretary',
                       'general_treasurer', 'treasurer', 'pastor', 'admin', 'leader')
    )
  )
  WITH CHECK (
    tenant_id::text = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
  );
