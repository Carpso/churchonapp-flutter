# Changelog

## Unreleased - 2026-10-02 (Map place names, stream re-attach, self-prompting updates, media-team streaming)

**Maps - place names now draw on every map**
- The self-hosted PMTiles vector basemap is now the ONLY source. The OpenStreetMap raster fallback was removed deliberately: OSM enforces its usage policy by User-Agent and answers a non-compliant request with HTTP 200 carrying a "403 Access blocked" placeholder tile rather than an error, so the app rendered a name-less map with nothing to indicate a failure. Flutter sends an okhttp-style UA on Android and browsers forbid overriding it on the web, so that fallback could never work.
- A failed archive open now says so and offers a retry instead of quietly showing a broken map.
- Over-zoom past the archive's z15 top, so zoomed-in screens (ride tracking, drop-pin, navigation) keep roads AND labels rather than requesting tiles above the ceiling and getting nothing.
- Verified before touching the renderer: the regional and Lusaka archives both list `places`, `pois` and `roads`, and all 12 Noto fontstack ranges return 200. **Still unverified on physical hardware.**

**Streaming - closing the studio no longer kills the broadcast**
- `dispose()` no longer calls `endStream()`. OBS/RTMPS keeps publishing while the leader is elsewhere; previously backgrounding or reopening the app ended their own service and then started a second one.
- On reopen the studio looks up the church's live stream, asks Cloudflare whether an encoder is actually connected, and restores the title and state.
- OBS credentials are fetched through the `SECURITY DEFINER` RPC `get_my_stream_credentials`. They are deliberately not SELECT-granted since `20261240`, so reading them off the row returned null and left the OBS box empty - the exact complaint this fixes.
- Added the non-secret operational columns the studio needs (`ingest_mode`, `broadcast_started_at`, `last_heartbeat`, `cloudflare_stream_id`, `created_by`). All 26 verified against `information_schema`: one wrong name makes PostgREST reject the whole select and re-attach fail silently.
- A WHIP publisher's peer connection cannot survive the session, so a phone feed re-attaches as paused and must be restarted by hand rather than being handed a dead URL.
- Stream admin gains an on-air panel and a remote STOP.

**Media-team streaming (accepted risk)**
- `worship_leader` and `praise_team_leader` can now read their own church's ingest credentials (`20261246`) and manage live inputs (`cloudflare-stream`).
- **This grants broadcast-hijack capability, not just broadcast-start capability**: holding `stream_key` + `rtmp_url` allows publishing as that church. Granted deliberately so a media team can run its own service. Scoped to the caller's own church, so nothing crosses tenants.
- `praise_team_member` is deliberately excluded - rank-and-file members would otherwise get live-infrastructure control.

**Playback**
- New `MediaPlayerConfig`: `formatHint` for HLS and DASH (without it ExoPlayer treats a `.m3u8` as media and fails `MEDIA_ERR_NETWORK` / 404), `mixWithOthers: false` so a sermon stops competing with the radio stream, `allowBackgroundPlayback`, and shared buffering states.
- Projector lays video out with `Expanded`/`Flexible` so overlays cannot overflow on short or landscape screens.

**Weather**
- Defaults to the user's exact position (profile coordinates, then GPS with a permission prompt, then the existing fallback city). An explicit city is now optional rather than assumed.
- Fixed the chosen city never persisting: `SelectedCityNotifier.attachPrefs` was called by nothing, despite a comment claiming the notification bootstrap did it. Every cold start forgot the choice.

**App updates**
- `app_release_config` singleton plus a `service_role`-only `publish_app_release` RPC. Installs compare their build on Home render and on app resume; optional builds get a dismissible prompt and builds below `min_supported_build` are forced. Metadata publishes only after a successful build, so a failed build cannot point users at a missing artifact.
- Published `1.0.0+362` with APK and AAB sharing one versionCode on purpose: the release row advertises `latest_build` while `apk_url` serves the APK, so auto-incrementing between the two builds would have left sideloaded users in a permanent update loop.

### Known gaps after this release
- Map labels are unconfirmed on hardware.
- Build 362 does NOT contain the re-attach or city-persistence fixes - both landed after it. A 363 build is required.
- Source audio is 128 kbps MP3; player improvements cannot add quality. Needs a transcode or higher-bitrate master.
- Viewer counts freeze while the leader's app is closed (the per-minute rollup skips streams with a heartbeat older than 10 minutes). Cosmetic.
- One pre-existing `connect_screen_test` failure from a live PostgREST retry timer at teardown.

## Unreleased - 2026-10-01 (Push notifications fixed - every push was failing)

### Fixed - push notifications were failing 100% (invalid FCM enum)
- The FCM v1 payload sent `visibility: "VISIBILITY_PUBLIC"`. `AndroidNotification.Visibility` is an enum whose values are **bare** (`PRIVATE` / `PUBLIC` / `SECRET`), not prefixed with the enum name. FCM rejected **every** message:
  `400 INVALID_ARGUMENT — Invalid value at 'message.android.notification.visibility', "VISIBILITY_PUBLIC"`.
  No push of any type had ever been delivered. Corrected to `"PUBLIC"` (`notification_priority` likewise normalised to `PRIORITY_HIGH`).
- **The failure handler then made it permanent.** It treated `INVALID_ARGUMENT` as "this device is gone" and nulled `profiles.fcm_token`. But `INVALID_ARGUMENT` is FCM's generic *"your request was malformed"* status, so one bad field in our own payload **wiped the entire device-token registry** — after which there was nothing to send to and no recovery except each user reopening the app. Token clearing is now limited to responses that genuinely mean the token is dead: `UNREGISTERED` / `NOT_FOUND` / `SENDER_ID_MISMATCH`.
- **Diagnosability.** A failure previously returned only `{"sentCount":0,"invalid_token_cleared":1}` — indistinguishable from "one user uninstalled", which is why this went unnoticed. The response now carries the FCM HTTP status, truncated reason and whether a token was cleared (omitted on success, so clean responses are unchanged).
- **Verified with live sends to real devices:** before `sentCount:0 / invalid_token_cleared:1`; after `success:true / sentCount:1`; multi-target `3/3 delivered, 0 failures`; tokens retained across a send.

### Fixed - weather notifications were invisible on the client
- `weather` was fully wired server-side (type, channel, dispatch) but absent from every client surface: no icon, no colour, no channel label and no tap route. A weather alert would render with a default bell icon and tap to nothing. Added to `fcm_service.dart` (channel + label), `notification_service.dart` (tap -> `/weather-alerts`) and `notifications_screen.dart` (icon, colour, route).
- `dart analyze lib`: clean. Tests: 524 pass / 1 pre-existing failure (unchanged).
- 2 tokens were cleared while isolating the fault; both users re-register automatically because `syncToken()` runs on sign-in **and** on app resume.

## Unreleased - 2026-10-01 (Streaming made production-grade: tenant→members broadcast, start/end notifications, weather alerts, map growth)

### Fixed - SECURITY: broadcast ingest credentials were world-readable
- `20261237` had granted table-level `SELECT ON live_streams` to `authenticated` and `anon`, which **re-granted every column** and undid the deliberate column allowlist from `20261109`/`20261144`. PostgreSQL column grants are additive and are evaluated before RLS, so `stream_key`, `rtmp_url` and `whip_url` became readable by any signed-in user *and* by anon on every row passing `live_streams_public_safe_read` — i.e. anyone could read any church's broadcast ingest credentials.
- `20261240` rebuilds the allowlist dynamically from `information_schema` (so it can never drift, and a column added later is denied until deliberately classified), re-grants safe reads to `authenticated` + `anon`, and keeps `INSERT/UPDATE/DELETE` so a broadcaster can still persist its own row. **Verified: 0 SELECT grants on any credential column for either role.**

