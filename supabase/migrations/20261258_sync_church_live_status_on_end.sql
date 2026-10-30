-- ============================================================================
-- 20261247_sync_church_live_status_on_end.sql
--
-- Ensures church_live_status is automatically set to is_live=false when a stream
-- ends or is archived, and preserves synchronization with live_streams.
--
-- PREVIOUS BEHAVIOR:
--   trg_live_streams_sync_live_status only fired AFTER UPDATE OF broadcast_started_at
--   and only ever set is_live = TRUE. When a stream ended (or was expired by
--   expire_stale_live_streams), church_live_status remained is_live = TRUE indefinitely
--   unless explicitly reset by client code.
--
-- FIX:
--   Update trigger to monitor broadcast_started_at and status.
--   When status transitions to 'ended' or 'archived', check if any other live stream
--   exists for that church. If none, set is_live = false on church_live_status.
-- ============================================================================

CREATE OR REPLACE FUNCTION private.sync_church_live_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_real_church_id UUID;
  v_other_live BOOLEAN;
BEGIN
  -- Resolve the real church UUID
  SELECT c.id INTO v_real_church_id
    FROM public.churches c
   WHERE c.id = NEW.church_id OR c.tenant_id = NEW.church_id
   LIMIT 1;

  IF v_real_church_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 1) When stream transitions to ended or archived: flip is_live to FALSE
  IF NEW.status IN ('ended', 'archived') THEN
    SELECT EXISTS (
      SELECT 1 FROM public.live_streams
       WHERE (church_id = NEW.church_id OR church_id = v_real_church_id)
         AND status = 'live'
         AND id <> NEW.id
    ) INTO v_other_live;

    IF NOT v_other_live THEN
      UPDATE public.church_live_status
         SET is_live = FALSE,
             updated_at = now()
       WHERE church_id = v_real_church_id;
    END IF;

    RETURN NEW;
  END IF;

  -- 2) When media is confirmed flowing for a live broadcast: flip is_live to TRUE
  IF NEW.status = 'live' AND NEW.broadcast_started_at IS NOT NULL THEN
    INSERT INTO public.church_live_status AS c
      (church_id, is_live, title, stream_url, updated_at)
    VALUES (
      v_real_church_id,
      TRUE,
      COALESCE(NEW.title, 'Live Service'),
      -- For WHIP (WebRTC) broadcasts, preview_url (WHEP) is the only playable URL
      COALESCE(
        CASE WHEN NEW.ingest_mode = 'whip' THEN NULLIF(NEW.preview_url, '') ELSE NULL END,
        NULLIF(NEW.hls_url, ''),
        NULLIF(NEW.preview_url, '')
      ),
      now()
    )
    ON CONFLICT (church_id) DO UPDATE
      SET is_live    = TRUE,
          title      = COALESCE(EXCLUDED.title, c.title),
          stream_url = COALESCE(EXCLUDED.stream_url, c.stream_url),
          updated_at = now()
    WHERE c.church_id IS NOT NULL;
  END IF;

  RETURN NEW;
EXCEPTION WHEN undefined_table OR unique_violation OR not_null_violation THEN
  RETURN NEW; -- schema drift must not break the broadcast
END;
$$;

REVOKE ALL ON FUNCTION private.sync_church_live_status() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_live_streams_sync_live_status ON public.live_streams;
CREATE TRIGGER trg_live_streams_sync_live_status
  AFTER UPDATE OF broadcast_started_at, status ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION private.sync_church_live_status();

-- Heal any existing stale church_live_status rows where no live stream currently exists
UPDATE public.church_live_status cls
   SET is_live = FALSE,
       updated_at = now()
 WHERE cls.is_live = TRUE
   AND NOT EXISTS (
     SELECT 1 FROM public.live_streams ls
      WHERE (ls.church_id = cls.church_id)
        AND ls.status = 'live'
   );

