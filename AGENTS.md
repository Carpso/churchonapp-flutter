# Church On App — How-To Guide for AI Agents

## Project Overview

Flutter-based church management platform with Supabase backend. Covers digital giving, marketplace, media streaming, events, logistics, Bible study, social features, and admin tools. Target market: Zambian churches (MTN/Airtel/Zamtel mobile money).

## Quick Start

```bash
# First time
cp .env.example .env      # Fill in actual keys
flutter pub get

# Run
flutter run

# Build
.\build_release.ps1       # Auto-increments build number + builds AAB
.\build_release.ps1 -Type apk

# Analyze
flutter analyze
```

## How To: Run Flutter Analyze

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

- Source code should have **0 errors, 0 warnings**
- Test files have pre-existing issues (reporting_service_test.dart needs constructor update, radio_service_test.dart references removed `fetchLiveMetadata`, many unused imports)
- If adding code, ensure no new warnings appear in source (test warnings are acceptable)

## How To: Write a New Feature

1. Follow the feature-first structure:
   - `lib/features/<feature>/data/` — services, models, providers
   - `lib/features/<feature>/presentation/` — screens, widgets
2. State management: Riverpod (`FutureProvider`, `StreamProvider`, `NotifierProvider`)
3. Database: Supabase with RLS — queries go through `supabase.from('table').select()`
4. Never hardcode API keys — use `Env.keyName` from `lib/core/config/env.dart`
5. Import convention: `package:church_on_app/...` (not relative imports for cross-feature)
6. Use `debugPrint()` in catch blocks, never `print()`
7. Handle async states with `.when(data: ..., loading: ..., error: ...)` pattern
8. Test files go in `test/features/<feature>/`

## How To: Run a Migration

Migration files are in `supabase/migrations/`. Apply via Supabase dashboard SQL editor or CLI.

## How To: Add an Environment Variable

1. Add to `.env.example` with a placeholder value
2. Add to `.env` locally with real value
3. Add getter in `lib/core/config/env.dart`
4. Add to `.gitignore` if not already listed
5. Never commit `.env` to git

## How To: Use Kael AI (chat, sermon summaries, audio drama)

Kael is the in-app AI assistant. Edge Function: `supabase/functions/kael-ai/index.ts`. Client: `lib/features/modules/media/data/ai_chat_service.dart`.

**Provider order**: Gemini Flash (`GEMINI_API_KEY`, env `GEMINI_MODEL` default `gemini-2.0-flash`) → HuggingFace free-tier (`HUGGINGFACE_TOKEN`; env `HF_MODEL_ID` default `HuggingFaceH4/zephyr-7b-beta` — never a PRO-gated model like `mistralai/Mistral-7B-Instruct-v0.3`).

**Request contract (unified)** — `action` decides the response format:
- `action: 'chat'` (default, requires `messages[]` + optional `userContext`) → **SSE** (`data: {"chunk": ...}` then `data: {"done": true}` or `data: {"error": ...}`)
- `action: 'summary'` / `'dramatize'` / other (requires `prompt` — `message`/`content` accepted as legacy aliases) → **JSON** `{"response": "..."}`

**Client**: chat uses true SSE streaming via raw HTTP (`POST <restUrl>/functions/v1/kael-ai` with Bearer token, `Accept: text/event-stream`), buffered `functions.invoke` as fallback. Never treat chat as JSON — the Edge Function returns `text/event-stream`.

**DB**: `ai_chat_sessions` + `ai_chat_messages` (with RLS) must exist — recreated standalone in migration `20260857_ai_chat_tables.sql` (previously only in the failed `20260710_missing_tables_schema.sql` batch).

## How To: Handle Payments

The Lipila payment gateway lives at `lib/features/finance/presentation/lipila_payment_gateway.dart`.
- Uses `supabase.functions.invoke()` (NOT raw HTTP) to call Lipila API server-side
- PIN polling: 30 attempts, 4s interval
- Real Lipila merchant rates (wallet 68907, Carpso Solutions): **2.5% MoMo collection, 1.5% MoMo disbursement**
- Fees are remote-configurable via `platform_settings`: `momo_fee_percent` (2.5%) + `coa_fee_percent` (1%) = 3.5% customer MoMo fee; `lipila_disbursement_fee_percent` (1.5%) + `coa_payout_fee_percent` (1%, min K3) are deducted from every payout via `FeeConfig.payoutNet()` — never send a raw payout amount to `lipila-payout`
- For payout webhooks, set `LIPILA_PAYOUT_WEBHOOK_URL` in Edge Function env

## How To: Use Remote Configuration (no app updates for value changes)

`RemoteConfig` (`lib/core/config/remote_config.dart`) reads ALL `platform_settings` rows once and exposes typed getters with local fallbacks. Change a `value` in Supabase → next app launch picks it up. **Never hardcode a tunable business value** — add a key instead.

### Usage

- Providers/services: `currentRemoteConfig(ref)` (takes `Ref`)
- Widgets: `widgetRemoteConfig(ref)` (takes `WidgetRef` — Riverpod 3 keeps these separate)
- Reactive: `ref.watch(remoteConfigProvider).value` in build

### How To: Add a New Config Key

