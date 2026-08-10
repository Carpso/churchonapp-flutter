-- Update expansion_leads RLS so COA employees + superadmins can read/manage all leads
DROP POLICY IF EXISTS "Superadmins can manage all leads" ON public.expansion_leads;
CREATE POLICY "Superadmins can manage all leads" ON public.expansion_leads
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee', 'coa_employee'))
    );

-- Allow anonymous users to create expansion leads from the website landing page
-- (only when no user_id is attached — anon cannot claim a user account)
DROP POLICY IF EXISTS "Anonymous can create leads" ON public.expansion_leads;
CREATE POLICY "Anonymous can create leads" ON public.expansion_leads
    FOR INSERT TO anon WITH CHECK (user_id IS NULL);
