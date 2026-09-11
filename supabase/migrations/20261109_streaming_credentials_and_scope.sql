-- 20261109: never expose Cloudflare ingest credentials to viewers.

ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS cloudflare_video_id TEXT;

DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='live_streams' AND cmd='SELECT' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.live_streams', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "live_streams_public_safe_read" ON public.live_streams
  FOR SELECT TO anon, authenticated
  USING (status IN ('scheduled','live','ended','archived'));

-- Replace table-level SELECT with an allowlist. Edge Functions using the
-- service role retain full access to stream_key/whip_url/rtmp_url.
REVOKE SELECT ON public.live_streams FROM anon, authenticated;
GRANT SELECT (
  id, church_id, title, description, status, streaming_backend,
  scheduled_at, started_at, ended_at, hls_url, dash_url, preview_url,
  viewer_count, created_at, cloudflare_video_id
) ON public.live_streams TO anon, authenticated;

-- Stream config writes are leadership-only, not any tenant member.
DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='church_stream_config' AND cmd IN ('INSERT','UPDATE','DELETE') LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.church_stream_config', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "church_stream_config_leadership_write" ON public.church_stream_config
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id=auth.uid() AND p.tenant_id::text=church_stream_config.church_id::text
      AND p.role IN ('admin','pastor','bishop','apostle','prophet','general_secretary','leader','department_leader','superadmin','coa_employee')
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id=auth.uid() AND p.tenant_id::text=church_stream_config.church_id::text
      AND p.role IN ('admin','pastor','bishop','apostle','prophet','general_secretary','leader','department_leader','superadmin','coa_employee')
  ));