1. Use it in code with a fallback: `currentRemoteConfig(ref).getInt('my_key', 25)` (or `getDouble` / `getBool` / `getString` / `getDuration` (seconds) / `getDoubleList` (comma-separated))
2. Add the key + default to migration `supabase/migrations/20260854_remote_config_keys.sql` with `ON CONFLICT (key) DO NOTHING`
3. Add an editable field to `_featureFields` in `lib/features/admin/presentation/subscription_pricing_screen.dart` so COA can edit it from the admin UI

### Currently wired keys

| Area | Keys (fallback) |
|------|-----------------|
| Coin rewards | `coins_daily_open_reward` (25), `coins_streak_bonus_per_day` (50), `coins_attendance_reward` (50), `coins_referral_reward` (100), `coins_daily_collect_cooldown_sec` (72000), `coins_open_streak_1d/6d/13d/14d` (5/10/20/30) |
| Carpso rides | `ride_per_km_kwacha` (5), `ride_min_total_fare_kwacha` (15), `ride_delivery_min_fare_kwacha` (20), `ride_medium_weight_surcharge_kwacha` (5), `ride_heavy_weight_surcharge_kwacha` (10), `ride_avg_city_speed_kmh` (25) |
| Bible quiz | `quiz_prize_1st/2nd/3rd_kwacha` (500/300/150), `quiz_season_weeks` (12), `quiz_lease_fee_kwacha` (1500), `quiz_lease_fee_usd` (50) |
| Subscriptions | `subscription_trial_days` (30), `subscription_renewal_days` (365), `platinum_promo_days` (30), `subscription_manual_payment_days` (30) |
| Marketplace/Events | `marketplace_delivery_fee_kwacha` (15), `event_commission_percent` (0.10) |
| Fees (FeeConfig) | `coa_fee_percent`, `momo_fee_percent`, `card_fee_percent`, `business_cut_percent`, `min_fee_kwacha`, `lipila_disbursement_fee_percent`, `coa_payout_fee_percent`, `ride_base_fare_kwacha`, `ride_delivery_base_fare_kwacha`, `ride_delivery_per_km_kwacha` |
| Plan pricing | `onboarding_fee`, `gold_monthly_fee`, `platinum_monthly_fee` (wired in `home_subscription_paywall.dart`) |

**Known gap**: the old `quiz_lease_fee` key (K250 default) is still shown in the pricing screen overview but the hub lease modal now reads `quiz_lease_fee_kwacha` (K1,500).

## How To: Manage Church Coins (CC)

Church Coins are **loyalty reward tokens** for in-app use only. They have no real-world monetary value and cannot be exchanged for cash, transferred between users, or refunded. Compliant with Zambian law (BoZ VASP directive — coins are loyalty points, NOT cryptocurrency).

### Architecture

```
EARNING (free)                    SPENDING (in-app only)           BUYING (real money)
─────────────                     ──────────────────────           ──────────────────
Daily app opens (5-30 CC)         Ad promotion (100-1000 CC)       Buy Coins screen
Bible reading streaks             Bookshop book redemption         via Lipila (MoMo/Card)
Referrals (100 CC each)           Partner offer redemption         5 packages: 100-2500 CC
Attendance scanning               Bible Quiz merch (future)
Bible quiz participation          COA promo campaigns (manual)
```

### Key Rules (NEVER violate)
| Allowed | Blocked |
|---------|---------|
| Earn coins via activities | Cash out coins to MoMo |
| Buy coins with real money | Transfer coins between users |
| Spend on ad promotion | Use for tithing/offering |
| Redeem at partner locations | Use to buy goods/services |
| Earn referral bonuses | Represent as real currency |

### Files

| File | Purpose |
|------|---------|
| `lib/core/services/coins_service.dart` | Core service: earn, spend, balance, partner redemption |
| `lib/features/finance/data/coin_purchase_service.dart` | Buy coins with real money (Lipila integration) |
| `lib/features/finance/data/partner_tenant_service.dart` | Partner tenant + offer management |
| `lib/features/finance/presentation/buy_coins_screen.dart` | TikTok-style coin purchase UI |
| `lib/features/finance/presentation/partner_redemption_screen.dart` | Browse & redeem partner offers |
| `lib/features/admin/presentation/manage_partners_screen.dart` | Superadmin/COA add partner tenants |
| `lib/features/finance/presentation/payout_request_screen.dart` | Coin dashboard (balance, buy, redeem) |
| `lib/features/admin/presentation/ad_payment_sheet.dart` | Ad promotion (coins + mobile money) |

### How To: Add a New Coin Earning Method

1. Add method to `CoinsService` in `coins_service.dart`:
```dart
Future<int> addNewMethod() async {
  final user = _client.auth.currentUser;
  if (user == null) throw Exception("Not authenticated");
  await _client.rpc('add_coins', params: {
    'user_id': user.id,
    'amount': 50, // coin amount
  });
  return 50;
}
```
2. Call from the relevant screen's action handler
3. Coins are added via the `add_coins` Postgres RPC function

### How To: Add a New Coin Spending Method

