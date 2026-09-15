-- Make marketplace global: all active items visible to all authenticated users
DO $$ BEGIN
  EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DROP POLICY IF EXISTS "Anyone can view marketplace items" ON public.marketplace_items;
DROP POLICY IF EXISTS "Marketplace items select tenant scoped" ON public.marketplace_items;

CREATE POLICY "Anyone can view marketplace items"
  ON public.marketplace_items FOR SELECT TO authenticated
  USING (status = 'active');

-- Make events global: all events visible to all authenticated users
-- (inter-tenant events and regular events both shown)
DO $$ BEGIN
  EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DROP POLICY IF EXISTS "Anyone can view events" ON public.events;
DROP POLICY IF EXISTS "Events select tenant scoped" ON public.events;

CREATE POLICY "Anyone can view events"
  ON public.events FOR SELECT TO authenticated
  USING (true);
