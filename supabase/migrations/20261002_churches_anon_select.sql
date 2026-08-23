-- 20261002: Allow anon (not-logged-in) visitors to see verified churches.
--
-- Root cause of "website not loading tenants on map": the only SELECT
-- policies on churches were TO authenticated. Website visitors (anon role)
-- got zero rows → empty map and empty tenant list before login.
-- Bookshops already had a public SELECT policy; churches did not.

CREATE POLICY "Anyone can discover verified churches"
  ON public.churches
  FOR SELECT
  TO anon
  USING (is_verified = true);
