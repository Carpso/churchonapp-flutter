-- Marketplace tenant-scoping hardening
-- Fix: new listings must carry tenant_id and only be created by a user whose
-- profile tenant matches. Also allow vendors to delete their own items.

-- 1. Drop the overly-broad INSERT policy (auth.role() = 'authenticated' lets any
-- authenticated user post without a tenant) and the old vendor create policy.
DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can submit marketplace items" ON public.marketplace_items;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Vendors can create items" ON public.marketplace_items;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- 2. Tenant-scoped INSERT policy: vendor_id must be the caller AND the item's
-- tenant_id must match the caller's profile tenant (NULL tenant_id allowed for
-- platform-level items only via superadmin).
CREATE POLICY "Marketplace items insert tenant scoped" ON public.marketplace_items
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = vendor_id
    AND (
      tenant_id IS NULL
      OR tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    )
  );

-- 3. Vendor DELETE own items policy.
CREATE POLICY "Vendors can delete own items" ON public.marketplace_items
  FOR DELETE TO authenticated
  USING (auth.uid() = vendor_id);

-- 4. Backfill: set tenant_id on existing active items from their vendors'
-- profiles so previously-hidden listings become visible again.
UPDATE public.marketplace_items mi
SET tenant_id = p.tenant_id::uuid
FROM public.profiles p
WHERE mi.vendor_id = p.id
  AND mi.tenant_id IS NULL
  AND p.tenant_id IS NOT NULL;