### Added - Stream start/end notifications (this feature did not exist at all)
- **Before this change nothing notified members about a service.** No `notifications` row on start or end, no `stream` type in the `push-notifications` Edge Function, no icon, no channel, no notification route. Members could only find a live service by already having the app open.
- `20261240` adds a **notification outbox + cron dispatcher** rather than pushing inline: `stream_notification_outbox` (unique on `stream_id`+`kind`, so re-promotion/retry/reconnect is a no-op), a trigger that appends one cheap row, and `dispatch_stream_notifications()` drained every 30s by pg_cron `stream-notify-dispatch`. A congregation of thousands cannot block the write that starts the broadcast, which is exactly what a synchronous trigger fan-out would do. Fan-out is set-based (one `INSERT ... SELECT`) with device push chunked 500 at a time; cap via `platform_settings.stream_notify_member_cap` (default 2000).
- `push-notifications` gains `stream_started` / `stream_ended` / `stream` → icon `ic_notif_event`, channel **`coa_live_stream_v2`**, registered on the client at `Importance.max` so a leader can silence everything else without ever muting "the service is starting". Both the system-notification tap handler and `notifications_screen.dart` route these to `/live-player?id=<stream_id>`.
- **Verified live:** the first dispatch created **13 real `stream_started` notifications** for Rock Of Ages Chapel (14 members, broadcaster excluded).

### Fixed - "Service is live" was announced before anything was broadcasting
- `createLiveStream()` inserts the row with `status='live'` the moment the Cloudflare live input is *created* — before any encoder has published a frame. Announcing on `status` therefore told the whole congregation a service was live when a leader had armed OBS and walked away.
- `20261241` adds **`broadcast_started_at`**, which means *media is confirmed flowing*, and the announcement keys off that instead: WHIP stamps it when the WebRTC peer connects, RTMPS/OBS stamps it when the studio's heartbeat first sees Cloudflare report the input `connected`. `church_live_status.is_live` flips at the same instant, so the home LIVE pill and the push can never disagree. A guard trigger nulls the stamp on a non-live row.
- The studio's `setLiveStatus(is_live: true)` also moved to **after** the ingest attempt; it used to run *before* the WHIP publish, so `is_live` went true for a feed that never connected.

### Fixed - WHIP broadcasts could never be recorded (and the sweep chased them forever)
- Cloudflare documents that a WHIP/WebRTC broadcast is **not recorded and emits no HLS/DASH**. Confirmed against the vendor docs. Consequences: `playable_recording_url()` returned NULL so `sync_recorded_service` deleted the sermon row, and `auto_archive_stream_recordings()` burned 6 attempts with exponential backoff on every phone broadcast before landing on `failed`.
- `20261240` adds **`ingest_mode`** (`rtmps` | `whip`), set by the studio once the ingest path actually wins, plus a trigger that marks a WHIP row `archive_status='not_applicable'` so the sweep skips it. `StreamAnalytics` now reports `ingestMode` + `hasRecording` so the UI can explain a missing replay instead of looking broken.

### Fixed - viewer count froze when the broadcaster's app was closed
- `live_streams.viewer_count` was only recomputed by the **streamer's** 15s poll or on a viewer's open/close — a viewer heartbeat never republished it, so a closed studio left a stale number on the home hero forever.
- `refresh_live_stream_viewer_counts()` (pg_cron `stream-viewer-rollup`, every minute) recomputes every live stream. It is O(number of live streams), **not** O(number of viewers), so it stays cheap at 1 church or 1000.

### Fixed - deep links that resolved to nothing
- `/live-player` only read `state.extra`, so every shared or notification link (`/live-player?id=<uuid>`) opened an empty viewer and errored — and that is precisely the link the studio QR and the new notifications hand out. It now accepts `?id/?church/?url/?title/?audio/?thumb` as well as `extra`.
- `/live-streaming` ignored `?tenant=`, so a church's own share link dropped members on a platform-wide list where their own service was one row among every other church's. New `/church/:churchId/live` + `LiveStreamingScreen(initialChurchId:)` resolves that church's broadcast, falling back to its most recent recording, then to a clear "not streaming — you'll get a notification" state.
- The studio share link and QR were a hardcoded `churchonapp.com/live-streaming`; they are now stream-specific via `DeepLinks`.
- New `DeepLinks` (`lib/core/services/deep_links.dart`) is the single owner of every shareable link. Added `/bible/verse-of-the-day/:date` (`VerseOfTheDayScreen`, date-stamped so a shared verse still shows tomorrow) and `/quiz/tournament/:tournamentId`.

### Fixed - WHEP viewers behind symmetric NAT could not watch at all
- The broadcaster fetched real TURN credentials; the **viewer** was hardcoded STUN-only. That asymmetry worked in the studio and failed in the pews — most mobile carriers and many office/WiFi networks use symmetric NAT, so the WHEP session simply never connected. `WhepPlayback` now fetches the same `turn-credentials` and degrades to STUN if that fails.

### Fixed - "Projector / Big Screen" showed no video
- The projector view rendered only text overlays and a copy-link button. It now has a real player: HLS via `video_player` (what an RTMPS broadcast produces and what scales to a congregation), falling back to the WHEP renderer for a phone-cam broadcast, with a retry state.

### Fixed - two gates that could never fire
- The weekly-minutes gate was `!config.isPaid && minutesUsed >= max`, and every church is `is_paid=true`, so the condition was permanently false and a tenant that had burned its allowance could still start another broadcast. The cap now applies to everyone.
- `storage_bytes` was only ever reset to 0, so `getStorageUsage()` always returned 0 and the storage gate was dead. `endStream()` now records a duration-based estimate for RTMPS broadcasts (0 for WHIP, which retain nothing).
- `getAnalytics()` selected `viewer_count, started_at, ended_at` but then read `status` and `streaming_backend` — both always NULL, so `isLive` was permanently `false`, `backend` was permanently `'unknown'`, and the Cloudflare-analytics branch never ran. Columns fixed; `peak_viewer_count` is now the primary peak source.

### Added - configurable weather alerts
- New `weather_alert_preferences` (per-user, **opt-in, off by default**): max/min temperature, rain probability, max wind, a service window, and **quiet hours**. A `timezone` column is required because quiet hours and the daily dedupe are meaningless in UTC.
- pg_cron `weather-alert-sweep` (twice hourly) calls the new **`weather-alerts` Edge Function**, which fetches the keyless Open-Meteo forecast, evaluates it against each user's own thresholds, respects quiet hours and the service window, and sends **at most one alert per user per local day**. The HTTP call lives in an Edge Function rather than plpgsql because pg_net only offers fire-and-forget plus a fragile synchronous collector.
- One forecast fetch per distinct coordinate, so a whole congregation sharing one venue costs a single upstream request. A forecast failure never consumes a user's single daily alert, and the day is claimed with a conditional update so two concurrent sweeps cannot both send.
- UI: `WeatherAlertSettingsScreen` (`/weather-alerts`), plus a Weather row in notification preferences.

