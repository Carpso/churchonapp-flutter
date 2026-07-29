DO $$
BEGIN
  CREATE POLICY churches_insert_auth ON public.churches
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
