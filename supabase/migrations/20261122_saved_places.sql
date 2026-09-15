-- Server-side saved places / pins for Carpso Ride + last-mile delivery.
--
-- Before: `SavedPlacesService` kept places ONLY in SharedPreferences
-- (`carpso_saved_places`) — device-local, so a rider's saved pickup/dropoff
-- (and any dropped pin) could not be reused for a delivery order, by a
-- courier, or on another device. This table makes them first-class,
-- tenant-scoped, geo-coded map data.

CREATE TABLE IF NOT EXISTS public.saved_places (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  tenant_id   uuid,
  label       text NOT NULL,
  address     text NOT NULL DEFAULT '',
  lat         double precision,
  lng         double precision,
  -- 'saved'    = personal place (Home / Work / …)
  -- 'landmark' = tenant-shared point of interest (church, depot, pickup point)
  -- 'pin'      = a location dropped on the map
  place_type  text NOT NULL DEFAULT 'saved',
  is_public   boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_saved_places_user   ON public.saved_places(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_places_tenant ON public.saved_places(tenant_id, is_public);
CREATE INDEX IF NOT EXISTS idx_saved_places_geo    ON public.saved_places(lat, lng);

ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;

-- Owner: full CRUD on their own places.
DROP POLICY IF EXISTS "saved_places_owner_select" ON public.saved_places;
CREATE POLICY "saved_places_owner_select" ON public.saved_places
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "saved_places_owner_insert" ON public.saved_places;
CREATE POLICY "saved_places_owner_insert" ON public.saved_places
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "saved_places_owner_update" ON public.saved_places;
CREATE POLICY "saved_places_owner_update" ON public.saved_places
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "saved_places_owner_delete" ON public.saved_places;
CREATE POLICY "saved_places_owner_delete" ON public.saved_places
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Tenant members: may READ public landmarks belonging to their own tenant
-- (so last-mile couriers can pick "Main Gate", "Depot", etc.).
DROP POLICY IF EXISTS "saved_places_tenant_landmarks" ON public.saved_places;
CREATE POLICY "saved_places_tenant_landmarks" ON public.saved_places
  FOR SELECT TO authenticated USING (
    is_public
    AND tenant_id IS NOT NULL
    AND tenant_id::text = public.get_my_tenant_id()::text
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_places TO authenticated;
REVOKE ALL ON public.saved_places FROM anon;

-- Keep updated_at fresh.
CREATE OR REPLACE FUNCTION public.touch_saved_places_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_saved_places_updated_at ON public.saved_places;
CREATE TRIGGER trg_saved_places_updated_at
  BEFORE UPDATE ON public.saved_places
  FOR EACH ROW EXECUTE FUNCTION public.touch_saved_places_updated_at();