### Added - map growth from our own usage (consent-scoped)
- `map_growth_samples` records the user's **own** movement inside Church On App: Carpso rides/deliveries, in-app navigation, and explicit place reports / saved pins. `MapGrowthService` thins trails to one point per 40 m and drops implausible coordinates before they reach the database.
- **Explicitly does not and cannot collect Yango/InDrive/Google Maps location history** — no API exposes another app's location data, and doing so without consent would be a privacy and legal violation. Growth here is our own drivers, our own riders, our own navigation and OSM enrichment.
- The table has **no client SELECT policy**: the raw trail is written by the user and readable only server-side. Clients get the aggregate `get_map_growth_heatmap()`. Retention is 180 days (`map-growth-prune`).

### Fixed - service-worker console exception
- `Exception: prepareServiceWorker took more than 4000ms to resolve. Moving on.` was Flutter's default 4s registration budget on a cold cache. New `web/flutter_bootstrap.js` raises it to 20s via `{{flutter_service_worker_version}}`, so PWA/offline behaviour is unchanged and the false alarm is gone.

### Fixed - `profiles?id=eq...` HTTP 400
- `profile_provider` used a star select, which fails with 400 whenever a migration adds a column before PostgREST's schema cache reloads. Now selects an explicit, verified column list. (`date_of_birth` is deliberately excluded — it does not exist on `profiles` and naming a missing column is itself a 400.) PostgREST schema cache reloaded.

### Fixed - test suite regressions
- `524 passing / 1 failing`, down from **12 failing**. Seven stale logistics tests asserted the **fabricated** Lusaka fixtures (`Bus #4`, `bus-1`, canned traffic/parking) that the Logistics Command rewrite deliberately removed — they now assert the real contract (empty on failure, never invented data). `universal_search_screen_test` and one `connect_screen_test` were dying on `_instance._isInitialized` (no Supabase client). `marketplace_service_test`'s fake client had no `auth`, and `radio_service_test` still asserted the **silent** `playStation` no-op that was itself the "tapping a station does nothing" bug.
- The one remaining failure (`connect_screen_test` "renders without error") is a **pre-existing harness limitation**: a real PostgREST retry timer is outstanding at teardown. Properly fixing it means making the feed injectable, i.e. a production refactor of shared code, so it is documented rather than worked around.

### Test evidence
- `supabase/tests/stream_notification_pipeline_test.sql` — 12/12 green against the real production path (triggers + dispatcher) inside a rolled-back transaction: no false announce when merely armed, announce on confirmed media, exactly the tenant's members with the broadcaster excluded, correct push channel, chunked fan-out, idempotent re-dispatch, end-of-service copy, and WHIP marked unrecordable. Writes nothing, sends nothing.
- Weather: `weather-alert-candidates` RPC resolves the user, falls back to church coordinates, and returns the correct **local** hour/date for the user's timezone; Open-Meteo live forecast confirmed for Lusaka.

### Deploy state
- Migrations `20261240`, `20261241`, `20261242`, `20261244` applied live and registered in `deploy.ps1`. Edge Functions `push-notifications` and `weather-alerts` deployed; `?action=health` returns `{"status":"ok","cron_secret_set":true,"service_role_set":true}`.
- **Not built:** APK/AAB require an explicit go-ahead. Last published artifacts are still `+351`/`+352` and predate all of the above, including the manifest-free but native-affecting changes.

## Unreleased - 2026-09-30 (Listed as a map navigation option: geo: intent + in-app /navigate screen, release v1.0.0+352)

### Added - App appears in Android's "Open with" chooser for navigation
- `android/app/src/main/AndroidManifest.xml` registers two VIEW intent filters (`geo` + `google.navigation`, DEFAULT + BROWSABLE categories) so Android's app chooser offers Church On App when a maps/navigation link is opened from a browser, WhatsApp, etc. No `autoVerify` (non-http scheme), and no self-loop (the app issues no outbound `geo:` intents).
- `lib/main.dart` handles the incoming `geo:` / `google.navigation:` deep links in `_handleDeepLink` via new `_openMapNavigation`: parses `geo:<lat>,<lng>(Label)` / `geo:<lat>,<lng>?q=...` / `google.navigation:q=...`, integer-or-decimal coordinates, rejects the null-island `geo:0,0` no-coords path, and resolves free-form addresses through `GeocodingService.forward`. Success routes to `/navigate`.
- **iOS limitation (by design)**: iOS does not allow third-party apps to intercept `geo:` (Apple Maps owns it), so on iOS the entry point remains the existing `churchonapp://navigate?lat&lng&label` scheme. No `geo` scheme was registered in `Info.plist` (hijack risk / App Store rejection) - stated openly.

### Added - Standalone turn-by-turn screen `/navigate`
- New `lib/features/transport/presentation/map_navigation_screen.dart` - a destination-driven navigation screen (NOT a change to any existing ride feature): permission + location-service gating with actionable error card, `getCurrentPosition` -> `RouteService.fetchRoute` -> `navigationProvider.start(...)`, GPS stream (`distanceFilter: 15`) feeding the snap-to-route navigation controller and the map puck, arrival detection at <= 30 m (stops nav, cancels sub, announces via `VoiceDirectionService`), `ChurchMap` with destination flag + blue puck + route path (pin/save-pin controls hidden), `NavigationBanner` (voice toggle + steps sheet) and a bottom card with loading/error/arrived/ETA states (`route.isFallback` shows a straight-line fallback note).
- Route `/navigate` registered in `app_router.dart` (parses `lat`/`lng`/`label` query params; member-level, no `hasAccess` entry needed - the default at line 545 returns true).

### Added - Release v1.0.0+351 (APK) / +352 (AAB) + R2 publish cycle
- Fresh builds after the navigation feature: APK `ChurchOnApp-1.0.0+351.apk` (234,626,961 B) + AAB `ChurchOnApp-1.0.0+352.aab` (134,599,190 B), both copied to `builds/latest/`, `builds/latest.json` manifest updated (`built_at` re-stamped), superseded `+349`/`+350` artifacts pruned (exactly 5 objects remain), all four public URLs HEAD 200 with byte-exact sizes.
- Web redeployed (`882f94af.churchonapp.pages.dev`) and byte-verified against production (`main.dart.js` 10,962,142 = local).

### Note - media.churchonapp.com edge cache of latest.json still serves stale +348
- The plain URL returns `1.0.0+348` (`cf-cache-status: HIT`, `age` > 26h) while origin (and any `?query` cache-buster) returns `+352`. A zone Cache Rule overrides the origin `max-age=14400`; available tokens (`VITE_CLOUDFLARE_API_TOKEN` = 401, `EXPO_PUBLIC_CLOUDFLARE_API_TOKEN` = valid but zero zones / no purge route, wrangler OAuth = no purge scope) cannot purge it. Self-heals at the edge TTL; consumers wanting the current manifest should append a cache-busting query param. Nothing in this repo consumes `latest.json`.

### Closed - Security pending items (TOTP MFA + FCM key rotation)
- **TOTP MFA confirmed already enabled** in the Supabase dashboard (project `daboihiudmglwhdfvsku`: MFA Enabled, TOTP Enabled, max 10 factors) - no dashboard action needed. The app flow was already complete: each signed-in user enrolls an authenticator via `/two-factor-setup` (`mfa.enroll()` → QR + secret) and verifies a code via `challengeAndVerify` at setup and at login. The earlier 422 `mfa_totp_enroll_not_enabled` was observed pre-config; the typed `TotpUnavailableException` stays as a guard for transient states.
- **FCM service-account key rotation waived by owner** ("no need to rotate") - previously flagged as pending in AGENTS.md because the key was shared in plain text during setup.


