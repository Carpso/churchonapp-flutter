# Church On App

A comprehensive church management and community platform built with Flutter, connecting congregations through digital giving, marketplace, media, events, and more.

**v1.0.0+292 — 1.0.0 | Flutter 3.35.1 | 0 errors, 0 warnings | August 2026**

## Features

- **Auth & Profiles** — Email/Google authentication with role-based access (member, admin, pastor, bishop, superadmin). Android SHA-1/256 fingerprint registered; web OAuth authorized origins configured; Supabase site_url → https://churchonapp.com. **Trust & Identity (KYC)** — AES-256 encrypted ID + selfie upload (works on mobile AND web), admin verification workflow
- **Church Discovery** — Select-church screen fetches ALL nearby Christian churches from OpenStreetMap Overpass API (not just registered ones). Unregistered churches appear on the map with animated logo pins and show a "Not Yet Available" dialog on tap. Registered churches are highlighted.
- **Expansion Leads** — Website footer "Tell us which church to add" form writes to `expansion_leads`; Superadmin & COA Employee dashboards have an Expansion Leads screen to track new/contacted/onboarded leads.
- **Digital Giving** — Mobile money payments via Lipila gateway (MTN/Airtel/Zamtel), tithe tracking, QR giving, wallet coins
- **Marketplace** — Multi-vendor marketplace with cart, checkout, and order management
- **Media & Streaming** — Sermon uploads (R2), live streaming studio (Cloudflare Stream RTMP/HLS + WebRTC WHIP ingest, role-gated with tenant-ownership enforcement), Kingdom Radio
- **Bible Study** — Reading plans, verse of the day, deep study suite, memory verses; NKJV/NLT translations, full-text search, verse notes/bookmarks, cross-references, AI-powered chapter summaries via Kael
- **Data Import** — Enterprise-grade CSV/JSON import system with column mapping, entity presets (Breeze/PlanningCenter/RockRMS/MTN-bank), leadership-only role gate, document extraction via kael-ai, per-row error audit trail, and tenant-scoped import logs
- **Enterprise Reporting** — Church service reports (attendance, offering, visitors, salvations, online viewers, ministries participation), organization-wide service aggregation feeds bishop/apostle dashboards, month-over-month trends
- **Events** — Service scheduling, conference management, event ticketing
- **Logistics** — Ride & delivery requests with real-time GPS tracking, driver portal
- **Games** — Bible Quiz arena (multiplayer) on a JBQ/WBQA-aligned competition engine: timed rounds (5s decision / 30s answer), +10/20/30 difficulty scoring with speed bonuses, 50/50 + Ask-the-Pastor (Kael AI hint) + Extra Time lifelines, anti-cheat flagging, regional/global leaderboards with 4-tier tie-breakers, free practice vs church-sponsored tournaments
- **Kids Zone** — Bible stories, activities, weekly progress tracker
- **Admin Console** — Member management, finance dashboards, global broadcast, payroll (NHIMA/NAPSA/PAYE), superadmin hub, heatmaps
- **Social Connect** — Prayer wall, testimonies, community feed with AI moderation, chat, audio/video calls
- **Notifications** — Push notifications via Supabase Edge Functions, in-app alerts
- **Modules** — Jobs board, business meetings, weather maps, flyer studio, Kael AI chat

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.35.1 (Dart 3.x) |
| State | Riverpod (FutureProvider, StreamProvider, NotifierProvider) |
| Backend | Supabase (Postgres, Auth, Realtime, Storage, Edge Functions) |
| Payments | Lipila Mobile Money API (MTN, Airtel, Zamtel — Zambia) |
| Maps | OpenStreetMap / LatLng (flutter_map) |
| AI | Hugging Face `meta-llama/Llama-3.1-8B-Instruct` via `router.huggingface.co` (Kael AI, quiz generation, sermon summary, moderation — HF-only, no Gemini) |
| Storage | Cloudflare R2 (sermon uploads, media) |
| Charts | fl_chart |
| Calls | Twilio (audio/video) |

## Code Quality

| Metric | Status |
|--------|--------|
| `flutter analyze` | **0 errors, 0 warnings, 0 info** |
| Catch blocks | All non-empty, with `debugPrint` logging |
| Async state | `.when()` pattern used consistently across screens |
| Error handling | Global `ErrorWidget.builder` boundary configured |
| API keys | Removed from source code; loaded from `.env` file |
| Demo credentials | Removed from production auth flow |
| R8 optimization | 5-pass proguard + full mode, log stripping, ABI splits |

## Project Structure

