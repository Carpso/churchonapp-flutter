-- ============================================================================
-- 20261245_app_release_config.sql
--
-- Makes the app able to tell users there is a new version and self-trigger the
-- update.
--
-- WHY A NEW TABLE
--   The existing `app_config` table looks like it should work, but it cannot:
--
--   * It is a generic key/value table (rows: coin_exchange_rate, trophy_config,
--     version) which merely HAPPENS to carry `latest_build` / `update_message` /
--     `force_update` columns.
--   * AppUpdateService read it with `.maybeSingle()`. `maybeSingle()` asserts at
--     most ONE row; the table has 3, so the query ALWAYS threw PGRST116 and the
--     bare `catch (_) { return; }` swallowed it. The update prompt could never
--     have fired — silently, on every launch, for every user.
--   * Even had it returned, the only `latest_build` value is 1, so
--     `1 <= currentBuild` short-circuits forever.
--
--   A purpose-built single-row table removes the ambiguity entirely.
--
-- FORCE-UPDATE MODEL
--   `min_supported_build` is the important column. A build BELOW it cannot talk
--   to current servers safely, so the prompt becomes non-dismissible. Anything
--   between min_supported and latest is optional (dismissible "Later").
--   Bumping min_supported is therefore a server-breaking-change switch.
--
-- MAINTAINED BY
--   `build_release.ps1` publishes this row automatically after a successful
--   build, so "the app self-triggers an update" requires no manual step: bump
--   pubspec, build, deploy, and every install below the new build is prompted
--   on next launch.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_release_config (
  -- Singleton. Kept as a real column rather than a partial index so the client
  -- can read it with an unambiguous `.limit(1)` and never trip maybeSingle().
  id                  BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),

  -- Build number (the +NNN in pubspec) users should move TO.
  latest_build        INTEGER NOT NULL DEFAULT 0,
  -- Human version name, e.g. "1.0.0".
  latest_version      TEXT    NOT NULL DEFAULT '1.0.0',

  -- Builds BELOW this are blocked from continuing. Bump deliberately.
  min_supported_build INTEGER NOT NULL DEFAULT 0,

  update_message      TEXT,
  release_notes       TEXT,

  -- Where "Update Now" goes. `play_url` works for Play-installed builds;
  -- `apk_url` matters because most installs today are SIDELOADED from R2, where
  -- there is no Play listing to open and the old code dead-ended on a store
  -- link that resolved to nothing.
  play_url            TEXT,
  apk_url             TEXT,
  aab_url             TEXT,

  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by          TEXT
);

COMMENT ON COLUMN public.app_release_config.min_supported_build IS
  'Installs below this build number are force-updated (non-dismissible). Bump only for server-breaking changes.';
COMMENT ON COLUMN public.app_release_config.apk_url IS
  'Direct APK for sideloaded installs. Required in practice - most users install from R2, not Play.';

ALTER TABLE public.app_release_config ENABLE ROW LEVEL SECURITY;

-- The table holds no user data, only release metadata. Public read so an
-- unauthenticated user still gets the update prompt (a signed-out user on an
-- unsupported build must be told, not left on a broken client).
DROP POLICY IF EXISTS app_release_config_public_read ON public.app_release_config;
CREATE POLICY app_release_config_public_read ON public.app_release_config
  FOR SELECT TO anon, authenticated
  USING (true);

-- Writes are service-role only (the release script + superadmin tooling).
REVOKE INSERT, UPDATE, DELETE ON public.app_release_config FROM anon, authenticated;
GRANT SELECT ON public.app_release_config TO anon, authenticated;

INSERT INTO public.app_release_config
  (id, latest_build, latest_version, min_supported_build,
   update_message, release_notes, play_url, apk_url, aab_url, updated_by)
VALUES (
  true,
  361,
  '1.0.0',
  -- Deliberately low: nothing currently requires a hard block. Raise this only
  -- when an old build genuinely cannot work against the current backend.
  300,
  'Church On App has a new version with live-streaming improvements, weather alerts and a faster map.',
  '• Tenant live services with start/end alerts
 • Weather alerts you control
 • Map growth from your own rides and navigation
 • Fixed: push notifications now deliver reliably',
  'https://play.google.com/store/apps/details?id=com.churchonapp.churchonapp',
  'https://media.churchonapp.com/builds/latest/ChurchOnApp.apk',
  'https://media.churchonapp.com/builds/latest/ChurchOnApp.aab',
  'migration 20261245'
)
ON CONFLICT (id) DO UPDATE SET
  latest_build        = EXCLUDED.latest_build,
  latest_version      = EXCLUDED.latest_version,
  min_supported_build = EXCLUDED.min_supported_build,
  update_message      = EXCLUDED.update_message,
  release_notes       = EXCLUDED.release_notes,
  play_url            = EXCLUDED.play_url,
  apk_url             = EXCLUDED.apk_url,
  aab_url             = EXCLUDED.aab_url,
  updated_at          = now(),
  updated_by          = EXCLUDED.updated_by;

-- Ops helper: point every install at a new build. Called by build_release.ps1
-- so publishing a release is enough to notify every device.
CREATE OR REPLACE FUNCTION public.publish_app_release(
  p_latest_build        INTEGER,
  p_latest_version      TEXT,
  p_min_supported_build INTEGER DEFAULT NULL,
  p_update_message      TEXT    DEFAULT NULL,
  p_release_notes       TEXT    DEFAULT NULL,
  p_play_url            TEXT    DEFAULT NULL,
  p_apk_url             TEXT    DEFAULT NULL,
  p_aab_url             TEXT    DEFAULT NULL,
  p_updated_by          TEXT    DEFAULT 'release-script'
)
RETURNS public.app_release_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- plpgsql has no `RETURN *`; the row must be captured and returned.
  v_row public.app_release_config;
BEGIN
  INSERT INTO public.app_release_config AS r
    (id, latest_build, latest_version, min_supported_build,
     update_message, release_notes, play_url, apk_url, aab_url, updated_by)
  VALUES
    (true, p_latest_build, p_latest_version,
     COALESCE(p_min_supported_build, 0),
     p_update_message, p_release_notes,
     COALESCE(p_play_url,
              'https://play.google.com/store/apps/details?id=com.churchonapp.churchonapp'),
     COALESCE(p_apk_url, 'https://media.churchonapp.com/builds/latest/ChurchOnApp.apk'),
     COALESCE(p_aab_url,  'https://media.churchonapp.com/builds/latest/ChurchOnApp.aab'),
     p_updated_by)
  ON CONFLICT (id) DO UPDATE SET
    latest_build        = EXCLUDED.latest_build,
    latest_version      = EXCLUDED.latest_version,
    -- Never silently raise or LOWER the force-update floor when omitted.
    min_supported_build = COALESCE(p_min_supported_build, r.min_supported_build),
    update_message      = COALESCE(EXCLUDED.update_message, r.update_message),
    release_notes       = COALESCE(EXCLUDED.release_notes, r.release_notes),
    play_url            = EXCLUDED.play_url,
    apk_url             = EXCLUDED.apk_url,
    aab_url             = EXCLUDED.aab_url,
    updated_at          = now(),
    updated_by          = EXCLUDED.updated_by
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_app_release(
  INTEGER, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_app_release(
  INTEGER, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;