## Unreleased - 2026-09-25 (City map tiles LIVE: 6 metros z0-15 via protomaps/basemaps jar, manifest published, r2-put hardened)

### Added - City archives shipped (supersedes the z16-19 plan below)
- The plain `planetiler.jar` route failed on capability (caps z<=16) and correctness (emits OpenMapTiles, while our v4 style expects the Protomaps schema). Builds now use the **protomaps/basemaps jar** (`--osm_path --bounds --minzoom=0 --maxzoom=15`) over Geofabrik PBFs.
- 6 archives **live on `maps.churchonapp.com`** (all HEAD 200): `tiles/{lusaka,ndola,kitwe,livingstone,harare,bulawayo}-z0-15.pmtiles` (23.3/6.8/6.3/3.9/14.9/7.4 MB) + dated snapshots `tiles/<city>-z0-15/20260925.pmtiles`. These **include building footprints** (the public Protomaps planet build has none) - the base regional archive stays the fallback below z11 and outside city bboxes.
- `tiles/latest.json` manifest published (6 sources) via `refresh-maps.ps1 -SkipBuild`.
- `MAPS_EXTRA_SOURCES` (6 entries, `minZoom` 11 / `maxZoom` 15, `bbox=[south,west,north,east]`) wired in `.env`; `docs/MAPS.md` S5 rewritten for the shipped pipeline. Because the value is bundled at build time, switching it requires a web rebuild + new APK.

### Fixed - r2-put.mjs upload routing (wrong-bucket + broken flags)
- `parseArgs` returned `{positional, options}` but `main()` read `opts.copy`/`opts.bucket`/`opts.head` flat, so `--copy`/`--head` silently fell into put mode. Options are now flattened.
- Bucket resolution is `opts.bucket || R2_BUCKET || 'church-on-app-maps'` - a sibling project's `VITE_R2_BUCKET_NAME=choa-sermons-vault` had redirected all 6 city uploads to the media bucket (they were live behind `media.churchonapp.com`, 404 on `maps.*`). Re-published to the correct bucket after the fix.

### Fixed - build-city-tiles.ps1 repairs
- File restored from a botched in-place edit (duplicated content, glued `#Requires`), parse-clean. PS 5.1 `ConvertTo-Json` threw `Argument types do not match` on the report array - replaced with a manual JSON serializer. Extras block reordered (`$byId`/`$extra` defined before use - it previously ran against `$null` and silently emitted nothing). `Get-BboxCsv` reorders metro bboxes to planetiler's `west,south,east,north` (metros.json is `[south,west,north,east]`).

## Unreleased - 2026-09-24 (Push notifications fixed, per-stream live chat, single-stream enforcement, building-level map pipeline)

### Fixed - Push notifications never rang (ROOT CAUSE)
- `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT` were never set in the Supabase Edge Function environment, so every push silently failed. Now set and verified by a permanent secret-free probe (`GET .../push-notifications?health=fcm` -> `fcm_project_id_set:true, fcm_service_account_set:true, service_account_parses:true, project_ids_match:true`). Complements the earlier fix converting FCM v1 payloads from camelCase (silently ignored) to snake_case.

### Fixed - Livestream chats were shared between streams (ROOT CAUSE)
- Chat was keyed on `tenant_id` (one chat per **church**) with no `stream_id` column, so **messages from an ended stream kept appearing in every new stream's chat**. Migration `20261233` adds `stream_id` (FK + backfill + index `(stream_id, created_at)`), replaces blanket `USING(true)`/`WITH CHECK(true)` RLS with stream/church-scoped policies, and adds the table to realtime. Client now subscribes filtered by `.eq('stream_id', …)`, clears on stream change, and disables input with "This stream has ended" for ended/archived/replay streams.

### Fixed - Only one live stream per church
- Migration `20261231`: heals existing duplicates, adds a partial unique index `(church_id) WHERE status='live'`, RPCs `start_stream_guard` / `stop_other_streams` / `get_active_stream_for_church`. Starting a stream while another is live prompts **STOP & START / CANCEL**.

### Fixed - Viewers actually see WHIP broadcasts
- Cloudflare emits no HLS/DASH for a WebRTC/WHIP ingest (the live-input manifest returns HTTP 204 after broadcast). Viewers now play via **WHEP** (`WhepPlayback`, flutter_webrtc) with a bounded "waiting for broadcast" poll; `cloudflare-stream` exposes `whep` + authoritative `hls`/`dash`/`preview` per input.

### Added - City map pipeline for rentable map platform (initial z16-19 planetiler plan - superseded by the 2026-09-25 entry above)
- Protomaps public plan is **maxzoom 15 with no buildings**, so building-level detail needs self-hosted **planetiler** builds over OpenStreetMap. New `scripts/map/`: `metros.json` (Zambia/Zimbabwe/Malawi/Mozambique + Lusaka, Ndola, Kitwe, Livingstone, Harare, Bulawayo bboxes), `r2-put.mjs` (S3 SigV4 upload - required because wrangler crashes on large files and the dashboard caps at 300 MB), `build-city-tiles.ps1/.sh` (PBF -> planetiler z13-19 -> R2 `tiles/<name>.pmtiles` -> paste-ready `MAPS_EXTRA_SOURCES=` line), `refresh-maps.ps1/.sh` (dated snapshots + `tiles/latest.json` manifest + scheduled refresh, because OSM changes daily).
- App: new `map_sources.dart` + `church_map.dart` bbox/zoom auto-switching - region PMTiles (z0-15) normally, city z16-19 file when the camera is inside a metro at zoom >= 16; smallest-bbox-wins, silent fallback to base, per-source `maximumZoom`. Driven by **`MAPS_EXTRA_SOURCES`** (JSON in `.env`) so new cities and new apps (Carpso Ride) need no code changes.
- Hosting/rental architecture documented in `docs/MAPS.md`: **R2 = tile data** (cheap, egress-free), **Cloudflare Workers = metered API gateway with per-tenant keys/usage/billing (the rentable product)**, **routing (OSRM/Valhalla) + geocoding (Photon) = Cloudflare Containers or a small VM** (R2 cannot run compute). No free global live-traffic feed exists - paid providers or crowd-sourced driver data.

### Fixed - Ticketing deep-link gaps resolved
- `/ticket/:id`, `/events/:id/tickets` and `/events/:id/manage-tickets` verified registered + gated (leadership-only on manage-tickets), with thin by-id fetch screens (loading / not-found / success) so QR, share and push links resolve without an `extra` payload. Web SPA fallback `/* -> /index.html` confirmed to cover them.
- Push payloads of type `ticket`/`event_ticket` now navigate to `/ticket/:id` (previously dead-ended: no switch case existed).

### Housekeeping
- Full-Africa z15 extract from `build.protomaps.com` failed 5x from this machine (HTTP/2 PROTOCOL_ERROR, TCP timeouts, throttling) and old daily builds 404 - **run multi-GB extracts on a cloud VM next to the data and push straight to R2**. Garbage cleaned (D: 174 GB free).
- Releases: APK **v1.0.0+345** (221.6 MB) / AAB **v1.0.0+346** (127 MB), superseded builds pruned; then a fresh clean build after this session's chat/map/ticketing work: **APK v1.0.0+347 (223.0 MB) / AAB v1.0.0+348 (127.6 MB)** on R2 with `latest.json` updated. Web redeployed (196034fc.churchonapp.pages.dev).


