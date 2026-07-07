# Church On App

A comprehensive church management and community platform built with Flutter, connecting congregations through digital giving, marketplace, media, events, and more.

## Features

- **Auth & Profiles** — Email authentication with role-based access (member, admin, pastor, bishop, superadmin)
- **Digital Giving** — Mobile money payments via Lipila gateway (MTN/Airtel/Zamtel), tithe tracking, QR giving
- **Marketplace** — Multi-vendor marketplace with cart, checkout, and order management
- **Media & Streaming** — Sermon uploads, live streaming studio, Kingdom Radio
- **Events** — Service scheduling, conference management, event ticketing
- **Logistics** — Ride & delivery requests with real-time GPS tracking
- **Games** — Bible Quiz arena (13 games built, only quiz unlocked)
- **Discipleship** — Progress tracking, milestones, mentor discovery
- **Kids Zone** — Bible stories, activities, weekly progress tracker
- **Admin Console** — Member management, baptism registry, finance dashboards, global broadcast, payroll (NHIMA/NAPSA/PAYE), heatmaps
- **Social Connect** — Prayer requests, testimonies, community feed with AI moderation
- **Notifications** — Push notifications via Supabase, in-app alerts

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x (Dart) |
| State | Riverpod |
| Backend | Supabase (Postgres, Auth, Realtime, Storage) |
| Payments | Lipila Mobile Money API (Zambia) |
| Maps | OpenStreetMap / LatLng |
| AI | Gemini API (content moderation, reports) |
| Storage | Cloudflare R2 (media uploads) |
| Charts | fl_chart |

## Project Structure

```
lib/
  core/              # Shared services, providers, widgets, config
  features/
    admin/           # Admin dashboards, member management, broadcast
    auth/            # Login, registration, onboarding
    bible/           # Bible reading & study tools
    connect/         # Social feed, prayer requests, testimonies
    disciple/        # Discipleship tracking & mentorship
    events/          # Event scheduling & management
    finance/         # Giving, wallet, Lipila gateway, payouts
    home/            # Main dashboard & navigation
    logistics/       # Ride & delivery requests
    marketplace/     # Product listing, cart, checkout, library
    modules/         # Games, kids zone, media, radio
    navigation/      # Routing & bottom navigation
    notebook/        # Personal notes & journaling
    profile/         # User profile, settings, activity log
    support/         # Help & support
    transport/       # Transport service & driver management
```

## Getting Started

### Prerequisites

- Flutter SDK ^3.9.0
- Supabase project (configured with migrations in `/supabase/migrations`)
- Lipila API key (set in `lib/core/config/env.dart`)

### Setup

```bash
# Install dependencies
flutter pub get

# Run on device
flutter run

# Build release
flutter build apk --release
flutter build appbundle --release
```

### Environment Variables

Configure in `lib/core/config/env.dart`:
- `lipilaApiKey` — Lipila payment gateway API key
- `lipilaWebhookUrl` — Callback URL for Lipila webhook events
- Supabase URL and anon key (auto-configured via `supabase_flutter`)

## Architecture

- **State Management**: Riverpod with `FutureProvider`, `StreamProvider`, and `NotifierProvider`
- **Data Layer**: Supabase direct queries with fallback mock data for offline resilience
- **Payments**: Lipila mobile money collection with PIN polling (30 attempts, 4s interval)
- **Offline**: SharedPreferences-based cache service with TTL expiry
- **Navigation**: Standard `Navigator.push` with `MaterialPageRoute`

## Deployment

- **Android**: `flutter build appbundle --release` (109.8 MB)
- **iOS**: `flutter build ios --release` (requires Apple developer account)
- **Version**: 1.0.0+40 (pubspec.yaml)
- **Package**: com.churchonapp.app

## License

Private — All rights reserved.
