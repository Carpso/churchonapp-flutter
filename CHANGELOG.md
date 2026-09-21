# Changelog

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