## Unreleased — 2026-09-14 (Home white-screen root cause, broken images, sermon playback, Cloudflare VOD)

### Fixed — Home tab "blank white block under Latest Sermon" (ROOT CAUSE)
- **`ErrorWidget.builder` was returning a full-screen `MaterialApp` + `Scaffold`** (`CustomErrorBoundary`). Because `ErrorWidget.builder` substitutes an *arbitrary* failing widget — usually a small child inside the home `SliverList` — laying a full-screen Scaffold out inside a sliver child **broke the whole viewport** and painted a blank white block under the first section that failed. This is why the sections were only visible while scrolling fast and "vanished" when scrolling stopped.
- Fix: `ErrorWidget.builder` now returns a new **bounded** `InlineErrorTile` (`lib/core/widgets/error_boundary.dart`). `CustomErrorBoundary` is reserved for genuine ROOT-level failures. New PERMANENT RULE recorded in AGENTS.md.

### Fixed — Home "Marketplace Picks" flashing/vanish (ROOT CAUSE)
- `productsProvider` was a `FutureProvider.family` keyed by a **`Map`**, which has no value equality — so every rebuild created a NEW family instance (`loading` → resolve → rebuild → refetch…), an endless reload loop that made the section flash/vanish and destabilised its neighbours.
- Fix: the family key is now a value-equal **Dart record** (`ProductFilter`), call site `productsProvider((category: 'all', marketType: null))`. New PERMANENT RULE recorded in AGENTS.md.

### Fixed — ALL broken images (avatars, social, sermon thumbnails)
- `R2Service.resolveReadUrl` tested `url.startsWith('media.churchonapp.com/')`, but stored URLs are `https://media.churchonapp.com/...`, so the check **always failed** → R2 URLs were never signed → private-bucket **403** → images broke app-wide. Now matches with **and** without the `https://` prefix.

### Fixed — Home feed sections never populated
- **Marketplace Picks**: SELECT policy was tenant-scoped; now global (`status='active'`) and the provider fetches globally.
- **Events**: RLS now global and `HomeEventTimeline` falls back to the 3 most recent **past** events ("Recent Events") when nothing is upcoming.
- **Writers / Kingdom News**: `kingdom_news` was missing from the `supabase_realtime` publication (realtime `.stream()` emitted nothing despite 10 published rows). Added it (+`sermons`) with `REPLICA IDENTITY FULL`.
- **Global News**: rss2json was rate-limited with no cache → `[]`. Now falls back to raw RSS via CORS proxy (regex-parsed) → last-good cache → curated static links.

### Fixed — Pull-to-refresh flicker
- Home `onRefresh` no longer `ref.invalidate(profileProvider)`. Added `ProfileNotifier.refresh()` (re-fetch in place) and `build()` watches only the tenant **id**, so a refreshed `Tenant` instance no longer resets the profile to `loading` and flashes the header.

### Added / Fixed — Sermon playback, upload & VOD quality
- **YouTube playback**: 70/78 sermons were YouTube URLs that `video_player` cannot play. Added `youtube_player_iframe` + `youTubeVideoIdFromUrl()`; YouTube sources now use an embedded player (fullscreen supported).
- **Audio sermons**: new AUDIO media type in Media Manager (`file_picker`, bytes-based) writing `sermons.audio_url`; the player gained a dedicated `just_audio` audio stage (artwork, seek, ±10 s, play/pause).
- **UPCI sample sermons** (`20261118`): replaced fake/dead sample rows (non-existent YouTube ids + rickroll) with 12 real, oEmbed-verified UPCI sermon videos.
- **Viewership**: `viewer_count` was never incremented. Added `sermon_views` + `record_sermon_view(uuid)` RPC (dedup 1/user/6 h) and the player records a view on open.
- **VOD → Cloudflare Stream**: `cloudflare-stream` gained `create_upload_url` (Direct Creator Upload) + `get_video`; new `VodUploadService` uploads and stores adaptive-HLS playback + auto thumbnail.
- **R2 master archive**: sermons are *also* written to R2 (`archive_url`) as the cheap master copy — CF Stream is only the playback layer, so the source media is always owned and re-encodable elsewhere.

### Fixed — HLS on web (Chrome/Firefox)
- Bundled **self-hosted `web/hls.min.js`** (satisfies the `'self'` CSP) + `video_player_web_hls`, so Cloudflare Stream live + VOD HLS now plays in the browser (previously Safari-only).

### Removed — Legacy MediaMTX backend
- No `church_stream_config` row selected it (31/31 `cloudflare`) and no server was ever deployed. Removed the enum value, `_createMediaMTXStream`, `mediamtxHost/Secret`, the admin backend selector, the `stream.churchonapp.com` hardcoded fallbacks, and `Env.liveStreamUrl`. **Cloudflare Stream is the single streaming backend.**

### Fixed — Live stream viewer & Kael contrast
- `LiveStreamScreen` now validates the stream URL (rejects empty/`/null/`/non-http), catches init errors, and shows a "Stream unavailable" + RETRY state instead of crashing. The stale `.../null/index.m3u8` row was closed.
- Kael chat: user bubble is now brand-yellow with `Colors.black87` text; suggestion chips use a dark translucent fill with white text (both were unreadable).

## Unreleased — 2026-09-08 (Cross-References, Parallel Reader, Streaming Consolidation)

### Added — Bible cross-references (finally real)
- **Root cause fixed**: `cross_references` was an empty shell — SELECT-only policy, no unique index, source-direction-only fetch, curated links bookmarked non-canonical book names (`Psalm` vs `Psalms`).
- **Migration `20260908_fix_cross_references_parallel_streaming.sql` (deployed)**: seeds ~68 curated cross-reference pairs (harmony `parallel`, OT→NT `prophecy`, classic `thematic` — incl. the 59 app-side `kLinkedScripture` links), unique index `ux_cross_references_pair`, authenticated INSERT policy, and reverse-row backfill so *either* side of a pair surfaces its counterpart.
- **`BibleVerseService.fetchCrossReferences` is now bidirectional**: selects both `source_book` + `target_book` embeds, `.or()` matches source OR target, reverse rows render the counterpart correctly.
- **Kael-AI fallback generator** (`generateCrossReferences`): when no DB refs exist the verse sheet asks Kael (`cross_ref` action), parses `BibleRef: Book C:V` lines, persists them idempotently via the new unique index + INSERT policy.
- **Related-passages canonical names**: `linked_scripture_data.dart` `_canonicalBookNames` (`Psalm→Psalms`) — the 59 curated RELATED PASSAGES links now surface and navigate on canonical book names.

### Added — Parallel Bible reader
- New `ParallelBibleScreen`: chapter-level comparison across 11 resolvable translations (KJV/WEB/ASV/BBE/YLT/DRA/Noyes/Tyndale/Webster/UKJV/MKJV), KJV base verse list, per-verse per-translation rows, FilterChip translation toggles (min 1 kept), working chapter-picker grid capped at the book's real chapter count.
- Route `/bible/:book/:chapter/parallel` registered; `columns` AppBar entry in the reader + "Open Parallel Reader" button in the verse sheet.
- Verse-sheet PARALLEL TRANSLATIONS widened from hardcoded `['kjv','web']` to `['kjv','web','asv','bbe','ylt']` (canResolve-filtered).