```
lib/
  core/
    config/          # Environment variables (.env loader)
    providers/       # Riverpod providers (auth, profile, stats, etc.)
    routes/          # App router
    services/        # Supabase, notifications, R2, Gemini, tenant, etc.
    theme/           # App theme, colors, typography
    utils/           # Connectivity, DB seeder, platform settings
    widgets/         # Shared widgets (church map, error boundary, QR, etc.)
   features/
     admin/           # 60+ screens: dashboards, member mgmt, broadcast, payroll
     auth/            # Login, signup, onboarding, church selection
     bible/           # Bible reader, verse service, reading plans
     connect/         # Social feed, prayer wall, chat, calls, testimonies
     data_import/     # CSV/JSON/document import, column mapping, entity presets
     disciple/        # Discipleship tracking & mentorship
    events/          # Event scheduling & management
    finance/         # Giving, wallet, Lipila gateway, payouts
    home/            # Main dashboard, live stream, news, announcements
    logistics/       # Ride & delivery requests
    marketplace/     # Product listing, cart, checkout, library
    modules/         # Bible quiz, games, kids zone, media, radio, jobs, events
    navigation/      # Bottom nav shell, routing
    notebook/        # Personal notes & journaling
    profile/         # User profile, settings, activity, referrals
    support/         # Help & support
    transport/       # Transport services, driver management
```

## Getting Started

### Prerequisites

- Flutter SDK ^3.9.0
- Supabase project (configured with migrations in `/supabase/migrations`)
- Lipila API key (set in `.env` file)

### Setup

```bash
# Copy environment file and configure
cp .env.example .env
# Edit .env with your keys (Supabase URL, Lipila key, Gemini key, etc.)

# Install dependencies
flutter pub get

# Run on device
flutter run

# Build release (auto-increments build number)
.\build_release.ps1           # AAB for Play Store
.\build_release.ps1 -Type apk # APK for direct install
```

### Environment Variables

Configured via `.env` file (see `.env.example`):
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — Supabase project credentials
- `LIPILA_API_KEY` — Lipila payment gateway API key
- `LIPILA_SHORT_CODE` — Lipila merchant short code
- `GEMINI_API_KEY` — Google Gemini API key
- `GOOGLE_WEB_CLIENT_ID` — Google OAuth client ID
- `R2_ENDPOINT` / `R2_ACCESS_KEY` / `R2_SECRET_KEY` — Cloudflare R2 storage
- `LIPILA_PAYOUT_WEBHOOK_URL` — Callback URL for Lipila payout webhooks

## Architecture

- **State Management**: Riverpod with `FutureProvider`, `StreamProvider`, and `NotifierProvider`
- **Data Layer**: Supabase direct queries with fallback mock data for offline resilience
- **Payments**: Lipila mobile money collection with PIN polling (30 attempts, 4s interval). Platform-first model: payments collected to merchant wallet (2.5% collection fee), then auto-disbursed minus the 1.5% Lipila disbursement fee.
- **Offline**: SharedPreferences-based cache service with TTL expiry
- **Navigation**: Standard `Navigator.push` with `MaterialPageRoute`

## Database Migrations

Migrations live in `supabase/migrations/` and are applied via `supabase\deploy.ps1`.

### Seed Data

The KJV Bible text (31,102 verses) was originally a single 7.3MB SQL file that exceeded Supabase's API request size limit (413). It has been split into 11 idempotent batches (`20260711000004_seed_kjjv_text_p001.sql` … `p011.sql`) in `supabase/migrations/` and referenced by `deploy.ps1`. The original seed file (`20260711000004_seed_kjjv_text.sql`) has been replaced with a no-op verification comment.

### Migration Health

All migrations apply cleanly — **0 failures** across the full deploy list (153+ applied). Latest additions: `20260910` (subscribe-to-tier anchored on confirmed coa_payments), `20260911` (server-side 2FA via auth.mfa), `20260912` (COA role-assignment RLS fix), `20260913` (offline giving replay), `20260914` (livestream studio tables), `20260915` (platform ads tenant scoping), `20260916` (churches UPDATE RLS), `20260917` (SOS alerts RLS incl. coa_employee), `20260918` (prophetic heatmap real-data RPC), `20260919` (church_buses RLS incl. coa_employee).

### Deployment

```powershell
# Apply all migrations
.\supabase\deploy.ps1

# Deploy Edge Functions
supabase functions deploy push-notifications --no-verify-jwt
supabase functions deploy kael-ai --no-verify-jwt
# ... (all 21 functions)

# Build release
.\build_release.ps1           # AAB
.\build_release.ps1 -Type apk # APK
```

| Platform | Command | Size |
|----------|---------|------|
| Android (AAB) | `.\build_release.ps1` | ~122 MB |
| Android (APK) | `.\build_release.ps1 -Type apk` | ~210 MB universal |
| iOS | `flutter build ios --release` | Requires Apple developer account |
| Web | `flutter build web` | Hosted via Cloudflare Pages |

- **Package**: com.churchonapp.churchonapp
- **Supabase**: Self-hosted or managed project
- **Edge Functions**: 29 Edge Functions (push notifications, payments, AI, streaming management, data import, SMS, email, WhatsApp, export tools, database backup)
- **Storage**: Cloudflare R2 for media uploads

## Security

- API keys loaded from `.env`, never hardcoded in source
- All database queries go through Supabase Row Level Security (RLS)
- Role-based access control enforced server-side on all Edge Functions
- Cloudflare Stream management role-gated (leadership only) with tenant-ownership enforcement
- Data import restricted to leadership roles with column allowlist + tenant scoping
- Input validation on all forms; server-side column blocklist prevents role/coins escalation during imports
- Catch blocks log errors instead of swallowing them silently
- Payout failures logged with full context for debugging

## License

Private — All rights reserved.
