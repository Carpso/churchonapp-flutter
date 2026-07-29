-- Streaming configuration table
-- Supports both Cloudflare Stream and MediaMTX backends

CREATE TABLE IF NOT EXISTS church_stream_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE UNIQUE,
  
  -- Backend selection
  backend TEXT NOT NULL DEFAULT 'cloudflare' CHECK (backend IN ('cloudflare', 'mediamtx')),
  
  -- Cloudflare Stream config
  cloudflare_account_id TEXT,
  cloudflare_api_token TEXT,
  
  -- MediaMTX config (self-hosted VPS)
  mediamtx_host TEXT DEFAULT 'stream.churchonapp.com',
  mediamtx_secret TEXT,
  
  -- Stream settings
  auto_record BOOLEAN DEFAULT true,
  enable_chat BOOLEAN DEFAULT true,
  enable_prayer_requests BOOLEAN DEFAULT true,
  max_concurrent_streams INTEGER DEFAULT 1,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE church_stream_config ENABLE ROW LEVEL SECURITY;

-- Church admins can manage their own config
DO $ BEGIN CREATE POLICY "stream_config_church_admin" ON church_stream_config; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role IN ('superadmin', 'admin')
      AND church_id = church_stream_config.church_id
    )
  );

-- Superadmin can manage all configs
DO $ BEGIN CREATE POLICY "stream_config_superadmin" ON church_stream_config; EXCEPTION WHEN duplicate_object THEN NULL; END $;
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

-- Add streaming_backend column to live_streams if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'live_streams' AND column_name = 'streaming_backend'
  ) THEN
    ALTER TABLE live_streams ADD COLUMN streaming_backend TEXT DEFAULT 'cloudflare';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'live_streams' AND column_name = 'dash_url'
  ) THEN
    ALTER TABLE live_streams ADD COLUMN dash_url TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'live_streams' AND column_name = 'preview_url'
  ) THEN
    ALTER TABLE live_streams ADD COLUMN preview_url TEXT;
  END IF;
END $$;
