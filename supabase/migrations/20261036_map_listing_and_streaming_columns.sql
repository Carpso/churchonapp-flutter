-- 20261036: Map listing empty (churches/bookshops) + streaming viewer fixes
-- Root cause: client selects columns that do not exist on the live DB
-- (schema drift across two bookshops migrations + partial deploy), so the
-- whole query 42703s and the map/list comes back empty.

-- Churches: every column getAllTenants / getNearbyChurches selects.
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS primary_color TEXT DEFAULT '#FFD700',
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'Zambia',
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ;

-- Bookshops: union of both historical schemas + listing columns.
-- (First schema had address/country/is_verified; second had location/contact/
-- is_active; listing selects latitude/longitude/is_active/subscription/etc.)
ALTER TABLE public.bookshops
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'Zambia',
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS primary_color TEXT DEFAULT '#8B5CF6',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'silver',
  ADD COLUMN IF NOT EXISTS onboarding_fee_paid BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS owner_id UUID,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS contact TEXT,
  ADD COLUMN IF NOT EXISTS location TEXT;

-- live_streams: columns the unified service inserts on go-live.
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS rtmp_url TEXT,
  ADD COLUMN IF NOT EXISTS stream_key TEXT,
  ADD COLUMN IF NOT EXISTS hls_url TEXT,
  ADD COLUMN IF NOT EXISTS dash_url TEXT,
  ADD COLUMN IF NOT EXISTS preview_url TEXT,
  ADD COLUMN IF NOT EXISTS whip_url TEXT,
  ADD COLUMN IF NOT EXISTS last_heartbeat TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS storage_bytes BIGINT DEFAULT 0;

-- Viewer path must stay readable: keep the permissive select.
DROP POLICY IF EXISTS "live_streams_select" ON public.live_streams;
CREATE POLICY "live_streams_select" ON public.live_streams FOR SELECT USING (true);