1. Add spending method to `CoinsService`:
```dart
Future<void> spendOnSomething({
  required int coinAmount,
  required String description,
}) async {
  final user = _client.auth.currentUser;
  if (user == null) throw Exception("Not authenticated");
  // Check balance first
  final profile = await _client.from('profiles').select('coins').eq('id', user.id).maybeSingle();
  final current = (profile?['coins'] as num?)?.toInt() ?? 0;
  if (current < coinAmount) throw Exception("Insufficient coins");
  // Deduct
  await _client.rpc('add_coins', params: {
    'user_id': user.id,
    'amount': -coinAmount,
  });
  // Log redemption
  await _client.from('coin_redemptions').insert({
    'user_id': user.id,
    'amount': coinAmount,
    'redemption_type': 'custom',
    'description': description,
    'status': 'completed',
  });
}
```
2. **IMPORTANT**: This should NEVER be used for tithing, offering, or buying goods unless COA team runs a specific promo

### How To: Add a Partner Tenant (Superadmin)

1. Navigate to Superadmin Hub → Partner Tenants
2. Tap "+" to add a partner (name, type: bookshop/coffee_shop/restaurant/other)
3. Add offers for the partner (title, coins required)
4. Users see offers in PartnerRedemptionScreen and can spend coins

### Database Tables Required

```sql
-- Coin purchases (buying with real money)
CREATE TABLE coin_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  coins_amount INT NOT NULL,
  price_kwacha INT NOT NULL,
  payment_ref TEXT,
  payment_method TEXT,
  package_label TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Coin redemptions (spending coins)
CREATE TABLE coin_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  amount INT NOT NULL,
  redemption_type TEXT NOT NULL, -- 'bookshop', 'partner_offer', 'merch_store', 'ad_promotion'
  partner_id TEXT,
  description TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Partner tenants
CREATE TABLE partner_tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL, -- 'bookshop', 'coffee_shop', 'restaurant', 'other'
  description TEXT,
  location TEXT,
  logo_url TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Partner offers
CREATE TABLE partner_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id UUID REFERENCES partner_tenants(id),
  title TEXT NOT NULL,
  description TEXT,
  coins_required INT NOT NULL,
  image_url TEXT,
  is_active BOOLEAN DEFAULT true,
  redeemed_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Increment redeemed count RPC
CREATE OR REPLACE FUNCTION increment_redeemed_count(offer_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE partner_offers SET redeemed_count = redeemed_count + 1 WHERE id = offer_id;
END;
$$ LANGUAGE plpgsql;
```

## How To: Generate Codes (Tenant, User, Tithe Card, Referral, etc.)

All codes use the `CodeGeneratorService` at `lib/core/services/code_generator_service.dart`. Every code starts with `COA-` brand prefix.

### Code Formats

| Code Type | Format | Example |
|-----------|--------|---------|
| Tenant Code | `COA-{ISO}_T_{NNNN}` | `COA-ZM_T_0001` |
| Church Code | `COA-{ISO}_CH_{NNNN}` | `COA-ZM_CH_0001` |
| Bookshop Code | `COA-{ISO}_BS_{NNNN}` | `COA-ZM_BS_0001` |
| User Code | `COA-{ISO}_U_{XXXXXX}` | `COA-ZM_U_A1B2C3` |
| Tithe Card Number | `COA-{ISO}-TC-{YYYY}-{NNNNNN}` | `COA-ZM-TC-2026-000001` |
| Referral Code | `COA-{ISO}-REF-{XXXXXX}` | `COA-ZM-REF-A1B2C3` |
| Wallet ID | `COA-{ISO}-W-{XXXXXX}` | `COA-ZM-W-A1B2C3` |
| Membership ID | `COA-{ISO}-MEM-{NNNNNN}` | `COA-ZM-MEM-000001` |
| Event Ticket | `COA-TKT-{YYYY}-{XXXXXX}` | `COA-TKT-2026-A1B2C3` |
| Payment Reference | `COA-TXN-{YYYY}-{XXXXXX}` | `COA-TXN-2026-A1B2C3` |

Where `{ISO}` = country code (ZM, ZW, KE), `{NNNN}` = sequential counter, `{XXXXXX}` = random alphanumeric, `{YYYY}` = year.

### How To: Generate a New Code Type

1. Add method to `CodeGeneratorService`:
```dart
Future<String> generateMyCode(String country) async {
  final iso = countryToISO(country);
  final next = await _nextSequence('my_code');
  return '$brandPrefix-${iso}_MY_$next';
}
```
2. Add format regex to `_formatPatterns` for validation
3. Add sequence name to `id_sequences` table in migration
4. Call from the relevant screen/service

### How To: Register a Generated Code

Always register codes in the `generated_codes` table for tracking:
```dart
await codeGenerator.registerCode(
  codeType: 'referral',
  codeValue: code,
  countryIso: iso,
  userId: user.id,
);
```

### Database Tables