### Fixed — Streaming consolidated on Cloudflare
- `stream_admin_screen.dart` OBS ("Start with OBS") + schedule flows no longer use the legacy MediaMTX hardcoded path (`LiveStreamService.createStream` → `stream.churchonapp.com`). Both now call `UnifiedStreamService.createLiveStream` → real Cloudflare live input, and show a copyable RTMP URL + stream key dialog (OBS credentials). Studio path already used Cloudflare.
- Usage meter reads the unified service (single gate source); removed dead `liveStreamService`/`subscriptionService` usages.
- `live_streams.status` CHECK widened to include `'archived'` (cleanup inserts were failing 23514).

### Builds
- Fresh `flutter clean` + `pub get` → APK **v1.0.0+305** 212.7 MB (`build/app/outputs/flutter-apk/app-release.apk`, assembleRelease 1490 s) → AAB **v1.0.0+306** 123.8 MB (`build/app/outputs/bundle/release/app-release.aab`, bundleRelease 281 s).
- `flutter analyze`: **0 errors, 0 warnings** (2 pre-existing infos in tests). Key-flow smoke 5/5.

## Unreleased — 2026-09-06 (Payments, Dashboards, Profile)

**Full payment system repaired — documented in [PAYMENTS.md](PAYMENTS.md).**

### Fixed — Money movement
- **`lipila-webhook` was returning 502** (crashing before its handler ran), so no
  Lipila delivery was ever processed. Rewritten: dual auth (`?secret=` callback
  param OR Standard Webhooks HMAC), `referenceId`-first reference resolution,
  disbursement confirmations acked without creating a `coa_payments` row, and
  every delivery audited.
- **Audit logging was silently broken** — it wrote `changes`/`user_agent`
  columns that don't exist (`audit_logs` uses `details`), which is why zero
  webhook audit rows ever existed.
- **`profiles` has no `phone` column** (only `phone_number`) — every payout
  recipient lookup errored silently and returned null, breaking giving, ride,
  delivery and order payouts.
- **Treasurer-only recipients** — 21 of 30 churches have no treasurer phone and
  their giving hard-failed. New server-side chain: designated tithe leader →
  elected tithe role → `treasurer_phone` → `contact_phone` → `pastor_phone` →
  any leadership `phone_number` → **wait and retry (never failed, never lost)**.
- `lipila-collect` now writes Lipila-verified `settled` state + runs settlement
  on status polls (a lost webhook can no longer strand a payout), uses
  `check-status?referenceId=` as the primary status endpoint, and ships
  `?secret=` on the callback URL.
- Tithes honour the recipient the giver picks (Pastor / Bishop / Treasurer) via
  `payout_tasks.recipient_role`.
- Church auto-payout RPCs use the same chain (`church_recipient_phone()`).

### Fixed — Admin & config
- **Platform subscription rates now apply on save** — `remoteConfigProvider` +
  `platformSettingsProvider` are invalidated (RemoteConfig caches once per
  launch); blank-key/blank-value wipes prevented; non-numeric input rejected.
- **COA treasury MoMo number** — missions donations used the compiled-in
  `Env.coaTreasuryPhone`; they now use `platform_settings.coa_treasury_phone`
  (normalised to `260…`) with the env value as fallback only.

### Fixed — Dashboards
- **Driver dashboard** was fully broken: selected `profiles.avg_rating` /
  `driver_status` (neither existed), `ride_bookings` (no such table) and
  `deliveries.fee` (no such column). Now uses `get_user_avg_rating`,
  `ride_requests` and `delivery_requests`. Added `profiles.driver_status`.
- **Rider dashboard** queried `ride_bookings` → now `ride_requests`.
- **Writer dashboard** queried `news_articles` and `marketplace_products`
  (neither exists) → now `kingdom_news` (where the writer studio publishes) and
  real sales from `order_items`. `publishArticle` now sets `status='published'`.
- **Bookshop dashboard** queried `order_items.status` (doesn't exist) → units
  sold now filtered by the parent order status on `orders`.
- **Vendor dashboard** — Edit opens `PostProductScreen` in edit mode (was a
  "coming soon" toast), Edit Shop opens account settings, product images use
  `AppImage` instead of `via.placeholder.com`.

### Fixed — Profile tab (audited)
- All 33 navigation targets verified to resolve; no missing DB columns; role
  gating correct; activity/faith cards use real data. Removed unreachable
  `_showComingSoon` helper.

### Fixed — Kael & Connect
- Kael suggestion templates now show whenever the thread is empty (they were
  gated on `!snapshot.hasData`, but the stream emits an empty first frame).
- Klips: For You/Latest actually reorders; Amen/comment counts use atomic RPCs;
  comments sheet loads real `klip_comments`; Save persists to `saved_klips`.
- Feed: likes/comments now sync `social_posts` counters atomically.
- Communities: counts refresh after join/leave.

### Tests
- **Full suite green: 484 / 484** (was 477/7). Fixed stale tests for
  `admin_service` (role `inFilter`), `bible_verse_service` (VOTD from
  `bible_verses`; `postDailyVerse` is an intentional no-op) and
  `live_stream_service` (demo/placeholder streams deliberately removed).

---

## v1.0.0+296 — 2026-08-30 (Dashboards)

### Pastor Dashboard (professionalised)
- **Real "Sermons This Month"** — counts the `sermons` table (was `klips` short-videos); guarded fallback
- **Real average attendance** — total check-ins ÷ distinct service-days (was MTD raw count)
- **Engagement snapshot** — Visitors MTD, Salvations MTD, Follow-ups due (from `service_reports` + `pastoral_followups`)
- **Latest Service Report card** — attendance/offering/visitors/salvations of the newest report, tap → Service Reports

### Bishop / Apostle / Admin dashboards (professionalised)
- **Bishop Dashboard network attendance fixed** — sum of per-branch `attendance_mtd` snapshots (was wrongly `stats['members']`)
- **Presbytery drilldown fixed** — presbytery children now resolve their real branch snapshot (was null → zeroed stats)
- **Apostle Dashboard "Active Missions" fixed** — real `missions` (org RPC / table) instead of cargo `deliveries`
- **Leadership memos (real)** — new `leadership_memos` table (migration `20261004`, RLS org-scoped, bishop-authored), Bishop Hub streams them + **New Memo** composer (replaces hardcoded static row)
- **Link New Branch works** — Bishop Hub reuses the functional `LinkChurchSheet` (was a dead instructions dialog)
- **Admin Hub stat grid de-hardcoded** — removed fake 4,250 members / +12.5% growth / 1,205 live viewers; now real member counts + member-growth % + live-stream count
- **Church Auto-Payout screen role-guarded** — internal superadmin/coa_employee gate (was reachable by direct navigation)

---

## v1.0.0+296 — 2026-08-30

### New
- **Kael AI professional assistant** — conversation memory guidance in the system prompt, 20-message history sent to the model, auto-titled sessions ("New Chat" → first question), suggested prompt chips on first open, and a **New chat** action in the Kael chat screen
- **Kael real matchmaking opponent** — the "Kael AI steps in" PvP opponent now pre-computes its answers in ONE batched `quiz_answers` HF inference call (parsed JSON plan) instead of a random 65% coin-flip; falls back to simulation only if the call fails
- **Kael rate-limit retry UI** — Ask-a-Friend lifeline no longer burns budget on 429s (retry snackbar) and the results "Kael explains" sheet shows a friendly rate-limit message with a Retry button
- **PvP invite cron sweep** — `expire_all_stale_pvp_invites()` global sweep scheduled via pg_cron every 15 min (migration `20261003`); orphaned invites now expire + refund inviters even when neither player opens the app
- **Quick actions rebalanced** — Bible Study removed (already on the church hero card); added **Fasting**, **Life**, **Prayer Requests** (`/prayer-wall`) and **Testimonies** (`/testimonies`)
- **PvP invite watcher** — inviters auto-enter the arena the instant their friend accepts (fix: inviter previously never saw the game start); accepted-challenge push notification + `/quiz/invite/<id>` deep link; live status chips (PENDING/ACCEPTED/WON/LOST + score) and a SENT audit trail
- **Ask-a-Friend lifeline** — renamed from Ask-Pastor (friendly Bible-study-friend persona + icon)

### Fixed
- **Comments appear instantly** — optimistic comment insert (no profile-fetch delay before render), background enrichment, comment-count refresh
- **Prayer wall & testimonies avatars** — profile photo first, then email/Google photo fallback; live enrichment for old rows missing snapshots
- **Verse of the Day double marking** — redundant translation label suppressed when the preferred translation equals the auto KJV text; share copies the displayed text
- **Home top bar** — weather circle 56→48px + 6px gap so the more button never squashes on narrow screens
- **News white audit on home** — section hidden entirely when both feeds are empty; newspaper icon placeholder replaces blank white image boxes
- **Notifications route correctly** — full type→route map (pvp invite/result/match, chat, post, event, sermon, job, ride, order, wallet…), awaited read-marking
- **Head-to-head results UI** — premium YOU vs OPPONENT cards with avatars, church, wager badge, winner crown, verified scores in arena finish screen and results screen

## v1.0.0+277 — 2026-08-18

### New
- **KYC works on web** — `KycService` is now bytes-based (`submitDocumentBytes`/`submitSelfieBytes` + `EncryptionService.encryptBytes`); ID + selfie upload works identically on churchonapp.com and mobile
- **Spiritual Momentum forecast** rewritten with real logic (streaks, verse notes, daily challenges, attendance; 40/40/20 weighting + week-over-week velocity) — no more fake growth
- **Flyer Studio** can render a PNG, share it (share_plus), and POST it straight to Connect
- **Media Manager** routes uploads to real tables (klips, sermons, marketplace → R2 URL)
- **Member Live Heatmap** + **Prophetic Surveillance heatmap** now use real church/user location data

### Fixed
- **Livestream 500** — studio rebuilt on `UnifiedStreamService` with real Cloudflare live input + WHIP ingest; `whip_offer` Edge Function relay now POSTs SDP to the live input's `webRTC.url` (the api.cloudflare.com `/whip` endpoint doesn't exist)
- **Login redirect loop** (go_router pushReplacement + session flag)
- **Bookshop checkout crash** (missing `orders` table fixed)
- **Logistics Command** rewritten on the real `church_buses` table (tenant-scoped, live/offline detection)
- **Financial Stewardship report** de-faked (real month, no fake "VPS blockchain" badge/delay); **Export Data** all 10 types map to real tables
- **Schedule save RLS** (migration 20260916), **SOS manager** tenant name + external `tel:` + coa_employee RLS (20260917)
- **Church logo upload on web** (bytes → uploadBytes)
- **CI test gate** — `key_flows_smoke_test.dart` wrapped in `ProviderScope` (l10n regression)

