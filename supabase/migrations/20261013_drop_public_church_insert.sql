-- Tighten churches INSERT: drop the public-role "Anyone can register a church"
-- policy (WITH CHECK (true)). The app registers churches strictly as an
-- authenticated user (register_church_screen gates on auth.currentUser), and
-- the two authenticated policies remain:
--   * "Authenticated users can create churches"  (WITH CHECK (auth.uid() IS NOT NULL))
--   * "churches_insert_registration"             (WITH CHECK (is_verified = false))
-- This closes a path where an anonymous caller could insert a church row that
-- references an existing tenant via churches_tenant_id_fkey.

DROP POLICY IF EXISTS "Anyone can register a church" ON public.churches;