```sql
-- Sequence counter (already exists)
CREATE TABLE id_sequences (
  name TEXT PRIMARY KEY,
  value BIGINT NOT NULL DEFAULT 0
);

-- RPC for atomic increment
CREATE OR REPLACE FUNCTION next_id_sequence(seq_name TEXT)
RETURNS TEXT AS $$
DECLARE next_val BIGINT;
BEGIN
  INSERT INTO id_sequences (name, value) VALUES (seq_name, 1)
  ON CONFLICT (name) DO UPDATE SET value = id_sequences.value + 1
  RETURNING value INTO next_val;
  RETURN LPAD(next_val::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- Code registry
CREATE TABLE generated_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code_type TEXT NOT NULL,
  code_value TEXT NOT NULL UNIQUE,
  country_iso TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### Key Rules

- **Never generate codes manually** — always use `CodeGeneratorService`
- **Never use raw UUIDs** for user-facing codes
- **Always register codes** in `generated_codes` table
- **Referral code ≠ Wallet ID** — they are different codes with different formats
- **Country prefix is required** — determines which market the code belongs to

## How To: Add a Supabase RLS Policy

1. Create migration file `supabase/migrations/<timestamp>_description.sql`
2. Write `CREATE POLICY` or `ALTER POLICY` with proper `USING` and `WITH CHECK` clauses
3. Always verify using `auth.jwt() -> 'sub'` or profile-based lookups (never `auth.jwt() -> 'role'`)
4. For SECURITY DEFINER functions, always add `SET search_path = public`
5. For church-scoped data, filter by `tenant_id`
6. Test policies by enabling and running queries as different roles
7. **Never use `WITH CHECK (true)` or `USING (true)` on INSERT/UPDATE policies** — always add auth checks like `auth.uid() = user_id` or `auth.uid() = contributor_id`
8. **SECURITY DEFINER functions must have `REVOKE EXECUTE FROM anon`** — unauthenticated users should never call elevated-privilege functions
9. Use `DO $$ BEGIN ... EXCEPTION WHEN undefined_object THEN NULL; END $$;` for safe DROP POLICY blocks in migrations

## How To: Add or Modify Onboarding for a Role

1. Add role to `_allRoles` in `lib/features/profile/presentation/role_onboarding_screen.dart`
2. Add 3 `Step` widgets with icon, title, description
3. Add a getter in `UserProfile` in `lib/core/providers/profile_provider.dart` (e.g., `bool get isProphet => role == 'prophet'`)
4. Add dashboard tile in `lib/features/admin/presentation/admin_hub_screen.dart`
5. If the role needs a trial check, add logic in `home_screen.dart` paywall section

## How To: Adjust Quick Actions on Home Screen

Edit `_buildQuickActions()` in `lib/features/home/presentation/home_screen.dart`:
- The `actions` list at the top of the method defines button order, icon, label, color
- Each action's tap handler is in the `onTap` callback (map by `label`)
- Add new imports at the top of the file for any new screens

## How To: Add an Offline Fallback

1. Use `SharedPreferences` for caching in the data service
2. Call pattern: try fetching from API → cache result → on error, read from cache
3. `OfflineService` (at `lib/core/services/offline_service.dart`) provides `startAutoSync()` for retry with exponential backoff (3 attempts)
4. Wrap screens in `OfflineAwareWrapper` (already done in `main_navigation_shell.dart`)

## How To: Fix UI Obstructed by Phone Status Bar

The app opts into edge-to-edge via `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` in `main.dart` `initState()`, which draws behind the system status bar. To prevent content from being hidden under the notch/status bar:

1. **Global fix**: A `SafeArea(top: true)` is applied in `MaterialApp.router`'s `builder` (main.dart)
2. **Navigation shell**: `main_navigation_shell.dart` has `SafeArea(top: true)` (line 252)
3. **Fix a screen**: Add `SafeArea(top: true, child: ...)` or use `MediaQuery.of(context).padding.top` for positioning

Never remove the status bar padding — some Android devices have notches, punch-holes, or camera cutouts.

## Google Play Compliance — DO NOT REGRESS (read before every release)

Google Play flags 3 things on every release. These are FIXED — do not undo them:

### 1. Edge-to-edge: NEVER use deprecated color parameters
- `SystemUiOverlayStyle(statusBarColor: ...)` and `systemNavigationBarColor: ...` map to the deprecated `Window.setStatusBarColor()` / `setNavigationBarColor()` — Google Play flags the release with **"deprecated APIs or parameters for edge-to-edge"**.
- Correct pattern (in `main.dart` `_updateOverlayStyle`): set **icon brightness only** (`statusBarIconBrightness`, `systemNavigationBarIconBrightness`), plus `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` once in `initState()`. SafeArea handles the padding.
- `SystemUiMode.immersiveSticky` in video/call screens is fine (different feature, not flagged).

### 2. R8 optimization: keep minification ON
- `android/app/build.gradle.kts` release build type MUST keep `isMinifyEnabled = true` and `isShrinkResources = true` (with `proguard-rules.pro`). Removing them re-triggers **"Improve your app's memory and performance with R8 optimization"**.
- Release 247's warning was from a build predating this config — the next release clears it automatically.

### 3. Bitmap downsampling: always downscale image decodes
- Full-size decodes (camera photos, `Image.file` without `cacheWidth`) trigger **"Improve your app's performance with bitmap downsampling"**.
- Rule: any `Image.file`/`Image.network`/`Image.memory` rendering a photo MUST pass `cacheWidth`/`cacheHeight` (≈ display size × `MediaQuery.devicePixelRatioOf(context)`). `AppImage` (`lib/core/widgets/app_image.dart`) already downsamples via `memCacheWidth`/`memCacheHeight` — prefer it for network images.
- Verified fixed: `post_product_screen.dart` preview, `events_screen.dart` banner preview.


## How To: Ensure Users Show Up Per Tenant

Users are scoped to tenants via `profiles.tenant_id`. To list users for a tenant:

```dart
final members = await supabase.from('profiles').select('*').eq('tenant_id', tenantId);
```

Key tenant-scoped patterns in the codebase:

| Feature | How It Filters | File |
|---------|---------------|------|
| Events | `eventsStreamProvider` reads `currentTenantProvider` | `event_service.dart` |
| Social posts | App-layer `.eq('tenant_id', tenantId)` | `social_service.dart` |
| Bible quiz PVP | `.eq('tenant_id', tid)` for same-church opponents | `bible_quiz_service.dart` |
| Game leaderboard | `.eq('profiles.tenant_id', tenantId)` via join | `game_service.dart` |
| Bible quiz leaderboard | `.eq('tenant_id', tenantId)` on profiles | `bible_quiz_service.dart` |
| Communities | `.eq('tenant_id', tenantId)` on `community_communities` | `community_service.dart` |
| Admin member listing | `getMembersStream()` with `.eq('tenant_id', tenantId)` | `admin_service.dart` |

If a user's `profiles.tenant_id` is NULL, they won't appear in tenant-scoped queries. When registering a user to a church, always set `tenant_id` on their profile.

## How To: Build & Release

```powershell
# Bump version in pubspec.yaml (or use build_release.ps1)
.\build_release.ps1           # AAB for Play Store
.\build_release.ps1 -Type apk # APK