### Data
- Duplicate Rock Of Ages tenant merged into the verified church (11 child rows repointed, backup kept in `_backup_dup_tenant_merge`); junk "Kabs" tenants deleted

### Infrastructure
- `flutter analyze`: **0 issues**
- Builds: AAB 121.8 MB + APK 210.0 MB (`v1.0.0+277`)

## v1.0.0+224 — 2026-07-29

### New
- AI Personalised Growth Forecast moved from Home to **Profile tab** (Faith Metrics section)
- App icons generated (adaptive icon via flutter_launcher_icons)

### Fixed
- **Social posts**: Users without display name now fall back to "Member" instead of blank
- **Recommendation carousel**: Navigation to events/prayer-wall/marketplace no longer crashes
- **Bible quiz**: Black screen after quiz completion fixed (Navigator.pop root navigator issue)
- **Kael AI chat**: ByteStream parsing fixed for AI responses
- **Email login**: Crash on successful sign-in fixed (UUID 'unknown' → null-safe login_history inserts)
- **Home screen**: Top nav bar overlap between church name and weather/bell icons resolved
- **AI Momentum badge**: Text overflow on momentum label fixed
- **Driver onboarding**: Phone column reference corrected; number plate now uppercase-enforced
- **Phone column**: 6 files updated to use correct column name across admin/service screens

### Changed
- Kingdom-prefixed features renamed (25+ files): KingdomLifeHub→LifeHub, KingdomNews→News, KingdomRadio→Radio, KingdomEvents→EventsList, KingdomMap→Map
- Events quick action on home screen now navigates to EventsScreen

### Performance
- Removed deprecated `SystemUiMode.edgeToEdge` API (Google Play compliance)
- Bitmap downsampling (`memCacheWidth`/`memCacheHeight`) added to 18+ CachedNetworkImage usages
- R8 full mode verified active (minify + shrink resources on)

### Infrastructure
- Full git recovery: 710 files committed (161K insertions), pushed to origin/main
- .gitignore updated with key.properties, temp files, build artifacts
- `flutter analyze`: **0 issues**
- Build: APK + AAB v1.0.0+224 (AAB 116 MB)

## 2026-09-19 — Maps, navigation, dashboards, streaming, stories, Kael, notifications (v1.0.0+331/+332)

**Maps**
- Southern Africa z15 PMTiles (ZM+ZW+MW+MZ) cut from the Protomaps planet and published to `https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles` (CORS `*`); old `zambia`/`zimbabwe` tiles deleted.
- POI/business layer (Overpass nearby search + basemap POI symbols) and crowd-sourced traffic (own driver speed heartbeats → ~200 m anonymised segments).
- >300 MB R2 uploads must use the **S3 API** (dashboard caps at 300 MB; wrangler crashes on Windows with large files).

**Navigation**
- Real turn-by-turn: OSRM `steps`+`annotations`, typed `RouteStep`s, snap-to-route controller, next-maneuver banner with live countdown + ETA, off-route auto-reroute, spoken maneuvers at ~400/150 m and at the turn, persistent mute, route-steps sheet.

**Dashboards**
- Bishop = organisation oversight with real RPC rollups and charts; Pastor = single branch. Duplicate tiles removed; duplicate "Secure Leadership Memos" fixed; bishops no longer routed to the basic admin hub.

**Streaming**
- R2 archive before input teardown; in-app replay of `archive_url` with LIVE→REPLAY; provider-neutral tenant config; paid quality 360p→720p; `church_live_status` upsert (fixes 23505); WHIP SDP `v=0` fix.
- "Unavailable/offline/invalid link" regression fixed via automatic `refresh_live_input` repair + auto-retry + state-aware copy. Real viewer count, live verse overlays, speaker details + editable caption, marquee ticker, projector/big-screen, QR share, cast + encoder/drone panels. Live chat contrast fixed.

