-- ============================================================================
-- Stream credentials: allow the worship/media team to run its own broadcast
-- ============================================================================
-- WHY
-- `get_my_stream_credentials` (20261144) is the ONLY way a client can read the
-- RTMP ingest URL and stream key, because migration 20261240 revoked column-level
-- SELECT on those credentials after 20261237 leaked them to every authenticated
-- user *and* to anon.
--
-- Its church-scoped role list was `pastor, bishop, apostle, prophet,
-- general_secretary, general_treasurer, admin, leader, department_leader`. That
-- already covered `leader`, but a worship/praise-team leader running the actual
-- service could not re-attach to their own stream after closing the app, and
-- the studio's re-attach path silently degrades to an empty OBS box without it.
--
-- ACCEPTED RISK (product decision, 2026-10-02)
-- Holding `stream_key` + `rtmp_url` allows publishing *as that church*. So this
-- widens the blast radius of a leadership account from "can watch/review" to
-- "can hijack the live broadcast". Granted deliberately so a media team can
-- operate its own service; it is scoped to the caller's OWN church, so it
-- grants nothing across tenants.
--
-- Precedent: this codebase already trusts the same two roles with elevated
-- media capability in 20260840 (worship lyrics upload, alongside
-- superadmin/pastor/bishop) and 20261208 (Klips posting).
--
-- DELIBERATELY NOT ADDED
--   `praise_team_member` - a rank-and-file choir member. That is a member role
--   in all but name; granting ingest keys to it would hand broadcast control to
--   the whole team.
--   `usher`, `assistant`, `cashier`, `driver`, `rider`, `vendor` - unrelated to
--   running a broadcast.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_stream_credentials(p_stream_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_role text;
  v_tid  text;
  v_row  public.live_streams%rowtype;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT role, tenant_id INTO v_role, v_tid FROM public.profiles WHERE id = v_uid;

  SELECT * INTO v_row FROM public.live_streams WHERE id = p_stream_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT (
    v_role IN ('superadmin', 'super_admin', 'coa_employee', 'employee')
    OR (
      v_tid IS NOT NULL
      AND v_row.church_id::text = v_tid
      AND v_role IN (
        -- church leadership
        'pastor', 'bishop', 'apostle', 'prophet', 'general_secretary',
        'general_treasurer', 'admin', 'leader', 'department_leader',
        -- worship / media team: runs the service on the ground
        'worship_leader', 'praise_team_leader'
      )
    )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authorised');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'stream_key', v_row.stream_key,
    'rtmp_url', v_row.rtmp_url,
    'hls_url', v_row.hls_url,
    'cloudflare_stream_id', v_row.cloudflare_stream_id,
    'ingest_mode', v_row.ingest_mode,
    'broadcast_started_at', v_row.broadcast_started_at,
    'status', v_row.status
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_stream_credentials(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Sanity check: the role list must not have drifted into an empty/typo'd state,
-- and the two media roles must be present exactly as the app spells them.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_def text;
BEGIN
  v_def := pg_get_functiondef('public.get_my_stream_credentials(uuid)'::regprocedure);
  IF v_def NOT LIKE '%worship_leader%' OR v_def NOT LIKE '%praise_team_leader%' THEN
    RAISE EXCEPTION 'media roles missing from get_my_stream_credentials';
  END IF;
  IF v_def NOT LIKE '%SECURITY DEFINER%' THEN
    RAISE EXCEPTION 'get_my_stream_credentials lost SECURITY DEFINER';
  END IF;
  IF v_def NOT LIKE '%praise_team_member%' THEN
    -- expected: praise_team_member must NOT be granted ingest credentials
    NULL;
  ELSE
    RAISE EXCEPTION 'praise_team_member must not be granted stream credentials';
  END IF;
END;
$$;