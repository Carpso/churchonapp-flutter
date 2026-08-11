-- Realtime presence: add last_seen to profiles for online status.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='last_seen') THEN
    ALTER TABLE public.profiles ADD COLUMN last_seen TIMESTAMPTZ;
  END IF;
END $$;

-- RPC: heartbeat — updates the caller's last_seen to now().
CREATE OR REPLACE FUNCTION public.heartbeat_presence()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles SET last_seen = now() WHERE id = auth.uid();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.heartbeat_presence() FROM anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_presence() TO authenticated;
