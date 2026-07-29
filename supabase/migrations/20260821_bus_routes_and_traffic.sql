-- Seed default bus routes for Lusaka
CREATE TABLE IF NOT EXISTS public.church_bus_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  route TEXT,
  stops JSONB DEFAULT '[]',
  driver_name TEXT,
  driver_phone TEXT,
  capacity INT DEFAULT 30,
  status TEXT DEFAULT 'active',
  current_lat DOUBLE PRECISION,
  current_lng DOUBLE PRECISION,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.church_bus_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "church_bus_routes_select" ON public.church_bus_routes
  FOR SELECT USING (true);
