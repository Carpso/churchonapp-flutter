# Church On App

A comprehensive church management and community platform built with Flutter, connecting congregations through digital giving, marketplace, media, events, and more.

**v1.0.0+249 | Flutter 3.35.1 | Dart 3.x | 0 errors, 0 warnings**

## Features

- **Auth & Profiles** — Email/Google authentication with role-based access (member, admin, pastor, bishop, superadmin)
- **Digital Giving** — Mobile money payments via Lipila gateway (MTN/Airtel/Zamtel), tithe tracking, QR giving, wallet coins
- **Marketplace** — Multi-vendor marketplace with cart, checkout, and order management
- **Media & Streaming** — Sermon uploads (R2), live streaming studio (YouTube), Kingdom Radio
- **Bible Study** — Reading plans, verse of the day, deep study suite, memory verses; NKJV/NLT translations, full-text search, verse notes/bookmarks, cross-references, AI-powered chapter summaries via Kael
- **Events** — Service scheduling, conference management, event ticketing
- **Logistics** — Ride & delivery requests with real-time GPS tracking, driver portal
- **Games** — Bible Quiz arena (multiplayer), trivia games
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
| AI | Gemini API (content moderation, reports, chat) |
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

All migrations apply cleanly — **0 failures** across the full deploy list (148 applied, 18 skipped by design: 6 deleted empty placeholders, 11 KJV seed batches already applied, 1 neutralized seed file). Latest migration `20260803_133358_bible_nkjv_nlt_smart_features.sql` adds NKJV/NLT translations, `bible_chapters` table, full-text search on `bible_verses`, reading plans, verse notes, cross-references, and AI-powered chapter summaries.

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
| Android (AAB) | `.\build_release.ps1` | ~118 MB |
| Android (APK) | `.\build_release.ps1 -Type apk` | ~203 MB universal |
| iOS | `flutter build ios --release` | Requires Apple developer account |
| Web | `flutter build web` | Hosted via Cloudflare Pages |

- **Package**: com.churchonapp.churchonapp
- **Supabase**: Self-hosted or managed project
- **Edge Functions**: Push notifications, webhook handlers
- **Storage**: Cloudflare R2 for media uploads

## Security

- API keys loaded from `.env`, never hardcoded in source
- All database queries go through Supabase Row Level Security (RLS)
- Role-based access control enforced server-side
- Input validation on all forms
- Catch blocks log errors instead of swallowing them silently
- Payout failures logged with full context for debugging

## License

Private — All rights reserved.
