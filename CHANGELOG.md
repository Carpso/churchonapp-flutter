# Changelog

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
