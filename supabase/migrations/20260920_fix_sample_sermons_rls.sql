-- 20260920: Sample sermons (church_id NULL) invisible under tenant-scoped RLS.
-- Allow NULL church_id = public sample content; keep tenant scoping otherwise.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'sermons'
      AND policyname = 'Sermons select tenant scoped'
  ) THEN
    DROP POLICY "Sermons select tenant scoped" ON public.sermons;
  END IF;
END $$;

CREATE POLICY "Sermons select tenant scoped"
ON public.sermons
FOR SELECT
TO authenticated
USING (
  church_id IS NULL
  OR church_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- Also apply to anon (landing page / public church sites show sample sermons)
CREATE POLICY "Anyone can view sample sermons"
ON public.sermons
FOR SELECT
TO anon
USING (church_id IS NULL);