**Stories** — durations (24 h/1 week/1 month/custom ≤1 year), reactions, archive, highlights, text-overflow fix.
**Kael** — non-dismissing sheet with selectable text, COPY/COPY ALL/REGENERATE; "Draft with Kael" on posts, products, klips, stories, events.
**Bookshop** — 42P17 fixed, close crash fixed, searchable staff picker, searchable lists, seamless tenant switching, marketplace cross-listing, order status machine, low stock, sales summary, CSV export.
**Quiz** — superadmin/COA tournament admin (custom seasons, prizes, publish/feature/cancel), awards ledger, trackable promo codes awardable to any user.
**Verse of the Day** — 458 curated KJV verses, deterministic 458-day rotation, 201-verse offline fallback; branded in-Flutter stream posters + logo default thumbnail.
**Notifications** — FCM payload converted to snake_case (camelCase was silently ignored → wrong default channel → no lock-screen sound), channels/aliases expanded, auto-push added for previously silent types.
**Edge Functions** — all 31 audited; `export-user-data`, `export-church-data`, `delete-account` now wired into the app; server-only and ops functions left alone.
**Release** — APK +331 / AAB +332 on R2; all superseded builds pruned (11 APKs + 7 AABs); web redeployed.

- **Session 2026-09-22/23 - Payments ported from chisomo, ticketing v2, worship setlists, and a long tail of production bug fixes**:
  - **Payments (ported from `chisomo_flutter`)**: adopted its in-flight payout reconciliation + retry/backoff (`reconcileInFlightPayouts()` in `_shared/settlement.ts`), a **platform-fee sweep ledger** (`sweepPlatformFees()`, wired into `lipila-settle` + `lipila-webhook` payout branch, uses `coa_settlement_phone`), **pledge dunning** (`_shared/dunning.ts` `chargeDuePledges()` - pre-creates pending `coa_payments` + `?secret=`), a leader **Church Earnings** screen (`get_my_church_earnings`) and an admin **Platform Fee Ledger** screen (`get_platform_fee_summary` + `fee_sweeps`). Migrations `20261227` + `20261228` applied; `lipila-settle`/`lipila-webhook` redeployed. churchonapp invariants preserved (client never picks payer/payee/amount; pre-created anchors; no `coa_payments` from payout webhooks; `details` jsonb; `phone_number`; `FeeConfig.payoutNet()`). Skipped: chisomo's PDF receipt builder (we have `receipt_service.dart`) and card collections (we have `lipila-card-collect`).
  - **Pro Business Meeting payments/entitlement (`20261221`)**: the generated migration was rewritten against the REAL schema - `meeting_subscriptions` is **user-scoped** (`user_id, plan_type, start_date, end_date, is_active, payment_ref`), not tenant-scoped, and `coa_payments` has **no `tenant_id`** (tenant lives in `metadata`). Now live: `meeting_entitlement`, `request_meeting_subscription` (server-derived price from `platform_settings`: 150/1500 + 30% COA cut), `activate_meeting_subscription` (requires a confirmed `coa_payments`), `get_meeting_admin_report`. Closes the client-side activation bypass.
  - **Event ticketing v2 - Ticketmaster-grade (`20261229_event_ticketing_v2.sql`, applied)**: `event_ticket_tiers`, `event_ticket_orders`, `event_tickets`, `event_ticket_refunds`, `event_ticket_waitlist`, `event_ticket_audit`; RPCs `get_event_ticket_inventory`, `reserve_event_tickets` (**row-locked atomic decrement, rejects overselling, idempotent by payment_ref, anchored on a confirmed `coa_payments` with amount >= total**), `validate_event_ticket` (used-once, idempotent), `refund_event_ticket`, `transfer_event_ticket`, `cancel_event_tickets`, `join_event_waitlist`, `is_event_host`; trigger auto-confirms pending orders when the anchor settles. UI: tier CRUD, buy screen with live "N left", **QR e-ticket** (`event_eticket_screen.dart`) with share/copy/receipt/transfer/host-refund, `my_tickets_tab` status list, and a **camera QR check-in scanner** (`event_ticket_scanner_screen.dart`) with manual-code fallback. Routes still to add: `/ticket/:id`, `/events/:id/tickets`, `/events/:id/manage-tickets`.
  - **Worship setlists 404 (`20261226`)**: `public.worship_setlists` **never existed** (`to_regclass` -> NULL) so every read 404'd. Created it with the columns the client expects (`id, tenant_id, title, song_ids uuid[], service_date, created_by, created_at, updated_at`), tenant-scoped SELECT via `get_my_tenant_id()`, leadership-only writes via `can_manage_worship_setlists()` (`SET search_path = public`, `REVOKE ... FROM anon`), touch trigger, realtime publication. **Retry-spam root cause**: Riverpod 3's `ProviderContainer.defaultRetry` retries a failed provider **up to 10x with backoff** - that's why one missing table produced ~10 identical GETs. Fixed with `retry: (_, __) => null` on `setlistsStreamProvider` + a manual RETRY.
  - **`verse_notes.is_liked` (42703, `20261224`)**: real columns are `id, user_id, translation_id, book_id, chapter, verse, note, is_bookmark, is_favorite, tags, created_at, updated_at` - `is_liked` was genuinely absent, breaking both fetch and `setVerseFlag`. Added it (`NOT NULL DEFAULT false`) + index.
  - **Web CSP blocked `blob:`**: `connect-src 'self' https: wss:` made picked-file -> bytes -> R2 fail on web (`Could not load Blob from its URL`). Fixed in `web/index.html` **and** `web/_headers`: `connect-src` gained `blob: data:`, added `worker-src 'self' blob:`, `img-src`/`media-src` gained `blob:`. Not loosened to `*`.
  - **`getLostData()` UnimplementedError on web**: the only call site was KYC capture (`kyc_verification_screen.dart`); now `if (kIsWeb) return;` guarded.
  - **MFA TOTP disabled (422 `mfa_totp_enroll_not_enabled`)**: client now throws a typed `TotpUnavailableException` and the setup screen hides the enable action with a clear message. **Superadmin must enable TOTP in Supabase Dashboard -> Authentication -> Multi-Factor Auth (cannot be done from code).** RESOLVED 2026-09-30: TOTP confirmed already enabled in the dashboard (MFA on, TOTP on, max 10 factors) - see the 2026-09-30 entry above.
  - **Other production fixes**: recorded-service sermons (dead Cloudflare **live-input** manifest returns HTTP 204 after a broadcast -> `manifestParsingError`; migration `20261220` adds `recording_hls_url` + `playable_recording_url()`, sync deletes unplayable rows, player falls back stored -> CF video manifest -> R2 archive); `profiles_tenant_id_uuid_fkey` repointed to **`tenants(id)`** (was `churches(id)`, which made **bookshop entity selection** fail with 23503); `orders` **42P17** RLS recursion fixed (`20261223`); live viewer `NaN ~/` crash (`live_stream_screen.dart:363` `value.aspectRatio` = 0/0 before first frame) + null-check spam (`stream_projector_screen.dart:55`) + archive-guard on live streams; dead Unsplash sample posters removed (`20261225`); audio artwork no longer calls `path_provider` on web; `daily_bible_verses` ordered by `created_at`; stale-ride auto-clear; geocoding URI builder; ref-after-dispose in tenant selection.
  - **Releases**: APK **v1.0.0+341** (221.6 MB) / AAB **v1.0.0+342** (127 MB) on R2 (`builds/latest/` + versioned + `latest.json`), superseded builds pruned each time. Web redeployed repeatedly (latest `524c0739.churchonapp.pages.dev`).
  - **Ops note**: `wrangler r2 object put` crashes on Windows for files >~250 MB (libuv assertion) and the Cloudflare dashboard caps uploads at 300 MB - use the **S3 API (SigV4 PUT)** for large objects (this is how the 1.4 GB regional PMTiles was published).