# Outputs:
# APK:  build\app\outputs\flutter-apk\app-release.apk
# AAB:  build\app\outputs\bundle\release\Church On App.aab
```

## How To: Understand the Trial & Subscription Flow

The church onboarding flow enforces a **30-day free trial** then payment:

1. **Registration**: `register_church_screen.dart` creates church with `subscription_ends_at = now + 30 days`
2. **Onboarding**: `church_onboarding_screen.dart` also sets 30-day trial
3. **Home screen**: `home_screen.dart` shows:
   - `_buildTrialBanner()` — green banner with days remaining when 7+ days left, orange when <7
   - `_buildSubscriptionPaywall()` — paywall when trial expired, showing payment instructions
4. **Admin approval**: `coa_employee_dashboard.dart` — superadmins verify churches and approve payments
5. **Payment extension**: When payment is approved, `subscriptionEndsAt` gets extended by 365 days
6. **`Tenant.isSubscriptionExpired`**: Returns true if now is after `subscriptionEndsAt`

## How To: Add Marketing & Ad Materials

Marketing materials live in `marketing/`:
- `AD_SCRIPTS.md` — TikTok/Reels/YouTube/Facebook ad scripts (15s-60s)
- `CHURCH_ONBOARDING_SCRIPTS.md` — Phone/WhatsApp/Email/in-person pitch scripts + objection handling
- `VIDEO_ADS_SCRIPTS.md` — Production-ready video ad scripts with scene-by-scene breakdowns
- `VOICEOVER_SCRIPTS.md` — VO narration for app store video, tutorial, radio, demo presentation
- `SOCIAL_MEDIA_CONTENT_CALENDAR.md` — 30-day content plan + posting times + hashtags
- `INFLUENCER_PARTNERSHIPS.md` — Partnership tiers, outreach templates, referral commissions
- `APP_STORE_OPTIMIZATION.md` — Keywords, screenshots, description, localization for Zambian market

## How To: Use the How-To Guides Feature

The in-app help system lives at `lib/features/support/presentation/support_hub_screen.dart`:
- **Tab 1 "HOW-TO GUIDES"**: 5 categories (Wallet, Word & Radio, Community, Logistics, Ministry) with step-by-step guides
- **Tab 2 "SUBMIT TICKET"**: Support ticket form that creates a row in `tickets` table + notifies admins
- Guides show numbered steps and have action buttons that navigate to the relevant screen
- To add a new guide: add a new `_GuideExpansionTile` in the `_buildCategoryGuides()` method

## Architecture

### Multi-Tenant Architecture (Churches + Bookshops)

The platform supports two tenant types via the `tenants` parent table:

```
tenants(id, name, type)  ──────── tenant_id → all scoped tables
    ↑  (type: 'church' | 'bookshop')
    │
churches(id, tenant_id, ...)  ─── church_id → church-specific tables
bookshops(id, tenant_id, ...) ─── (future)
```

- **`tenant_id`** → generic FK to `tenants(id)` — primary scoping for all data (RLS, queries)
- **`church_id`** → specific FK to `churches(id)` — church-specific features (nullable for bookshops)
- Every church-scoped table has BOTH columns for future multi-site/multi-tenant queries
- Superadmins have full CRUD on `tenants` and `bookshops` tables
- All 150+ public tables have RLS enabled

### Seed Church ID Prefixes (`zm_`, `zw_`)

Church IDs prefixed with country codes are seed/development data:

| Prefix | Country | Purpose |
|--------|---------|---------|
| `zm_` | Zambia | Seed Zambian churches (default market) |
| `zw_` | Zimbabwe | Seed Zimbabwean churches (expansion market) |

These IDs are generated by the `tenant_service.dart` seed data and grant hardcoded 10-year subscriptions for testing. Production churches use UUIDs generated by Supabase.

**Expansion:** 45 Zambian churches (zm_1–zm_45 across 8 provinces) + 12 Zimbabwean churches (zw_1–zw_12 across Harare, Bulawayo, Gweru, Mutare, Masvingo). To add more, create entries in `tenant_service.dart` `fallbackChurches` + migration SQL with `INSERT INTO churches ... WHERE NOT EXISTS`.

### Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Riverpod over Provider | Compile-safe, testable, supports async providers natively |
| Supabase over custom backend | RLS, realtime, auth, storage, Edge Functions — all-in-one |
| `go_router` for deep links | Required for Carpso Ride deep linking |
| `flutter_map` over Google Maps | Free, no API key required, offline tiles via PMTiles |
| `encrypt` package for 2FA | AES-256 replaces weak XOR cipher |
| `universal_io` over `dart:io` | Cross-platform support (web, desktop, mobile) |
| `supabase.functions.invoke()` over raw HTTP | Edge Function handles secrets server-side, no token exposure |
| Offline-first with SharedPreferences | Simple key-value cache; no SQLite overhead for mostly-read data |
| Coins for rewards only | Marketplace uses mobile money; coins are rewards/redeem/referral only |
| Instant church payouts | Churches auto-settled; drivers/merchants conditional on completion |
| `CodeGeneratorService` for all codes | COA-branded, country-prefixed, sequential counters, DB-backed, validated |

## Features by Role

| Role | Access |
|------|--------|
| **Member** | Bible, giving, events, radio, live stream, prayer wall, Bible quiz, Carpso Ride, marketplace, notebook, SOS |
| **Pastor/Bishop** | All member features + church dashboard, member management, giving reports, global broadcast, service reports |
| **Treasurer** | Giving dashboard, payout requests, financial reports |
| **Driver** | Ride acceptance, delivery requests, earnings dashboard |
| **Vendor/Merchant** | Marketplace inventory, order management, payout requests |
| **Writer** | Manuscript upload, publishing tools |
| **Superadmin** | All admin features + church verification, employee management, platform settings |
| **COA Employee** | Church onboarding, church approval/rejection, payment management |

## How To: Complete Deployment Workflow

### 1. Build Android Release

```powershell
# APK (for direct install / testing)
.\build_release.ps1 -Type apk
# Output: build\app\outputs\flutter-apk\app-release.apk

# AAB (for Google Play Store)
.\build_release.ps1
# Output: build\app\outputs\bundle\release\Church On App.aab
```

The script auto-increments build number in `pubspec.yaml`.

### 2. Deploy Supabase (Migrations + Edge Functions)

```powershell
.\supabase\deploy.ps1
```

Manual Edge Function deployment:
```powershell
supabase functions deploy <name> --no-verify-jwt
```

Edge Functions (21 total):
`bible-study-notify`, `cloudflare-stream`, `database-backup`, `delete-account`, `export-church-data`, `export-user-data`, `kael-ai`, `lipila-collect`, `lipila-payout`, `lipila-settle`, `lipila-webhook`, `migrate-coa-payments`, `migrate-to-r2`, `new-member-notify`, `push-notifications`, `r2-sign`, `send-birthday-email`, `send-sms`, `turn-credentials`, `well-known`

### 3. Deploy Web to Cloudflare Pages

```powershell
flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=
npx wrangler pages deploy build/web --project-name=churchonapp --branch=main
```

Requires `CLOUDFLARE_API_TOKEN` env var with **Cloudflare Pages:Edit** permission.

**Key web files:**
- `web/_redirects` — SPA routing + `/.well-known/*` redirects to Supabase Edge Function
- `web/.well-known/assetlinks.json` — Android app links (3 SHA-256 fingerprints + credential sharing)
- `web/.well-known/apple-app-site-association` — iOS universal links (requires `APPLE_TEAM_ID`)

### 4. Set Supabase Edge Function Secrets

```powershell
# Payment processing
supabase secrets set LIPILA_API_KEY=lsk_xxx
supabase secrets set LIPILA_WEBHOOK_SECRET=xxx
supabase secrets set LIPILA_PAYOUT_WEBHOOK_URL=https://daboihiudmglwhdfvsku.supabase.co/functions/v1/lipila-webhook

# Email / SMS
supabase secrets set RESEND_API_KEY=xxx
supabase secrets set EMAIL_FROM=noreply@churchonapp.com

# Cloudflare R2 (media storage)
supabase secrets set R2_ENDPOINT=xxx
supabase secrets set R2_ACCESS_KEY_ID=xxx
supabase secrets set R2_SECRET_ACCESS_KEY=xxx
supabase secrets set R2_BUCKET=xxx
supabase secrets set R2_PUBLIC_DOMAIN=media.churchonapp.com

# Firebase Cloud Messaging
supabase secrets set FCM_PROJECT_ID=xxx
supabase secrets set FCM_SERVICE_ACCOUNT='{...}'
supabase secrets set FCM_SERVER_KEY=xxx

# AI
supabase secrets set HUGGINGFACE_TOKEN=hf_xxx
supabase secrets set GEMINI_API_KEY=AIza_xxx   # Kael primary provider (Gemini Flash); HF is fallback

# IDs
supabase secrets set TREASURY_ID=xxx

# TURN Server (WebRTC calls)
supabase secrets set TURN_SERVER_URL=turn:turn.churchonapp.com:3478
supabase secrets set TURN_SECRET=xxx

# Apple (iOS universal links)
supabase secrets set APPLE_TEAM_ID=xxx
```

### 5. Run Database Migrations

Migration files in `supabase/migrations/` (applied in order by `deploy.ps1`).

Key migrations:
```
20260826_tenants_table.sql       # Creates tenants table, seeds from churches
20260826_add_churchid_tenantid.sql  # Adds tenant_id/church_id to all scoped tables
20260723_fix_quiz_competitions_payments.sql  # Fixes missing tables
```

Manual migration:
```powershell
supabase db query --linked --file supabase/migrations/<file>.sql
```

### 6. Verify Asset Links (Android App Links)

```powershell
# Check via Supabase Edge Function
curl https://daboihiudmglwhdfvsku.supabase.co/functions/v1/well-known/.well-known/assetlinks.json

# Check via public domain (after web deploy)
curl https://churchonapp.com/.well-known/assetlinks.json
```

Expected: 3 SHA-256 fingerprints + `get_login_creds` relation for credential sharing.

### 7. Flutter Analyze Before Release

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
# Target: 0 errors, 0 warnings in lib/
```

### 8. Complete Release Checklist

- [ ] All migrations applied
- [ ] Edge Functions deployed (especially `turn-credentials`, `well-known`, `lipila-webhook`)
- [ ] Web deployed to Cloudflare Pages
- [ ] Android APK/AAB built and signed
- [ ] `flutter analyze` passes (0 errors, 0 warnings)
- [ ] Google Play Console: assetlinks verified
- [ ] iOS: apple-app-site-association returns valid JSON
- [ ] TURN server env vars set (or STUN-only fallback active)
- [ ] `.env.example` updated with any new vars

## Remaining Known Issues

- All test files pass `flutter analyze` with 0 errors, 0 warnings (95 info-level issues only)
- `radio_service_test.dart` `getMetadataStream` test has 30s timeout due to internal 20s delay in the stream generator
- `.env` file in git history contains exposed keys (rotate in production)
- `profiles.tenant_id` uses `text` type instead of `uuid` — FK constraint on `tenants(id)` needs column type migration
- TURN server (Coturn) Edge Function created but requires deployment + environment variables (`TURN_SERVER_URL`, `TURN_SECRET`)
- iOS `apple-app-site-association` uses `APPLE_TEAM_ID` env var — must be set in Supabase Edge Function environment
- Website Google sign-in is handled by the Flutter web SPA; no separate `website/` directory exists
- `churches.id` and `tenants.id` are `uuid` type — registration code uses `package:uuid` v4, NOT string codes like `zm_1` or `ZM_CH_0001` (those are only in `tenant_service.dart` fallback data)
- Church registration screens upload logo files to R2 under `church-logos/{uuid}.jpg`
- **All coin/partner/code tables created**: `coin_purchases`, `coin_redemptions`, `partner_tenants`, `partner_offers`, `generated_codes`, `id_sequences` — applied via migrations `20260841` and `20260850`.
- Existing users with old referral codes (`COA-{UUID[0:8]}`) will keep them as aliases; new codes use `COA-{ISO}-REF-{XXXXXX}` format
- **Supabase linter**: 7 WARN `function_search_path_mutable` fixed (update_quiz_events_updated_at, get_user_avg_rating, check_admin_rate_limit); remaining functions may still trigger
- **Supabase linter**: 25 WARN `rls_policy_always_true` fixed (fundraising_contributions, group_contribution_members, group_contribution_payments, churches, transactions)
- **Supabase linter**: `anon` role EXECUTE revoked on ~55 SECURITY DEFINER functions
- **Supabase linter**: Leaked password protection requires manual toggle in Supabase Auth dashboard
- **Supabase linter**: 68 legacy migration files use `DO $ BEGIN` (single-dollar) syntax — these are already applied and non-re-runnable; comprehensive migration `20260832` covers critical fixes
- **All migrations clean**: Full deploy sweep applies 147 migrations with 0 failures (18 skipped by design: 6 deleted empty placeholders, 11 KJV seed batches already applied, 1 neutralized seed file). 15 previously-missing migrations (`20260845`–`20260857`) added to `deploy.ps1` and applied. Bible enhancement migration `20260803_133358_bible_nkjv_nlt_smart_features.sql` adds NKJV/NLT translations, `bible_chapters`, `reading_plan_entries`, `verse_notes`, `cross_references`, `bible_chapter_summaries` tables with full-text search on `bible_verses`. All function signature mismatches, text=uuid type mismatches, and policy name conflicts resolved with idempotent guards.
- **`live_stream_studio_screen.dart`**: Now wired to `UnifiedStreamService` which creates Cloudflare Stream live input via Edge Function (real RTMP/HLS). Previously only updated DB status without any actual video transmission. Route `/live-studio` registered in GoRouter. `delete_video` action added to `cloudflare-stream` Edge Function.
- **`Remember Me` feature**: Now fully functional. When unchecked: saves `remember_me = false` to SharedPreferences, splash screen checks flag and calls `supabase.auth.signOut()` to prevent session persistence. On sign out: clears `remember_me` and `remembered_email` from SharedPreferences.
- **Performance migration `20260842`**: Adds indexes on `messages(sender_id, conversation_id)`, `stream_chat_messages(stream_id)`, `fundraising_contributions(contributor_id)`, `live_streams(church_id, status)`, `community_communities(tenant_id)`, `community_members(community_id, user_id)`.
- **Container assertion crash fixed**: `AnimatedContainer` in `main_navigation_shell.dart` had `clipBehavior: Clip.hardEdge` without `decoration`, triggering Flutter assertion. Added `decoration: const BoxDecoration()`.
- **Release builds**: APK v1.0.0+251 (`build/app/outputs/flutter-apk/app-release.apk` 202.9MB), AAB v1.0.0+250 (`build/app/outputs/bundle/release/app-release.aab` 118.3MB). Bible smart features included.
- **Session 2026-08-03**: Bible enhancement migration applied, Bible verse service rewritten with smart features (search, reading plans, verse notes, cross-references, AI chapter summaries), flutter analyze 0 issues, deploy.ps1 fixed (Bible migration alphabetical order), AGENTS.md updated, all changes committed and pushed to origin/main (commit 4357167).
- **R8 optimization & Gradle performance (2026-07-30)**:
  - **Proguard enhanced**: 5 optimization passes, `allowaccessmodification`, `repackageclasses`, `mergeinterfacesaggressively` to shrink DEX size. Comprehensive keep rules for all feature models, Supabase/GoTrue/PostgREST, ExoPlayer/Media3, MapLibre, WebRTC, crypto libraries.
  - **Debug log stripping**: `-assumenosideeffects` strips `v/d/i` logs in release builds (reduces method count).
  - **Gradle caching**: Enabled `org.gradle.caching=true`, `org.gradle.parallel=true`, `configureondemand=true`.
  - **Resource shrinking**: `isShrinkResources=true` with R8 full mode removes unused resources.
  - **Keystore path fixed**: `key.properties` relative path corrected to `storeFile=upload-keystore.jks`.
  - **ABI splits**: Configured for APK builds (arm64-v8a 80.8MB, armeabi-v7a 64.5MB, x86_64 87.7MB) plus universal APK.
  - **Deno config**: Added `supabase/functions/deno.json` to resolve TypeScript import errors in Edge Functions.
  - **Paywall widget fix**: Fixed `use_build_context_synchronously` + `curly_braces_in_flow_control_structures` lints in `home_subscription_paywall.dart`.
- **Pre-launch audit fixes (2026-07-29)**:
  - **C1 — Lipila webhook auth bypass FIXED**: Removed Bearer token short-circuit that allowed bypassing HMAC signature verification with any `Authorization: Bearer anything` header. Now always requires valid HMAC-SHA256 signature in `x-webhook-signature` header when `LIPILA_WEBHOOK_SECRET` is configured. Body is read as text for signature verification before JSON parsing. (`supabase/functions/lipila-webhook/index.ts`)
  - **F1 — Subscription paywall bypass FIXED**: `home_screen.dart:177` had `&& isAdmin` gating the paywall, meaning only admins saw the expired-subscription block. Removed `&& isAdmin` so ALL users are blocked when the church's trial/subscription has expired.
  - **CRIT-1 — Null bang on Permission result FIXED**: `live_stream_studio_screen.dart:43` used `status[Permission.camera]!` which would crash if the map lacked that key. Replaced with `status[Permission.camera]?.isGranted ?? false` null-safe pattern.
  - **CRIT-2 — 17 unguarded `auth.currentUser!` FIXED**: Replaced across 8 admin service files (`writer_approval_service.dart`, `role_onboarding_service.dart`, `role_hierarchy_service.dart`, `order_service.dart`, `job_notification_service.dart`, `event_pass_service.dart`, `church_lead_service.dart`, `ad_payment_sheet.dart`) with null-safe guard: `final user = client.auth.currentUser; if (user == null) throw Exception("Not authenticated");`.
  - **CRIT-3 — Unguarded map lookups FIXED**: Fixed 12+ null-bang patterns on dialog result maps (`result['userId']!`, `result['role']!`, `field['key']!`) across `bishop_dashboard_screen.dart`, `bookshop_dashboard_screen.dart`, `superadmin_hub_screen.dart`, `subscription_pricing_screen.dart`, `prophetic_heatmap_screen.dart`, `finance_dashboard_screen.dart`, `ledger_screen.dart`. Replaced with null-safe pattern using local variables and null checks.
  - **Cross-tenant RLS leaks FIXED**: Migration `20260843` drops `USING (true)` SELECT policies on `social_posts`, `sermons`, `events`, `live_chat_messages`, `marketplace_items` and replaces with tenant-scoped policies: `tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())`. Also drops `Anyone can view marketplace items` policy. Adds superadmin override policy for `social_posts`. Adds quiz_results policies (own data only). Adds `coa_payments` columns (`webhook_idempotency`, `phone_number`, `network`, `settled_at`) + unique constraint + indexes.
  - **Quiz feature gating FIXED**: Added subscription check in `app_router.dart` redirect (routes `/quiz/*` redirected to home when subscription expired) and in `BibleQuizHubScreen.build()` (shows lock screen when subscription expired).
- **`flutter analyze` result**: 0 issues found (no errors, no warnings).
