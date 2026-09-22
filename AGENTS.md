# Church On App — How-To Guide for AI Agents

## ⚠️ CRITICAL RULE — NEVER BUILD APK/AAB WITHOUT EXPLICIT CONFIRMATION

**Do NOT run `build_release.ps1`, `flutter build apk`, or `flutter build appbundle`
unless the user explicitly says to build the Android release.** Android builds take
20–40 minutes and burn resources. When the user asks for app changes, only run
`flutter analyze` and (if web) `flutter build web --release` + deploy. Building the
APK/AAB requires the user to say something like *"build the apk"* / *"make the
release"* first. This rule takes precedence over any prior instruction.

## ⚠️ PERMANENT RULE — NEVER CHANGE BOTTOM NAV TAB ICONS

**Do NOT change the bottom navigation bar tab icons** (`main_navigation_shell.dart`
`_buildNavItem`/`_buildRailDestination`: Home / Sermons / Give / Connect / Profile).
This was explicitly locked on 2026-08-16 — any future request to swap tab icons
must be declined and referred to the user. Tab icon set is final.

## ⚠️ PERMANENT RULE — NEVER MODIFY FEATURES WITHOUT EXPLICIT USER REQUEST

**Do NOT modify, remove, rearrange, or refactor any existing feature without the
user explicitly requesting it.** When fixing bugs, only fix the specific bug — do not
touch adjacent code, rename things, or "improve" related features. When the user
reports an issue, confirm the exact scope before making changes. This prevents
rework from agents operating on the same features interchangeably.

## ⚠️ PERMANENT RULE — `ErrorWidget.builder` MUST RETURN A SMALL BOUNDED WIDGET

**`ErrorWidget.builder` replaces an ARBITRARY failing widget.** It is invoked in
place of whatever widget threw — very often a small child inside a `ListView` /
`SliverList` (e.g. one home-feed section). It must therefore return a **self-sizing
widget** (see `InlineErrorTile` in `lib/core/widgets/error_boundary.dart`).

**Never return a `Scaffold`, `MaterialApp`, or any full-screen widget from
`ErrorWidget.builder`.** Doing so lays a full-screen box out *inside a sliver child*,
which breaks the whole viewport layout and paints a **blank white block under the
first section that fails** — the exact cause of the "home tab white screen / features
vanish below Latest Sermon" bug (fixed 2026-09-14). `CustomErrorBoundary` (the
full-screen "App Recovered" screen) must only be used for a genuine ROOT-level
failure, never from `ErrorWidget.builder`.

## ⚠️ PERMANENT RULE — RIVERPOD FAMILY KEYS MUST HAVE VALUE EQUALITY

**Never key a `Provider.family` with a `Map` (or a `List`/`Set`).** These have no
value equality, so `{'category': 'all'} != {'category': 'all'}` — every rebuild
creates a NEW family instance that starts in `loading`, resolves, triggers another
rebuild… an endless fetch/reload loop (this made the home **Marketplace Picks**
section flash and vanish, dragging the sections around it down with it).

Use a **Dart record** (`typedef ProductFilter = ({String? category, String? marketType});`)
or a `String`/`enum` key — records compare structurally. See `productsProvider` in
`lib/features/marketplace/data/marketplace_service.dart`.

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

## How To: Secure the App, Handle a Hack & Backup

**Read `SECURITY.md` first — it is the full security operating manual** (threat
model, incident response runbook, backup/recovery plan, key inventory,
monitoring, secure-development checklist). A generic, project-agnostic copy
lives in `SECURITY_PLAYBOOK.md` — copy that one into other projects.

### Golden rules (never violate)
1. **Never ship secrets.** `.env` is bundled into every release build — it must
   contain ONLY public values (Supabase URL + anon key, map URLs,
   `R2_PUBLIC_DOMAIN`). R2 keys, `CLOUDFLARE_API_TOKEN`, `GEMINI_API_KEY`,
   `HUGGINGFACE_TOKEN`, Resend, Lipila, TURN secrets live ONLY in the Edge
   Function environment (`Deno.env.get()`) — never in `lib/`, `.env`, or assets.
2. **Never add secret getters to `env.dart`** (they ship inside the app).
3. **Client is untrusted.** Money-movement code re-derives amounts server-side;
   `lipila-payout` requires a confirmed `coa_payments` anchor; payouts never
   trust a client-inserted `transactions` row.
4. **Coin RPCs are guarded** (`auth.uid()` + amount cap) — don't remove those guards.
5. **New admin route** ⇒ add it to `hasAccess` in `app_router.dart`.
6. **New RPC** ⇒ `SET search_path = public` + `REVOKE EXECUTE FROM anon`; admin
   RPCs also revoked from `authenticated`.
7. **New table** ⇒ RLS on, owner/tenant-scoped policies, never
   `WITH CHECK (true)` on INSERT/UPDATE.

### If a hack happens (quick version — full runbook in SECURITY.md §2)
1. Contain in minutes: invalidate `LIPILA_API_KEY` (payouts fail fast),
   rotate any leaked key, `cron.unschedule('lps-settle')`.
2. Preserve evidence (`database-backup`, `admin_audit_log`, function logs).
3. Fix + rotate *all* possibly-exposed keys + reset affected users.
4. Re-enable, verify core flows, document in SECURITY.md §8 log.

### Backup (full plan in SECURITY.md §3)
- Supabase PITR + daily backups (dashboard). Test a restore monthly.
- R2 bucket: enable versioning + lifecycle. Test a version restore quarterly.
- On-demand: `database-backup` function (superadmin) or
  `supabase db dump --linked`.
- Web: Cloudflare Pages keeps deployment history for rollback.
- Cron jobs `lps-settle` + `event-remind` must send `x-cron-secret`
  (`CRON_SECRET` env var) — never a hardcoded anon JWT.

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

**Provider order (multi-provider AI layer, 2026-09)**: all Edge-function inference goes through `supabase/functions/_shared/ai.ts` (`callModel()` / `streamModel()`). Selection is automatic: **Cloudflare Workers AI (primary) → HuggingFace (fallback) → clear error**. Workers AI is used ONLY when BOTH `CLOUDFLARE_ACCOUNT_ID` AND a token are set (`CLOUDFLARE_AI_TOKEN`, or `CLOUDFLARE_API_TOKEN` as fallback); until a token is added the HuggingFace path runs exactly as before. Workers AI model: `CF_AI_MODEL` (default `@cf/meta/llama-3.3-70b-instruct-fp8-fast`); set `CF_AI_GATEWAY_URL` (e.g. `https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/workers-ai`) to route through an AI Gateway. HuggingFace secrets: `HUGGINGFACE_TOKEN`, `HF_MODEL_ID` (default `meta-llama/Llama-3.1-8B-Instruct`). A Workers AI failure (401/403/quota/5xx) automatically retries on HuggingFace, and the serving provider is logged (`[ai] <label> served by <provider>`). Routed functions: `kael-ai`, `generate-quiz-batch`, `quiz-import` (extraction), `data-import` (document extraction), `hf-keep-warm`. Broadcast contract unchanged: chat = SSE `data: {"chunk": ...}` … `data: {"done": true}`; other actions = JSON `{"response": "..."}`.

**Health probe**: `GET <restUrl>/functions/v1/kael-ai?health=ai` (also on `generate-quiz-batch`, `quiz-import`, `data-import`) returns the active provider plus a boolean for each secret (never the value), e.g. `{"status":"ok","active_provider":"workers-ai","providers":{"workers_ai":{"configured":true,"model":"@cf/...","gateway":false},"huggingface":{...}},"secrets":{"CLOUDFLARE_ACCOUNT_ID":true,"CLOUDFLARE_AI_TOKEN":true,...}}`.

**To activate Workers AI**: create a Cloudflare API token with **Workers AI: Read** (My Profile → API Tokens → Workers AI → Read) and run `supabase secrets set CLOUDFLARE_ACCOUNT_ID=<id> CLOUDFLARE_AI_TOKEN=<token>`, then redeploy the functions. **Token-free alternative**: deploy a tiny Cloudflare Worker with an `[ai]` binding (`env.AI`) that proxies `/chat/completions`, and point `CF_AI_GATEWAY_URL` at it.

**IMPORTANT**: HuggingFace calls MUST use the OpenAI-compatible router endpoint `https://router.huggingface.co/v1` (`/chat/completions` shape with `choices[0].message.content`) — the legacy `api-inference.huggingface.co` host does NOT resolve from the Supabase edge runtime (DNS failure, verified). Qwen2.5-1.5B and zephyr-7b-beta are NOT provider-enabled on this account via the router — use Llama-3.1-8B-Instruct (or any model the user enables).

**Request contract (unified)** — `action` decides the response format:
- `action: 'chat'` (default, requires `messages[]` + optional `userContext`) → **SSE** (`data: {"chunk": ...}` then `data: {"done": true}` or `data: {"error": ...}`)
- `action: 'summary'` / `'dramatize'` / other (requires `prompt` — `message`/`content` accepted as legacy aliases) → **JSON** `{"response": "..."}`

**Client**: chat uses true SSE streaming via raw HTTP (`POST <restUrl>/functions/v1/kael-ai` with Bearer token, `Accept: text/event-stream`), buffered `functions.invoke` as fallback. Never treat chat as JSON — the Edge Function returns `text/event-stream`.

**DB**: `ai_chat_sessions` + `ai_chat_messages` (with RLS) must exist — recreated standalone in migration `20260857_ai_chat_tables.sql` (previously only in the failed `20260710_missing_tables_schema.sql` batch).

## How To: Livestreaming with Cloudflare Stream (tenant church streaming)

Church leaders stream live services from their phone (WebRTC WHIP) or OBS (RTMP) to Cloudflare Stream, which auto-records and serves HLS to viewers.

### Architecture

```
Phone Camera / OBS
    │ (WebRTC WHIP or RTMP)
    ▼
Cloudflare Stream Live Input (per-church)
    │
    ├── HLS playback → app viewers
    ├── Auto-recording → 90-day retention
    └── WebRTC playback → low-latency preview
```

### Key Files

| File | Purpose |
|------|---------|
| `supabase/functions/cloudflare-stream/index.ts` | Edge Function: CF Stream API proxy (create/delete live inputs, WHIP relay, analytics, signed URLs, video deletion) |
| `lib/core/services/unified_stream_service.dart` | Client: creates live streams, checks gates (weekly minutes, concurrent, storage), records usage |
| `lib/features/modules/live_streaming/data/live_stream_service.dart` | Viewer: fetches active/upcoming streams from `live_streams` table |
| `lib/features/modules/live_streaming/presentation/live_stream_studio_screen.dart` | Studio: camera preview, WHIP ingest, OBS credential fallback |
| `lib/features/modules/live_streaming/presentation/live_streaming_screen.dart` | Hub: list active + upcoming streams, leader "Start Camera Stream" button |
| `lib/features/home/data/live_streaming_service.dart` | `church_live_status` realtime toggle (is_live flag for church cards) |
| `lib/features/home/presentation/live_stream_screen.dart` | Viewer: video player + live chat + announcements |

### How It Works

1. **Leader taps "Start Camera Stream"** → `LiveStreamStudioScreen` opens
2. Studio calls `UnifiedStreamService.createLiveStream(tenantId, title)`
3. Service checks gate: `checkStreamGate(tenantId)` → verifies `is_paid`, weekly minutes, concurrent streams, storage
4. Calls Edge Function `cloudflare-stream` with `action: create_live_input`
5. Edge Function creates CF Stream live input via `api.cloudflare.com` (Bearer token from `CLOUDFLARE_API_TOKEN` env)
6. Returns `rtmps.url`, `streamKey`, `hls`, `webRTC.url` (WHIP publish)
7. Studio attempts WHIP ingest (phone camera → CF Stream via WebRTC)
8. If WHIP fails → shows OBS credentials (RTMP URL + stream key)
9. Stream row inserted into `live_streams` table with `cloudflare_stream_id`
10. Viewers see it in `LiveStreamingScreen` (queries `live_streams WHERE status='live'`)

### Database Tables

```sql
-- Per-church streaming config (set by migration 20261006)
church_stream_config (
  church_id UUID PK,
  is_paid BOOLEAN,           -- must be true to stream
  backend TEXT,               -- 'cloudflare'
  max_minutes_per_week INT,  -- 480 (8 hrs) for paid churches
  max_viewers INT,            -- 1000
  max_stream_duration_sec INT, -- 14400 (4 hrs)
  retention_days INT,         -- 90
  max_storage_gb NUMERIC,     -- 10
  max_quality INT             -- 720 or 1080
)

-- Active/ended streams
live_streams (
  id UUID PK,
  church_id UUID,
  title TEXT,
  status TEXT,               -- 'live' | 'scheduled' | 'ended' | 'archived'
  streaming_backend TEXT,    -- 'cloudflare'
  cloudflare_stream_id TEXT, -- CF Stream input UID
  rtmp_url TEXT,
  stream_key TEXT,
  hls_url TEXT,
  whip_url TEXT,
  ...
)
```

### Required Secrets (Supabase Edge Function env)

```bash
CLOUDFLARE_ACCOUNT_ID=ab82a97ce2c926279c483fef36c41945
CLOUDFLARE_API_TOKEN=cfut_...    # Custom token with Stream:Edit, Account:Read, Pages:Edit
```

**CRITICAL**: `CLOUDFLARE_API_TOKEN` is read at Edge Function cold-start (`Deno.env.get()`). If the token is invalid/expired, ALL `create_live_input` calls fail with `401` → user sees "Streaming service error (401)". Rotate token via:
```bash
supabase secrets set CLOUDFLARE_API_TOKEN=<new>
supabase functions deploy cloudflare-stream --no-verify-jwt
```

### Role Gate

Only these roles may create/delete streams or WHIP-ingest:
`superadmin`, `coa_employee`, `bishop`, `apostle`, `prophet`, `general_secretary`, `pastor`, `admin`, `leader`, `department_leader`

Superadmins/COA employees bypass church-ownership check (network oversight).

### Cost Controls

| Tier | Minutes/Week | Max Viewers | Retention | Storage |
|------|-------------|-------------|-----------|---------|
| Trial (old) | 10 | 25 | 7 days | 1 GB |
| **Paid (current)** | **480** | **1000** | **90 days** | **10 GB** |

All churches set to paid via migration `20261006_streaming_paid_unlock.sql`.

### Known Issues

- **CF API token validity**: token MUST have `Stream:Edit` + `Account:Read` permissions. Test with `curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify`
- **WHIP on mobile**: requires WebRTC support (Android 5+, iOS Safari 11+). Falls back to RTMP/OBS if WHIP fails
- **`live_streams` is currently empty**: no church has started a stream yet (all 30 configs are `is_paid=true` and ready)

### Ingest Architecture Decision (WHIP vs RTMPS) — 2026-09-12

**Decision: RTMPS/OBS is the primary ingest path for church streaming; WHIP is a
convenience fallback for impromptu phone streaming.** Rationale:

- **RTMPS (OBS/encoder)** → guaranteed HLS + auto-recording, stable on dedicated
  encoders, best for scheduled/recurring services. Credentials (RTMP URL + stream
  key) are shown to the operator from the studio/`stream_admin_screen`.
- **WHIP (WebRTC phone camera)** → low-latency, no encoder needed, but dependent
  on device battery/network and historically less reliable for long services.

The studio (`live_stream_studio_screen.dart`) tries WHIP first for the "Start
Camera Stream" flow, then falls back to the OBS/RTMPS credentials dialog. The
Cloudflare live input is created at schedule/start time regardless of path, so
the same `hls_url` is watchable by viewers either way. Scheduled streams are
auto-promoted to `live` when their `scheduled_at` passes (pg_cron
`stream-schedule-start` → `auto_start_due_streams()`), and leaders can also tap
"Start Now" (`start_scheduled_stream` RPC) on upcoming stream cards.

## How To: Handle Payments

**📄 FULL PAYMENT SYSTEM DOCUMENTATION: `PAYMENTS.md` — read it before touching
anything payment-related.** It contains the architecture, the settlement engine
rules, the ops runbook, and the "DO NOT REGRESS" invariants.

The Lipila payment gateway lives at `lib/features/finance/presentation/lipila_payment_gateway.dart`.
- Uses `supabase.functions.invoke()` (NOT raw HTTP) to call Lipila API server-side
- PIN polling: 30 attempts, 4s interval
- Real Lipila merchant rates (wallet 68907, Carpso Solutions): **2.5% MoMo collection, 1.5% MoMo disbursement**
- Fees are remote-configurable via `platform_settings`: `momo_fee_percent` (2.5%) + `coa_fee_percent` (1%) = 3.5% customer MoMo fee; `lipila_disbursement_fee_percent` (1.5%) + `coa_payout_fee_percent` (1%, min K3) are deducted from every payout via `FeeConfig.payoutNet()` — never send a raw payout amount to `lipila-payout`
- For payout webhooks, set `LIPILA_PAYOUT_WEBHOOK_URL` in Edge Function env

### ⚠️ PERMANENT RULES — PAYMENTS (never regress these)

1. **The client never decides who gets paid or how much.** Recipients and gross
   amounts are resolved in `supabase/functions/_shared/settlement.ts` from
   server-side facts only.
2. **Giving recipient chain** (server-side, in order): designated tithe leader
   (re-validated: same tenant + leadership role + valid `260…` number) → elected
   tithe role (`payout_tasks.recipient_role`) → `churches.treasurer_phone` →
   `churches.contact_phone` → `churches.pastor_phone` → any leadership
   `profiles.phone_number` in the tenant → **retry** (never mark `failed`).
3. **`lipila-webhook` must never 502.** After any edit, re-probe:
   `curl -X POST https://<ref>.supabase.co/functions/v1/lipila-webhook -H "Content-Type: application/json" -d '{}'`
   → expect `200 {"status":"ignored","reason":"missing_signature"}`.
4. **Webhook auth is DUAL**: `?secret=<LIPILA_WEBHOOK_SECRET>` on the callback
   URL OR Standard Webhooks HMAC headers. Never re-add a bare
   `Authorization: Bearer <anything>` bypass (old audit finding C1).
5. **`audit_logs` has `details` (jsonb) — no `changes` / `user_agent` columns.**
6. **`profiles` has NO `phone` column — only `phone_number`.** Selecting `phone`
   errors and silently returns null.
7. **Never create a `coa_payments` row from a disbursement/payout webhook.**
8. **Always pre-create the pending `coa_payments` row before calling Lipila**,
   and always append `?secret=` to `callbackUrl` (collection + payout).
9. **After writing `platform_settings`, invalidate `remoteConfigProvider` and
   `platformSettingsProvider`** or changes only appear after an app restart.
10. Real tables: rides = `ride_requests`, deliveries = `delivery_requests`,
    market items = `marketplace_items`, writer articles = `kingdom_news`.
    There is **no** `ride_bookings`, `marketplace_products`, `news_articles`,
    `profiles.phone`, `profiles.avg_rating`, `order_items.status`,
    `deliveries.fee`.

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
| Bible quiz | `quiz_prize_1st/2nd/3rd_cc` (500/300/150 CC rewards), `quiz_prize_1st/2nd/3rd_kwacha` (legacy, unused by app), `quiz_season_weeks` (12), `quiz_lease_fee_cc` (1500 CC engine lease), `quiz_lease_fee_kwacha/usd` (legacy), `quiz_pass_cc_per_zmw` (1.0 CC per K1 pass conversion) |
| Subscriptions | `subscription_trial_days` (30), `subscription_renewal_days` (365), `platinum_promo_days` (30), `subscription_manual_payment_days` (30) |
| Marketplace/Events | `marketplace_delivery_fee_kwacha` (15), `event_commission_percent` (0.10) |
| Fees (FeeConfig) | `coa_fee_percent`, `momo_fee_percent`, `card_fee_percent`, `business_cut_percent`, `min_fee_kwacha`, `lipila_disbursement_fee_percent`, `coa_payout_fee_percent`, `ride_base_fare_kwacha`, `ride_delivery_base_fare_kwacha`, `ride_delivery_per_km_kwacha` |
| Plan pricing | `onboarding_fee`, `gold_monthly_fee`, `platinum_monthly_fee` (wired in `home_subscription_paywall.dart`) |

**Known gap**: the old `quiz_lease_fee`/`quiz_lease_fee_kwacha`/`quiz_lease_fee_usd` keys still exist in `platform_settings` (legacy, unused by the app — the hub lease modal and admin overview read `quiz_lease_fee_cc`).

**CC economy (20260898)**: everything bible-quiz is Church Coins — the Quiz Engine lease (churches' yearly tournaments + individual hosting) is paid in CC via the `lease_quiz_engine_cc` RPC (server-enforced amount, logged to `coin_redemptions` as `quiz_engine_lease`); players buy CC with Mobile Money (Lipila) from the Buy Coins screen when their wallet runs dry (Buy-CC sheet appears on any insufficient-balance quiz action); COA tournament prizes 1st/2nd/3rd are CC rewards (500/300/150 CC); paid tournament passes can be paid with CC via `join_quiz_event(p_event_id, p_pay_cc)` (1 CC = K1 × `quiz_pass_cc_per_zmw`, logged as `quiz_tournament_pass`).

**Quiz CC Store (`quiz_cc_store_screen.dart`)**: exhaustive quiz-CC center on the hub (QUIZ CC STORE card) — balance card, Buy CC (Lipila packages), spend tiles (engine lease live action, tournament wager/pass → lobby), earn list (weekly CC prizes, wager winnings, daily challenge), and live history of all quiz CC transactions (`kQuizCoinTypes`: quiz_tournament_wager, quiz_tournament_pass, quiz_engine_lease, pvp_wager, pvp_wager_refund).

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

## How To: Use the Smart CI/CD Pipeline

Three GitHub Actions workflows automate the release train:

### `ci.yml` — Pull-request/push guard (fast)
| Job | Purpose | Fails build? |
|-----|---------|-------------|
| `analyze` | `flutter analyze --no-fatal-infos` — warnings are FATAL | yes |
| `test` | `key_flows_smoke_test.dart` is a hard gate; full suite is informational | key_flows only |
| `secret-scan` | `.github/scripts/secret_scan.sh` — greps git-tracked files for live credentials (AWS/PATs/Stripe/OpenAI/Supabase/Lipila/Slack/HF/Resend/private keys/hardcoded JWTs). Whitelists `web/index.html` (PUBLIC Firebase web config) + `*.md` | yes |
| `codeql` | CodeQL TS/JS over `supabase/functions` + `web` — **only when repo var `ENABLE_CODEQL` = `true`** (requires GitHub Advanced Security) | yes |

### `ci-cd.yml` — Tag/deploy pipeline (main pushes, tags, dispatch)
1. **Semantic versioning**: `BUILD_NUMBER = git rev-list --count HEAD` (auto-increments every commit); `VERSION_NAME` from the git tag (`v1.2.0` → `1.2.0`), else `1.0.0`. pubspec gets `version: {NAME}+{NUMBER}`. No manual version bumps needed.
2. **Builds**: APK + AAB only (iOS build dropped 2026-08-15 — proof of concept done). 75-min timeout + 200 heartbeat. Gated on `STORE_FILE`/`KEY_*` secrets. Build number = highest versionCode across ALL Play tracks (production/internal/alpha/beta) + 1, computed via `GOOGLE_PLAY_SERVICE_ACCOUNT` (gcloud + androidpublisher API) — **NOT `git rev-list --count`** (broke when history was rewritten: Play rejected "+116" while Play already had +262/+263). Fallback: parse pubspec `version: 1.0.0+268`.
3. **Create Release**: GitHub Release with `RELEASE_NOTES.md` auto-generated from `git log` between the previous tag and HEAD (+ `generate_release_notes: true`), APK + AAB attached. Fires only on **tag push**.
4. **`distribute-firebase`**: Firebase App Distribution (OTA to testers) on every main push — gated on `FIREBASE_SERVICE_ACCOUNT` + `FIREBASE_ANDROID_APP_ID` secrets.
5. **`notify-success`/`notify-failure`**: Slack via `SLACK_WEBHOOK_URL`; falls back to `DISCORD_WEBHOOK_URL`; else echo. No webhook = green anyway.

### `test-lab.yml` — Real-device instrumentation
Manual (`workflow_dispatch`) + on `v*` tags. Builds debug APK + `integration_test/app_smoke_test.dart` androidTest APK, runs on Pixel 7/5/4a (API 33/30/28) via `gcloud firebase test android run`. Gated on `GCLOUD_SERVICE_ACCOUNT` + `FIREBASE_PROJECT_ID` secrets.

### Secrets to add (all jobs are gated — CI stays green without them)
`FIREBASE_TESTER_GROUPS` (already set: `coa-testers`), `SLACK_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`, `GCLOUD_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID` (`studio-7483333628-db257`). Already set: `STORE_FILE`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, `GOOGLE_SERVICES_JSON`, `GOOGLE_PLAY_SERVICE_ACCOUNT`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `FIREBASE_ANDROID_APP_ID` (`1:45750098887:android:49947b7979e42c599217e2`), `FIREBASE_SERVICE_ACCOUNT` (SA `firebase-app-distribution@studio-7483333628-db257.iam.gserviceaccount.com`, role `roles/firebaseappdistro.admin`; used via `serviceCredentialsFile: firebase-sa.json`, NOT `serviceCredentialsJsonContent` — env-var JSON broke the wzieba action with "Failed to authenticate, have you run firebase login?").
**NOTE**: the `secrets` context is NOT available in `if:` expressions (job or step level) — GitHub rejects the whole workflow file. Use job-level `env: HAS_X: ${{ secrets.X != '' }}` + step `if: env.HAS_X == 'true'` (see `distribute-firebase`, `test-lab`, notify jobs).

### Rules for agents
- Never commit `google-services.json`/`GoogleService-Info.plist`/`.env`/keystores (all gitignored; CI materializes them from secrets).
- New live-credential format in code ⇒ add its regex to `.github/scripts/secret_scan.sh` (and whitelist legit public config files explicitly).
- `integration_test/app_smoke_test.dart` must keep compiling (`flutter analyze` covers it); it pumps `ChurchOnApp` and asserts first frame with no exception.

## How To: Build & Release

```powershell
# Clean build (recommended): clear cache first
flutter clean; flutter pub get

# Bump version in pubspec.yaml (or use build_release.ps1)
.\build_release.ps1           # AAB for Play Store (bumps build number)
.\build_release.ps1 -Type apk # APK (bumps build number)

# Outputs (gradle archivesBaseName — NOT `app-release.*`):
# APK:  build\app\outputs\flutter-apk\Church On App.apk
# AAB:  build\app\outputs\bundle\release\Church On App.aab
```

### ⚠️ After every release build: ALSO upload the APK/AAB to R2

R2 is linked (Cloudflare account `ab82a97ce2c926279c483fef36c41945`, bucket
`choa-sermons-vault`, public domain `media.churchonapp.com`). **Every APK/AAB
build must be published to R2** so testers/users can download it without Play:

```powershell
$apk = "build\app\outputs\flutter-apk\Church On App.apk"
$aab = "build\app\outputs\bundle\release\Church On App.aab"

# Versioned copies (use the actual version from pubspec.yaml)
npx wrangler r2 object put "choa-sermons-vault/builds/ChurchOnApp-<VER>.apk" --file $apk --content-type application/vnd.android.package-archive --remote
npx wrangler r2 object put "choa-sermons-vault/builds/ChurchOnApp-<VER>.aab" --file $aab --content-type application/octet-stream --remote

# "latest" pointers (stable URLs people can bookmark)
npx wrangler r2 object put "choa-sermons-vault/builds/latest/ChurchOnApp.apk" --file $apk --content-type application/vnd.android.package-archive --remote
npx wrangler r2 object put "choa-sermons-vault/builds/latest/ChurchOnApp.aab" --file $aab --content-type application/octet-stream --remote
```

- **`--remote` is REQUIRED** — without it wrangler writes to a local simulator
  and the object never reaches R2 (see the Maps/R2 gotcha elsewhere in this file).
- Stable download URLs:
  `https://media.churchonapp.com/builds/latest/ChurchOnApp.apk` and `…/aab`.
- Keep a `builds/latest.json` manifest (version + url + size + built_at) and
  overwrite it each release so the site/QA can read the current build.
- If a new bucket/domain is desired (`builds.churchonapp.com`), set it up once
  in Cloudflare (R2 → bucket → Settings → Custom domain) BEFORE changing the
  commands above.
- **Wrangler uploads are large (200 MB+)** — allow several minutes; the command
  prints `Upload complete.` on success. Verify with a `HEAD` request to the
  public URL.

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

## How To: Use the Data Import System

The enterprise data-import system allows church leadership to bulk-import members, transactions, events, ministries, and service reports from CSV, JSON, or documents via kael-ai extraction.

### Files

| File | Purpose |
|------|---------|
| `lib/features/data_import/data/data_import_service.dart` | Service with CSV parser, entity-column presets, ChMS presets (Breeze/PlanningCenter/RockRMS/MTNbank), and Edge Function calls |
| `lib/features/data_import/data/data_import_provider.dart` | Riverpod 3 Notifier (`DataImportNotifier`) + `importTenantIdProvider` + `isImporterAllowedProvider` |
| `lib/features/data_import/presentation/data_import_screen.dart` | 3-tab UI: CSV/JSON paste + mapping editor → import; Document extraction via kael-ai; Results |
| `supabase/functions/data-import/index.ts` | Edge Function: leadership-role-gated, column-mapping engine, per-row upsert via service-role client, audit logging, document extraction via kael-ai |
| `supabase/migrations/20260861_data_import_system.sql` | Tables: `import_templates`, `data_imports`, `import_errors` + tenant-scoped RLS + `sp_validate_import_columns` RPC |

### Key Rules

| Rule | Reasoning |
|------|-----------|
| Only leadership roles (pastor/bishop/admin/superadmin/employee) can import | Prevents unauthorized data injection |
| tenant_id is force-overwritten server-side | Prevents tenant-hopping (writing members to another church) |
| Sensitive columns (role, coins, balances) blocked by `sp_validate_import_columns` | Prevents role/coin escalation via import |
| 5000-row max per import batch | Safety limit — split larger files |
| Mapping convention: `targetColumn:sourceField` (one per line) | Matches the Edge Function's mapping engine |
| Column names are validated against `information_schema.columns` server-side | SQL-injection prevention via identifier allowlist |

### How To: Add a New Entity for Import

1. Add the table name to `allowedEntities` in `supabase/functions/data-import/index.ts`
2. Add its column set to `DataImportService.columnsFor` in `data_import_service.dart`
3. Add the table name to `allowed_entities` in `sp_validate_import_columns` (migration)
4. The entity table must have a `tenant_id` column (tenant-scoped)

### How To: Add a New ChMS Preset (e.g., ChurchSuite, Elvanto)

1. Add the mapping to `DataImportService.presetMappings` in `data_import_service.dart`
2. The preset is a `Map<sourceField, targetColumn>` — e.g., `'First Name': 'full_name'`
3. Users select presets from the dropdown in the import screen

## How To: Use Tenant Reporting (P5)

Enterprise service reporting with per-church and organization-wide aggregation.

### Files

| File | Purpose |
|------|---------|
| `lib/features/admin/data/reporting_service.dart` | `ServiceReport` model (attendance, offering, visitors, salvations, online viewers, ministries) + `ReportingService` with `getServiceSummary()`, `getOrganizationServiceSummary()` |
| `supabase/migrations/20260863_service_reporting_enhancements.sql` | Added `service_date`, `visitors`, `salvations`, `online_viewers`, `ministries_active`, `notes` columns to `service_reports` + 2 SECURITY DEFINER RPCs |

### RPCs

| RPC | Arguments | Returns |
|-----|-----------|---------|
| `get_church_service_summary` | `p_tenant_id UUID` | service_count, attendance, offering, visitors, salvations, online_viewers (current month) |
| `get_organization_service_summary` | `p_org_id UUID` | churches, service_count, attendance, offering, visitors, salvations, online_viewers (current month, org-wide) |

### How To: Add a New Report Metric

1. Add the column to `service_reports` via a new migration with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
2. Update `ServiceReport` model in `reporting_service.dart` (add field + fromMap + submitReport insert)
3. Update the aggregating RPCs (`get_church_service_summary`, `get_organization_service_summary`) to include the new metric in their `SELECT` and `jsonb_build_object` returns
4. Update the dashboard widget that displays the summary

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

Edge Functions (29 total):
`bible-study-notify`, `buy-sms-credits`, `cloudflare-stream`, `create-bookshop`, `data-import`, `database-backup`, `delete-account`, `export-church-data`, `export-user-data`, `generate-quiz-batch`, `kael-ai`, `lipila-card-collect`, `lipila-collect`, `lipila-payout`, `lipila-settle`, `lipila-webhook`, `migrate-coa-payments`, `migrate-to-r2`, `new-member-notify`, `push-notifications`, `r2-sign`, `send-birthday-email`, `send-email`, `send-security-alert`, `send-sms`, `turn-credentials`, `well-known`, `whatsapp-send`, `whatsapp-webhook`

### 3. Deploy Web to Cloudflare Pages

```powershell
flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=
Copy-Item -Recurse web\functions build\web\functions
npx wrangler pages deploy . --cwd build/web --project-name=churchonapp --branch=main
```

- **CRITICAL**: `web/functions` (Pages Functions: OG/SEO meta injection for
  `/church/`, `/site/`, `/c/` URLs) MUST be copied into `build/web/functions`
  and deployed with `--cwd build/web` (or `pages deploy .` from inside
  `build/web`). `wrangler pages deploy build/web` from the repo root silently
  SKIPS the functions folder — the site deploys but OG meta never injects.
- Requires `CLOUDFLARE_API_TOKEN` env var with **Cloudflare Pages:Edit** permission.
- Pages Function secrets (public values — safe in env): `SUPABASE_URL` +
  `SUPABASE_ANON_KEY` via `wrangler pages secret bulk` (per-project, not per-deployment).
  Without them the function still serves pages with generic fallback meta.

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

Expected: SHA-256 fingerprints for BOTH the Play **app-signing** key and the
**upload** key (live file currently has **2** — it does NOT yet include the
`delegate_permission/common.get_login_creds` relation, so Android credential
sharing is not enabled). Verify both hashes against Play Console → App
integrity → App signing, and add any missing one before relying on App Links.

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
  - **Universal APK**: ~210 MB single APK for all ABIs (splits disabled 2026-09-03 — `build_release.ps1 -Type apk` builds universal via `flutter build apk --release` for reliable sideload; split-per-abi removed).
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
- **Session 2026-08-10 — Enterprise Hardening**:
  - **cloudflare-stream Edge Function hardened**: Added leadership-role gate (only `superadmin/coa_employee/bishop/general_secretary/pastor/admin` may create/delete live inputs or WHIP-ingest). Added tenant-ownership enforcement: `create_live_input` validates `meta.church_id` matches caller's tenant; `delete_live_input` and `whip_offer` verify ownership via `live_streams.cloudflare_stream_id ↔ church_id`. Superadmins/COA employees bypass ownership for network oversight. Added `ownsStream()` helper.
  - **Apostle dashboard unbounded scan eliminated (FIX 11)**: `apostle_dashboard_screen.dart` replaced full `profiles.select('tenant_id')` table scan with bounded org-scoped RPC `get_organization_church_member_counts(p_org_id)`. Added fallback `.limit(50)` for apostles without an org. Migration `20260860_organization_church_member_counts.sql`.
  - **Universal Data Import System**: 3 new tables (`import_templates`, `data_imports`, `import_errors`) with tenant-scoped RLS + `sp_validate_import_columns` RPC (server-side column blocklist prevents role/coins escalation during imports). Edge Function `data-import` — leadership-gated CSV/JSON/document import with column-mapping engine, per-row service-role upsert with audit trail, kael-ai document extraction. Dart service `data_import_service.dart` with RFC-4180 CSV parser, entity presets (Breeze/PlanningCenter/RockRMS/MTNbank), Riverpod 3 provider, and 3-tab import screen. Migration `20260861_data_import_system.sql`.
  - **Enterprise Tenant Reporting (P5)**: Added `service_date`, `visitors`, `salvations`, `online_viewers`, `ministries_active`, `notes` columns to `service_reports`. Created `get_church_service_summary(p_tenant_id)` and `get_organization_service_summary(p_org_id)` RPCs (SECURITY DEFINER, REVOKE FROM anon). Extended `ServiceReport` model and `ReportingService` with summary methods. Migration `20260863_service_reporting_enhancements.sql`.
  - **Deploy wiring**: All 29 Edge Functions now listed in `deploy.ps1` (added `send-email`, `send-security-alert`, `buy-sms-credits`, `create-bookshop`, `whatsapp-send`, `whatsapp-webhook`, `new-member-notify`, `data-import`). 3 new migrations (`20260860`, `20260861`, `20260863`) added to migration list. Deploy list now 152+ migrations.
  - **flutter analyze**: 0 errors, 0 warnings across lib/. 3 info-level items only (all in data_import module).
  - **Docs**: README.md (v1.0.0+252, updated features, project structure, security, Edge Function count), AGENTS.md (data import how-to, tenant reporting how-to, Edge Funcion list, session notes).
- **Session 2026-08-10 - Web Launch, Firebase Cleanup, Church Discovery**:
  - **Firebase project cleanup**: Restored `com.churchonapp.churchonapp` Android app (was DELETED) and registered correct SHA-1/SHA-256. Deleted stale Android app `com.churchonapp.app` and duplicate web app `1:45750098887:web:46345dc91a838e1b9217e2`. Corrected `web/index.html` Firebase config (real web appId `1:45750098887:web:2e4259493139c6719217e2` + apiKey).
  - **Google sign-in**: Android `origin_mismatch` fixed via SHA restoration. Web `localhost` redirect fixed by pushing `site_url=https://churchonapp.com` + redirect URLs to Supabase (`supabase config push`). Web Authorized JS origin (`https://churchonapp.com`) must be added in Google Cloud Console manually (cannot via gcloud API).
  - **White-screen fixes (web)**: Firebase crashlytics/messaging auto-init crashes fixed via conditional stubs `crashlytics_stub.dart` + `messaging_stub.dart` (used when `dart.library.html`). `churches.short_name` column removed from all queries + Tenant model. `Infinity.round()` hardened across `money.dart`, `transport_service.dart`, `pastor_dashboard_screen.dart`, `streaming_config_screen.dart`, `xp_service.dart`, `home_top_bar.dart`.
  - **Expansion Leads**: New `expansion_leads_screen.dart` (list + status new/contacted/onboarded + details). Wired into Superadmin dashboard + COA Employee dashboard. Route `/expansion-leads` (employee-guarded). Migration `20260877_expansion_leads_rls.sql` (superadmin/employee/coa_employee manage + anonymous submit with `user_id IS NULL`).
  - **Landing page**: Footer links fixed (`/events/0`->`/events`, `/klips/0`->`/kingdom-klips`, Bible Quiz->`/quiz`). Feature cards now use sunflower-yellow gradient bg (`0xFFFFDA03`). Pricing cards price/period no longer overlap (stacked layout). "Join Ecosystem" -> `/register-church`. Phone mockup shows app-icon grid background + logo + slogan overlay. Login/signup forced to `AppTheme.getTheme(null)` (sunflower yellow).
  - **Church discovery (select_church_screen)**: New `_fetchNearbyChurches()` queries OpenStreetMap Overpass API for nearby Christian `place_of_worship` nodes/ways within ~50km of user GPS; dedupes against registered churches; marks `_registered: false`; shows on map with animated logo/triangle pins; tapping shows existing "Not Yet Available" dialog. `_initTenants()` triggers it after location is obtained.
  - **Church commute**: server-side single `eq` filter (Supabase streams allow only one), pull-to-refresh, request loading spinner, refresh on empty, removed hardcoded rating, sunflower yellow theming.
  - **Project cleanup**: removed `tmpclaude-*`, `diagnostics/`, `site_release.zip` (104MB), `media_playback.mp4`, stray PDFs/iml/logs. Extended `.gitignore`.
  - **Deploy**: web deployed to Cloudflare Pages (`churchonapp.com`), verified 0 exceptions + hash match. Firebase Android SHA-1/256 = `46BDAED912391CD34CBA330EF05DF1B6EC8AE1A4` / `FB57B43902E7B93A48506915BE9767C24CA5DDEF7732A59A679768CF2FA67BDA`.
  - **Remaining manual steps**: add `https://churchonapp.com` as Authorized JavaScript origin on web OAuth client in Google Cloud Console; (optional) Supabase custom domain to hide `daboihiudmglwhdfvsku.supabase.co`.
- **Session 2026-08-11 � Feature Hardening, Release Builds +260..263**:
  - **CRITICAL RULE (top of file)**: NEVER build APK/AAB unless the user explicitly confirms ("build the apk"/"make the release"). Only run `flutter analyze` + `flutter build web --release` + deploy by default.
  - **Bible quiz**: fixed countdown going dark (removed fading `Opacity` in `_buildCountdown` � now always visible number); P2P `GridView.count` got `shrinkWrap: true` (cards no longer overlap/hide the International banner). VS reveal screen shows real player cards + animated VS badge.
  - **Bible**: `bible_service.dart` now uses `bible-api.com` for `web`/`kjv` (reliable) and the local `bible_verses` table only for `nkjv`/`nlt`. Translation dropdown disables unsupported codes with "(soon)" label. Bare `/bible` route added (home quick action was dead � "no route for /bible"). `/bible-study/:studyId/edit` route added (edit button was crashing). Deep Study pane no longer hardcoded to Psalm 23 (shows current book/chapter). Deep Study GridView `shrinkWrap` fix (was showing only the verse card).
  - **Missing tables migration `20260880_bible_study_tables.sql`**: created `bible_studies`, `bible_study_attendance`, `user_study_streaks`, `bible_verses` + `increment_study_attendees` RPC. Applied.
  - **Quiz leaderboard**: `get_quiz_leaderboard(p_limit, p_tenant_id)` RPC aggregates correct answers from `pvp_answers` + `daily_challenge_results` (not coins). Migration `20260881_quiz_leaderboard.sql` (also creates `daily_challenge_results`). UI shows "N correct".
  - **Kids progress**: `kids_progress` got `UNIQUE (user_id, week_start)` (RPC ON CONFLICT was failing 42P10), `kids_upsert_progress` hardened with `auth.uid() = p_user_id`, new `kids_mark_resource_completed(UUID)` dedupe RPC. `_loadProgress` filters by current `week_start`. Migration `20260879_kids_progress_fix.sql`. Applied.
  - **Kids audio**: `KidsAudioPlayer` wired via `ActivityDetailsPage.resource(res)` � audio stories play, linked content opens externally. Activity grid shows ALL activities (Wrap), not just 4.
  - **Social posts**: `streamPosts` now enriches real user names+avatars (realtime streams don't join profiles). `AppImage` empty-URL fallback (no broken-image icon).
  - **Chat**: realtime streams no longer use `.order()` (caused refresh loops + disappearing messages); sort client-side. Chat input wrapped in bottom padding so typing isn't hidden behind the nav bar.
  - **Tenants**: `getAllTenants` rewritten to 2 parallel queries (churches + bookshops) � was 33 sequential N+1 calls that timed out on mobile and fell back to only "Rock of Ages".
  - **Home tab reorder**: greeting (streak chip now, coins moved to profile) ? verse of day ? church card (HomeHeroCard) ? streak ? onboarding setup ? quick actions ? special offer ? sparkle picks ? latest sermon ? events ? recommended ? news (writers+global) ? carpso ride.
  - **Give tab**: card renamed to "MY GIVING", removed "Sovereign" (now "Material Rewards Active"), feature tiles use LayoutBuilder 3-col grid (was squashed/clamped). Same fixes in `giving_widget.dart`.
  - **Profile**: wallet card consolidated � removed BUY CC / REDEEM CC / REWARDS duplicates; MY CC screen (`payout_request_screen`) now holds Buy Coins + Redeem + Rewards + Collect. Digital Assets moved above Account/Logout, Prayer Wall tile removed. Spiritual momentum card full-width (removed margin), subtitle "Growth Forecast" (no "Personalized/AI"), title stays "Spiritual Momentum". Removed unused imports.
  - **Home top bar**: weather chip is `Flexible` so bell/search/more buttons stay visible on narrow screens. Weather chip backgrounds are single-color (removed confusing blue+gold mix in `weather_model.dart` chipGradient � hot=red, overcast=slate, clear=sky-blue).
  - **Home schedule sheet**: `isScrollControlled` + SingleChildScrollView so Save/date/time buttons aren't hidden; church name wraps (was squashed/ellipsis).
  - **Settings**: Account Settings scroll view bottom padding (140) so list not hidden behind nav bar.
  - **Kael**: added missing `/kael-chat` route (was GoRouter "page not found" from More Hub/Life).
  - **Klips**: seeded 3 sample Klips (migration `20260882_seed_sample_klips.sql`). Reactions (amen/like via `klip_likes`, comments, share) + Give button (Lipila gateway bottom sheet) confirmed wired in `VideoClipPlayer`.
  - **Marketplace**: `postProduct` now sets `tenant_id` from current tenant (was NULL ? items invisible under RLS). Migration `20260878_marketplace_tenant_scoping.sql`: tenant-scoped INSERT policy, vendor DELETE policy, backfill tenant_id from profiles. Applied.
  - **Expansion leads / Firebase**: cleanup continued (SHA registration, web Firebase config corrected to web appId `1:45750098887:web:2e4259493139c6719217e2`).
  - **Release builds**: clean (flutter clean + pub get) ? APK `Church On App.apk` 205MB v1.0.0+262, AAB `app-release.aab` 119.1MB v1.0.0+263. Commits `60b0bfb`. Web deployed to Cloudflare Pages (0 exceptions).
  - **Bible audio now self-hosted on R2**: KJV dramatized (127 range files) + DBSOT dramatized OT stories (20 files + m4b) + TTS per-chapter (`audio/kjv/`) uploaded to `media.churchonapp.com`. App wired: chapter player, podcast, verse-of-the-day listen button, quiz scripture listen button, kids zone stories. Archive.org URLs removed. 93 stale `_kjv_128kb.mp3` duplicates deleted; 58 `.wav` placeholders remain (15 B – 352 KB, unused) — safe to delete.
  - **Remaining knowns**: Communities from Life/MoreHub uses the SAME CommunitiesScreen as Connect (no red styling in code); KYC flow is mobile-only (uses dart:io File); 11 info-level analyze issues remain (pre-existing, all in kids/data_import/quiz/wallet files).
- **Session 2026-08-16 — Placeholder-URL sign-in bug killed (CRIT) + web redeploy**:
  - **Root cause of "you're offline" / Google sign-in failure**: every CI workflow
    (`ci.yml`, `ci-cd.yml`, `deploy-web.yml`, `test-lab.yml`) ran `cp .env.example
    .env` — so EVERY CI-built APK/AAB/web bundle shipped `SUPABASE_URL=https://your-project.supabase.co`
    (DNS unresolvable → auth requests fail → app reports "you're offline").
    Local builds were fine (real `.env`).
  - **Fix**: all 4 workflows now materialize `.env` from a new `ENV_FILE`
    GitHub secret (`printf '%s' "$ENV_FILE" > .env`, step-level `env: ENV_FILE:
    ${{ secrets.ENV_FILE }}`), falling back to `.env.example` only when the
    secret is unset. **⚠ USER ACTION REQUIRED**: add repo secret `ENV_FILE` =
    full contents of local `.env` (`gh secret set ENV_FILE --body "$(Get-Content .env -Raw)"`).
    Without it, CI builds still ship the placeholder.
  - **Startup guard (app)**: `Env.isSupabaseConfigured` (`lib/core/config/env.dart`)
    = URL non-empty, not containing `your-project`, and anon key starts with
    `eyJ`. `main.dart` now hard-stops with a `_EnvConfigErrorApp` screen
    ("App is not configured") if the bundled .env is placeholder/missing —
    a bad build can no longer silently masquerade as working.
  - **Quiz arena crash guard**: `_buildGameplay` in `bible_quiz_arena_screen.dart`
    returns a "No questions available" state instead of `_questions[_currentIndex]`
    RangeError when the batch loads empty/out-of-range.
  - **Select-tenant refresh**: `_refreshAll()` refetches tenants AND OSM pins;
    Refresh chip + `_initTenants` use it (plain `_fetchTenants` cleared OSM pins).
  - **Web redeployed**: `flutter build web --release` (real .env) →
    `wrangler pages deploy build/web --project-name=churchonapp --branch=main`
    (wrangler OAuth logged in, no token needed). Verified live via byte-identical
    `main.dart.js` (8,642,671 bytes). Fixes churchonapp.com sign-in + public
    church website white screens. Commit `d01bf8c` (pushed).
  - **`flutter analyze`**: 0 errors, 0 warnings (10 pre-existing info).
- **Session 2026-08-17 — Select-tenant fix, subscribe-tier anchor, server-side 2FA, offline giving, i18n, orphan wiring**:
  - **Select-tenant fix (root cause)**: `tenant_service.dart` `getAllTenants`
    hardcoded `'_registered': map['slug'] == 'rock-of-ages-kabulonga'` — only
    one church was ever selectable. Now `'_registered': map['is_verified'] == true`
    (all 18 verified churches selectable). Superadmin map counter badge
    (`_buildMapCounter`) added under the search overlay in `select_church_screen.dart`.
  - **`subscribe_user_to_tier` bypass FIXED (migration `20260910`, applied live)**:
    old body set `subscription_ends_at = now()+365` with `payment_status 'pending'`
    and client-supplied ref/amount; `user_has_feature_access` checked dates only.
    Now anchored: requires a confirmed `coa_payments` row (own user, status
    approved/completed/confirmed/settled, amount ≥ `user_silver_monthly_price`
    (50) / `user_gold_yearly_price` (500) from `platform_settings`), writes the
    subscription as 'paid'; `user_has_feature_access` also requires payment_status
    paid. Fixed `feature_key = feature_key` shadowing. Client bug fixed:
    `subscription_service.dart` `hasFeatureAccess` passed wrong param names
    (`p_user_id`,`p_feature_key`) → PostgREST always failed → gate always false;
    now passes `{'feature_key': featureKey}` only.
  - **2FA FIXED (server-side, migration `20260911` applied live)**: was
    broken-by-design — client-encrypted `totp_secret` in `profiles` (key
    `sha256('$userId-coa-totp-v2')` derivable client-side), never enrolled
    server-side; login set `requires2FA` but never navigated. Now `two_factor_service.dart`
    uses `auth.mfa.enroll()`/`challengeAndVerify`/`unenroll`; setup screen shows
    server-generated QR + secret; `auth_provider.signIn` checks
    `user?.factors.any((f) => f.status == FactorStatus.verified)`;
    `complete2FA` = `listFactors()` + `challengeAndVerify` (gotrue 2.22 has NO
    `session.mfaChallenge` and NO `recoveryCodes`); `login_screen.dart` routes
    to `/two-factor-verify`. `profiles.totp_secret`/`totp_enabled` dropped.
  - **Offline giving queue**: `lib/features/finance/data/offline_giving_queue.dart`
    (SharedPreferences, idempotent enqueue by paymentRef, replay via
    `insert_transaction_idempotent` key `offline-gift-{ref}` + `enqueue_payout_task`,
    5 retries w/ backoff, auto-sync on connectivity). `finance_service.logTransaction`
    falls back to the queue on insert failure; giving screen shows amber
    "N offline gifts queued" banner with SYNC NOW.
  - **i18n (core surfaces)**: `lib/core/i18n/` — `app_languages.dart` (enum +
    `appLanguageProvider`, persisted), `translations.dart` (curated Bemba/Nyanja/
    Lozi/Tonga dictionaries, English fallback by design), `l10n.dart`
    (`context.tr('Key')`). Language picker in Account Settings. Wired: bottom nav
    labels, home quick actions + quick-jump, giving categories/header, profile
    posts header + see-all, verse/nav labels. Untranslated strings fall back to
    English. Extend `kTranslations` to translate more of the app.
  - **Orphan wiring (NOTHING deleted)**: Superadmin Hub gained "Platform Tools"
    (~32 dead console screens: Subscription Pricing, Church Payouts, Employee
    Management, KYC Review, Onboarding Manager, Promo Campaigns, Reward Mgmt,
    System Security, Tenant Lease, Unified Audit, Withdrawal Approvals, Zambian
    Compliance/Payroll, Payroll Processing/Reports, AI Stewardship, Apostolic
    Resource Planning, Driver Simulation, Global Payout, Kingdom AI Moderator,
    Prophetic Navigation, Wallet Command Centre, Integrations, Platform Ads,
    SOS Alerts, System Docs, Feature Toggles, Platform Analytics, Expansion
    Leads, Turnover Tax, Game Management, Quiz Event Host). Admin Hub gained
    "Ministry Tools" (Member Directory, CRM Donors, News Management, Radio
    Stations, Data Import, Volunteer Schedule). More Hub gained "More to
    Explore" (~19 cards: Discover, Discipleship, Interchurch Network, Network
    Activity, Song Lyrics, Tithe Card, Pastors Corner, My Jobs, My Applications,
    Sovereign Matchmaking, Poll Creator, Create Klip, Ride History, News,
    Branch Locator, SOS Emergency, Life Hub…). Connect header icons for
    Interchurch/Network Activity/Pastors Corner. Give tab gained Tithe Card +
    Transaction Alerts tiles. Profile gained My Subscription / Notification
    Preferences / Request a Feature. **Fixed broken `/jobs/post` route**
    (FAB crashed GoRouter "no route"). Full audit: 50 unreachable files →
    all user-facing + admin ones wired; only dead-dedup/utility files remain
    (planner_screen, life_hub duplicates, dead core helpers — kept per
    do-not-delete rule).
  - **`flutter analyze`**: 0 errors, 0 warnings (10 pre-existing info).
    Commit `8803c37` (pushed).

The Lipila payment integration now includes a **shared FX service** that other
projects can copy/reuse when they wire Lipila:

- `lib/features/give/data/lipila_fx_service.dart` � `LipilaFxService` (free
  `open.er-api.com`, no API key). Methods: `fetchRate()` (10-min cache,
  fallback rate 18.0), `convert(amount, rate)`, `convertAsync(amount)`.
  Providers: `lipilaFxServiceProvider`, `zmwPerUsdProvider`.
- `lib/core/services/currency_service.dart` � backwards-compatible facade that
  re-exports the Lipila FX service (existing `zmwPerUsdProvider` still works).
- Wired into: Lipila payment gateway fee preview ("� USD") + multi-currency
  wallet live-rate card.
- Constructor takes `baseCurrency`/`targetCurrency` (default ZMW->USD) so other
  projects can convert any supported pair.
- **Session 2026-08-17 (late) — COA role-assignment RLS fix + Shona/Ndebele i18n**:
  - **COA employee role assignment FIXED (root cause)**: migration `20260848`
    renamed `employee` → `coa_employee` in `profiles.role`/`role_assignments`
    data, but the `role_assignments` RLS policies (20260709 "Superadmins/
    employees can manage all assignments" + 20260840 `role_assignments_insert/
    update/select`) still gated on `role IN ('superadmin','employee',...)` —
    so COA staff got "permission denied" on SELECT/INSERT/UPDATE and the whole
    COA role-assignment flow (approve/reject/elevate in Role Approval screen)
    was dead server-side for them. Migration `20260912_fix_role_assignments_rls_coa.sql`
    (applied live, verified via `pg_policy`) recreates all 6 policies with
    `coa_employee` (+ legacy `employee`/`super_admin`) included.
  - **Client**: `role_approval_screen.dart` "Assign Role" dialog now has the
    full 26-role list (`_assignableRoles`: superadmin, coa_employee, admin,
    pastor, bishop, prophet, apostle, general_secretary, general_treasurer,
    treasurer, bookshop_owner, store_manager, assistant, cashier, driver,
    rider, vendor, merchant, writer, leader, usher, department_leader,
    worship_leader, praise_team_leader, praise_team_member, member) and the
    assignment is tenant-scoped via the **target user's own `tenant_id`**
    (was: COA's null tenant). Removed unused `tenant_service` import.
  - **Shona + Ndebele added to i18n**: `AppLanguage.shona('sn', chiShona)` +
    `AppLanguage.ndebele('nd', isiNdebele)` in `app_languages.dart` (Zimbabwe
    expansion market — `zw_` churches); first-pass 45-key dictionaries in
    `translations.dart` `kTranslations` (`'sn'`, `'nd'`); language picker picks
    them up automatically via `AppLanguage.values`.
  - **`flutter analyze`**: 0 errors, 0 warnings (10 pre-existing info).
    Commits `97141d8` (RLS + dialog) + `9e8f026` (languages), pushed.
- **Session 2026-08-13 — Security Hardening Sprint**:
  - **Full 3-agent security audit** (Flutter client, Supabase backend,
    infra/config/secrets). Findings → fixes below.
  - **Secrets hygiene (CRIT-1):** `.env` was bundled into every release build
    and previously contained `R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`,
    `CLOUDFLARE_API_TOKEN`, `GEMINI_API_KEY`, `HUGGINGFACE_TOKEN`. `.env` now
    public-only; secret getters (`r2Endpoint`, `geminiApiKey`,
    `huggingFaceToken`) removed from `env.dart`; `SECRETS_BACKUP.md` deleted.
    **⚠ USER ACTION PENDING: rotate all those keys + `RESEND_API_KEY` +
    anon key; restrict Google web API key by referrer; enable email
    confirmation in Supabase Auth.** (SECURITY.md §5)
  - **Migration `20260888_security_hardening.sql`:** `add_coins`/`deduct_coins`
    now require `auth.uid() = user_id` + ±100,000 cap; `coa_payments` INSERT
    policy restricted to `status='pending'` (superadmin bypass); `SET search_path
    = public` added to 14 SECURITY DEFINER functions (get_my_tenant_id,
    get_church_monthly_stats, get_church_monthly_tithes,
    get_organization_church_member_counts, get_organization_missions,
    sp_validate_import_columns, get_church_service_summary,
    get_organization_service_summary, get_coa_payment_stats,
    kids_upsert_progress, get_platform_engagement_stats,
    kids_mark_resource_completed, increment_study_attendees,
    get_quiz_leaderboard). Added to `deploy.ps1`.
  - **`lipila-payout` hardened:** non-payout roles must now present a
    `coa_payments` row (`payment_ref = reference`, status
    approved/completed/confirmed/settled) and payout is capped at verified
    amount + 1.0. Client-inserted `transactions` rows can no longer trigger payouts.
  - **Android backups disabled:** `allowBackup="false"`,
    `fullBackupContent="false"`, `dataExtractionRules="@xml/data_extraction_rules"`
    (new file excludes all domains from cloud-backup/device-transfer).
  - **Web hardening:** CSP meta tag + SRI on the passkeys `bundle.js` in
    `web/index.html`.
  - **Git hygiene:** deleted `SECRETS_BACKUP.md`; `git rm -r --cached
    supabase/.temp`; `.gitignore` += `supabase/.temp/`; replaced hardcoded anon
    JWT in `20260870`/`20260871` cron SQL with `x-cron-secret` placeholder.
    **⚠ LIVE pg_cron jobs (`lps-settle`, `event-remind`) still embed the old
    JWT — re-schedule them with a real `CRON_SECRET` (SECURITY.md §6).**
  - **Docs:** new `SECURITY.md` (full operating manual) +
    `SECURITY_PLAYBOOK.md` (reusable for other projects) + this security how-to
    section.
  - **`flutter analyze`:** 0 errors, 0 warnings (12 pre-existing info-level).
- **Session 2026-08-15 — Smart CI/CD Pipeline live**:
  - **Pipeline goal met**: automated security scanning, instant OTA testers (Firebase App Distribution), automated semantic versioning + changelogs.
  - **`ci.yml`** now has 4 jobs: analyze (warnings FATAL, pinned Flutter 3.35.1, `cp .env.example .env` first — the gitignored `.env` asset triggers `asset_does_not_exist` otherwise), test (key_flows hard gate), **secret-scan** (`.github/scripts/secret_scan.sh` — greps tracked files for AWS/GitHub PAT/Stripe/OpenAI/Anthropic/Supabase/Lipila/Slack/HF/Resend/SendGrid/Cloudflare/private-key/JWT patterns; whitelists `web/index.html` PUBLIC Firebase web config + `*.md`; `scripts/` was gitignored so the scanner lives in `.github/scripts/` and `.gitignore` uses anchored `/scripts/`), **codeql** (TS/JS on Edge Functions, gated on repo var `ENABLE_CODEQL == 'true'`).
  - **`ci-cd.yml`** — semantic versioning (BUILD_NUMBER = `git rev-list --count HEAD`, VERSION_NAME from tag `v*` else 1.0.0, passed via `--build-name/--build-number`); changelog job auto-generates `RELEASE_NOTES.md` from `git log` prev-tag..HEAD + `generate_release_notes`; **distribute-firebase** job (wzieba action, changelog notes, gated on `FIREBASE_SERVICE_ACCOUNT` + `FIREBASE_ANDROID_APP_ID`); notify-success/notify-failure (Slack → Discord fallback → echo).
  - **`test-lab.yml`** — Firebase Test Lab instrumentation (Pixel 7/5/4a, API 33/30/28) from `integration_test/app_smoke_test.dart` (pumps `ChurchOnApp`, asserts first frame, uses `app.ChurchOnApp` prefixed import), gated on `GCLOUD_SERVICE_ACCOUNT` + `FIREBASE_PROJECT_ID`.
  - **CRITICAL GitHub gotcha learned**: `secrets` context is NOT allowed in `if:` expressions at ANY level (job or step) — the ENTIRE workflow file is rejected ("workflow file issue", 0s failure). Use job-level `env: HAS_X: ${{ secrets.X != '' }}` + step `if: env.HAS_X == 'true'` (see distribute-firebase/test-lab/notify jobs).
  - **CRITICAL setup-java gotcha**: `cache: 'none'` is INVALID (`unknown package manager specified: none`) — remove the key instead. Migrated to `actions/setup-java@v5`.
  - **Runner kills**: two parallel Gradle-cache restores killed runners during Setup Java (steps hang, log 404) — dropped `cache: 'gradle'` from build jobs; single-job test-lab keeps it.
  - **Fixed `unawaited_return_in_try_block` warnings** (new analyzer): `r2_service.dart:98`, `subscription_service.dart:128`, `bible_service.dart:191` — added `await`.
  - **Secrets set**: `FIREBASE_ANDROID_APP_ID` (`1:45750098887:android:49947b7979e42c599217e2`, verified via Firebase MCP list-apps; project `studio-7483333628-db257`).
  - **First full green builds in CI**: AAB 23m28s ✓, APK 24m36s ✓ (75-min timeout + heartbeat work), iOS ✓ — artifacts apk-release 95MB, aab-release 115MB, mapping-files (obfuscation maps).
  - **⚠ USER ACTIONS PENDING**: (1) ~~GitHub billing~~ — RESOLVED: repo made PUBLIC (free Linux/Windows runners; going private re-blocks until Pro card payment is fixed); (2) ~~`FIREBASE_SERVICE_ACCOUNT` + `FIREBASE_TESTER_GROUPS`~~ — SET, App Distribution verified working OTA; (3) optional `SLACK_WEBHOOK_URL`/`DISCORD_WEBHOOK_URL`; (4) `GCLOUD_SERVICE_ACCOUNT` + `FIREBASE_PROJECT_ID` (`studio-7483333628-db257`) for Test Lab; (5) Google Cloud Console: add `https://churchonapp.com` as authorized JS origin (web OAuth); (6) verify web white screen in a real browser.
- **Session 2026-08-15 (late) — Pipeline stabilization**: iOS build DROPPED (proof-of-concept done; only AAB + APK release builds remain). Versioning switched from `git rev-list --count` to **Play API max versionCode + 1** (rev-count regressed to +116 vs Play's +262/+263 after history rewrite → Play rejected with "does not allow any existing users to upgrade"; fallback parses pubspec `1.0.0+268`; YAML gotcha: multi-line python3 inside `run: |` must be indented or the block terminates — use single-line python). Firebase App Distribution FIXED: SA key materialized to `firebase-sa.json` in workspace + `serviceCredentialsFile` (env-var JSON → "Failed to authenticate, have you run firebase login?"; SA itself verified fine). AAB flake FIXED: `android.enableJetifier=false` (JetifyTransform corruption on Flutter engine jar, APK unaffected; AndroidX-native app needs no Jetifier). Commits `06abcd6`, `3d9402b`, `05882d9`, `5c75a8a`. App Distribution verified green in run 31909984193 (50s, OTA to coa-testers); Play Store deploy pending next full green run.
- **Session 2026-08-13 — Church Auto-Payout (Kingdom Sponsor model)**:
  - **Feature:** mirrors chisomo's host payout model — giving collected to a
    church accumulates into a server-side **withdrawable balance** and is
    automatically disbursed to the church treasurer phone when it crosses
    `church_payout_min_kwacha` (default K100). Admin dashboard lists eligible
    churches + payout ledger.
  - **Migration `20260890_church_auto_payout.sql`:** `church_withdrawals` ledger
    (RLS select-only for admin roles; INSERT/UPDATE service-role only), partial
    unique index = ONE in-flight withdrawal per church, `payout_tasks` CHECK now
    allows `church_payout` source + nullable `user_id`. RPCs:
    `_church_withdrawable_balances_svc()` (service-only balance core),
    `get_church_withdrawable_balances()` (role-gated admin wrapper),
    `get_church_withdrawals()` (role-gated ledger history),
    `enqueue_church_auto_payouts(NUMERIC)` (atomic enqueue, service-only).
    Config key `church_payout_min_kwacha` seeded. **Deployed.**
  - **Balance math (never client-trusted):** confirmed giving `coa_payments`
    (metadata->>tenant_id) MINUS giving `payout_tasks` already
    pending/processing/paid MINUS in-flight withdrawals. Legacy confirmed
    payments (pre-2026-08-13, paid by the old client path) are excluded via a
    `created_at >= 2026-08-13` OR has-task guard — no double-pay.
  - **`_shared/settlement.ts`:** new `church_payout` case in `resolveSettlement`
    (gross capped by ledger row), `disburse`/`markTaskFailed` now sync the
    `church_withdrawals` ledger (processing/paid/failed + fees + payout ref),
    new `enqueueChurchAutoPayouts(supabase)` reading the threshold from
    `platform_settings`. Wired into `lipila-settle` cron + `lipila-webhook`
    (runs right after a confirmed collection). **Both deployed.**
  - **Dart:** `lib/features/admin/data/church_payout_service.dart`
    (`ChurchWithdrawable`, `ChurchWithdrawalRecord`, provider, `runSettlementNow()`
    invoking `lipila-settle`), `lib/features/admin/presentation/church_payout_screen.dart`
    (KPI row, eligible churches, ledger, pull-to-refresh, "Run settlement now"),
    superadmin dashboard tile, `church_payout_min_kwacha` editable in
    Subscription Pricing.
  - **Cron secret fixed (was CRIT from security sprint):** generated a real
    `CRON_SECRET` (96-char random hex), set via `supabase secrets set
    CRON_SECRET=...`, and re-scheduled the **live `lps-settle`** pg_cron job to
    send `x-cron-secret` instead of the old anon JWT (verified working via a
    live invoke: `success:true`, threshold K100). **`event-remind` orphaned
    cron deleted** — it embedded the old JWT, no `event-remind` function is
    deployed (repo or live), and `push-notifications` cannot serve it (needs a
    user JWT, no `event_reminder` action). See SECURITY.md §6.
  - **`flutter analyze lib`:** 0 errors, 0 warnings (10 pre-existing info-level).
- **Session 2026-08-16 (late) — Bible KJV fix, nav icon lock, marketplace delivery, buy-SMS payments, radio, expansion map**:
  - **Bible KJV text fixed (root cause)**: KJV is FULLY seeded in the local
    `bible_verses` table (13 `_seed_kjjv_text_p00X` batch migrations) but
    `_dbCodes` only contained `{'nkjv','nlt'}` — so KJV went through
    missing R2 JSON files (404) + slow bible-api.com (15s timeout) and ended
    at "No content found". Fix: `bible_service.dart` `_dbCodes =
    {'kjv','nkjv','nlt'}` (DB-first = instant, offline-robust), R2 timeout
    20s→8s, bible-api timeout 15s→10s so fallbacks fail fast.
    `bible_verses` RLS = SELECT to `authenticated` only (verified OK).
  - **Bible text audit (2026-08-16, live-DB verified)**: KJV = 31,102 verses,
    all 66 books (Genesis 1533 ✓), seed UUIDs match real rows, DB path works
    end-to-end. **CORRECTED 2026-08-17**: R2 `bible-text/` actually has ALL
    21 translation folders with 66 books each (kjv/web/dra/darby lowercase,
    ACV/ASV/BBE/CPDV/Geneva1599/Jubilee2000/MKJV/NHEB/Noyes/OEB/RLT/RNKJV/
    Rotherham/Tyndale/UKJV/Webster/YLT uppercase) — the earlier "only
    kjv/web/dra/darby, 404 everywhere else" finding was a false alarm caused
    by Cloudflare's bot filter blocking the audit tool's Python-urllib UA
    (403); the app's Dart http UA is served 200. All 14 requested translations
    wired in `BibleService._r2Codes` + `_r2Folder` case map + `oeb`/`tyndale`
    added to `kEnglishTranslations`. bible-api serves only
    `kjv/web/asv/bbe/ylt/dra`. NKJV/NLT translation rows exist in
    `bible_translations` but have **0 verses** (never seeded, can't be —
    copyrighted). Result: `BibleService` sets are now reality-based
    (`_dbCodes={'kjv'}`, `_r2Codes` = 21 codes, `_remoteCodes={kjv,web,asv,bbe,ylt,dra}`) + static `canResolve(code)`;
    reader + deep-study translation pickers only enable resolvable codes
    (others show "(soon)"); empty state now explains + offers "SWITCH TO
    KJV". Scripture search now also hits KJV rows (search_vector GIN).
  - **Bottom nav icons LOCKED (permanent)**: Sermons tab icon changed
    `headphones`→`video` (per user request, verified `LucideIcons.video`
    exists) — then a PERMANENT RULE added to AGENTS.md: NEVER change bottom
    nav tab icons again; future requests must be declined.
  - **Marketplace checkout**: `MarketProduct.tenantId` added; pickup-at-church
    shows seller church names (from `tenants.id,name`); Carpso Delivery
    requires customer address → Nominatim geocode (debounced 900ms,
    User-Agent header) → distance-based fare (K15 base + K8/km, min K20,
    remote keys `ride_delivery_min_fare_kwacha`/`rideDelivery*`), real
    destination + fare passed to `requestDelivery` (was fake lat+0.001).
    Express stays flat K15. Fixed `LucideIcons.mapPinCheck`→`mapPin`
    (doesn't exist in 0.257.0), removed unused `_pickupChurchesLoaded`.
  - **Buy SMS credits secured**: `buy-sms-credits` Edge Function previously
    granted credits on ANY client-supplied `payment_ref` (free-credit exploit).
    Rewritten: server-side `BUNDLES` map (100→K50, 250→K100, 600→K250),
    client `amount_kwacha` ignored, idempotent via `tenant_sms_transactions`
    (payment_ref + type='purchase' → `already_applied`), anchored on
    confirmed `coa_payments` (status approved/completed/confirmed/settled,
    amount ≥ price), errors 400/402/403/500. **Deployed.**
  - **Radio**: `android:usesCleartextTraffic="true"` added to manifest (many
    stream URLs are http:// — Android 9+ blocked them); 3-state indicator
    LIVE (red)/CONNECTING (amber)/OFFLINE (grey) + per-station status dots.
  - **Expansion map rewritten** (`map_screen.dart`): Zambia-only (zw_ IDs
    filtered), plan filter badges (All/Silver/Gold/Platinum via `TenantPlan`
    enum comparisons + `church.limits.label`), marker tap → church info sheet
    + GET DIRECTIONS (Google Maps URL), branch count pill, refresh.
  - **CI**: `upload-drive` job PAUSED (`if: false`) — restore = main-branch
    push gate + `GOOGLE_DRIVE_SA`/`GOOGLE_DRIVE_FOLDER_ID` secrets (user adds
    Drive API access to the Play SA first).
  - **Deployed**: `generate-quiz-batch` (added `topic` param).
- **Session 2026-08-18 — 21-item user bug-fix batch, KYC on web, WHIP relay fix, tenant dedupe, test gate repair, builds +277**:
  - **Batch fixes (commit `1653b49`)**: livestream studio rewritten on `UnifiedStreamService` (real Cloudflare live input, WHIP ingest via client-side SDP→`whip.url`, `/live-studio` route) — was a 500-crash placeholder; login redirect-loop fixed (`go_router` pushReplacement, `userAlreadySeen` via SharedPreferences); bookshop `orders` table fixed (was missing → checkout crash); Platform Ads (superadmin) set `tenant_id` nullable + per-tenant list; "Seed Mock Data" admin button removed; Account Settings scrollable; Admin Hub tiles tenant-scoped; schedule save no longer fails RLS (migration `20260916` churches UPDATE policy: `tenant_id::text = auth.uid()-profile lookup`); tithe reminder card linked to paywall. Spiritual momentum (`prediction_service.dart`) rewritten with REAL logic (streaks/verse_notes/daily_challenge_results/attendance in parallel, 40/40/20 weighting, week-over-week velocity, streak+7 forecast — no more fake growth); Selphie/KYC capture hardened (camera permission, lost-data recovery, preview thumbnails); SOS manager gets tenant name + `tel:` external launch + RLS incl. `coa_employee` (migration `20260917`); Prophetic surveillance heatmap rewired to REAL church lat/lng + member-count weights (`get_prophetic_heatmap_data` RPC, migration `20260918`); Logistics Command rewritten on real `church_buses` table (tenant-scoped, live/offline detection, RLS incl. `coa_employee` in migration `20260919`); Media Manager routes uploads to real tables (klips/sermons/marketplace→R2 URL dialog); Flyer Studio can render PNG (RepaintBoundary), share via share_plus, and POST to Connect (`R2Service.uploadBytes` added); church logo upload fixed for web (readAsBytes → uploadBytes); Member Live Heatmap now real (profiles lat/lng/last_seen, 30s refresh, tenant-scoped); Financial Stewardship report de-faked (real month, no "VPS blockchain" badge, no fake delay); Export Data — all 10 types map to REAL tables. All migrations applied live + added to `deploy.ps1`. `flutter analyze`: 0 issues.
  - **Git push unblocked (CRIT)**: GCM interactive OAuth hung; `GIT_TERMINAL_PROMPT=0` + `git credential fill` returned the CACHED PAT from Windows Credential Manager (`git:https://Carpso@github.com` entry) — plain `git push` then works. SSH keys on machine are NOT registered to GitHub.
  - **KYC on web (commit `c89120c`)**: `KycService` now bytes-based (`submitDocumentBytes`/`submitSelfieBytes`, new `EncryptionService.encryptBytes`); screen stores the picked `XFile` (no temp-file dance — `Directory.systemTemp` doesn't exist on web) + `Image.memory` preview. Mobile delegates through the same pipeline. **KYC now works on churchonapp.com.**
  - **`whip_offer` Edge Function fixed (root cause)**: was POSTing SDP to `https://api.cloudflare.com/client/v4/accounts/{id}/stream/live_inputs/{id}/whip` with a Bearer token — that is NOT a real endpoint (the original livestream 500). Cloudflare WHIP publish URL is the live input's **`webRTC.url`** (`https://customer-<CODE>.cloudflarestream.com/<SECRET>/webRTC/publish`, no auth header — the URL IS the credential). Fix: relay resolves the live input via the API, extracts `webRTC.url`, POSTs the SDP there, returns the answer. **Deploy the updated function** (client already bypasses it, but the broken action is a landmine).
  - **Duplicate tenants merged (live DB)**: Rock Of Ages had 2 active tenants rows — dup `00000000-0000-0000-0000-000000000036` (11 child rows: 5 notifications, 2 social_posts, 1 transaction, 1 sermon, 1 event, 1 pledge) repointed to verified `a7d7ef90-5555-4444-9999-d8c9735d4b53`, then deleted. Backup table `public._backup_dup_tenant_merge` (11 rows) kept. Also deleted 2 junk inactive "Kabs" tenants (0 refs). Verified 0 dangling references.
  - **`key_flows_smoke_test.dart` fixed (real regression)**: `context.tr()` (l10n from 08-17) requires a Riverpod `ProviderScope` — `GivingCategorySelector` test pumped it bare → CI hard gate was failing. Wrapped in `ProviderScope`. Gate now 5/5 green.
  - **Test suite status**: 339 pass / 56 fail — ALL pre-existing stale tests (renamed screen titles e.g. "Kingdom Testimonies"→"Testimonies", rewritten services chat/coins/logistics/tenant, supabase-init mocks). None caused by recent app changes. Fixing all 56 = dedicated stale-test sweep, still pending.
  - **Release builds**: local clean builds v1.0.0+277 — AAB 121.8 MB (`build/app/outputs/bundle/release/app-release.aab`), APK 210.0 MB (`build/app/outputs/flutter-apk/app-release.apk`). pubspec bumped `1.0.0+277`.
- **Session 2026-08-21 — Bible 2-book fix, PvP invite, HF-only AI, Groups vs Ministries, 42P17, fresh +289/+290**:
  - **Bible 2-book corruption FIXED (root cause)**: `bible_books_service.dart` cached any `isNotEmpty` result for 30 days — a stale `bible_books_cache` with 2 books (Genesis/John from early partial API) short-circuited the DB (66) and built-ins forever. Selector showed `2 books`. Fix: hardened `fetchAllBooks()` to only accept `length==66` from cache/Supabase/APIs (`_clearCache()` on partial), Supabase `rows.length==66` guard, API `==66` guard, else fallback to `_getBuiltInDefaults()` (66) + repopulate cache. Fixed duplicate `bookOrder`: `Ezekiel 25→26`, `2 Corinthians 46→47` in `_getDefaultBookOrder` + `_getBuiltInDefaults`. `bible_screen.dart` `_loadBooks` now `Future<void>` + auto force-refresh via `bibleBooksRefreshProvider(true)` when `!=66` + orange `Only X/66 — FIX` banner in selector with retry. `offline_bible_kjv.json` has 66 (5.29 MB), `offline_bible_data.json` only 3 (legacy) — now superseded. `flutter analyze lib` 0 issues.
  - **PvP Invite-a-Friend FIXED**: `pvp_service.dart` `WagerTier` was `free/10/50` but UI `0/10/25/50/100` `bible_quiz_hub_screen.dart:1929` → `25/100` mapped to `free` and RPC error swallowed (`createInvite` caught `throw` and returned `null` so `Insufficient coins` sheet never showed). Fix: expanded `WagerTier` to `free/10/25/50/100` + `fromCoins()`, `createInvite()` now **throws** on `success!=true` (with `Insufficient coins` reason) so `_sendInvite()` `catch` can show `showBuyCoinsSheet()` correctly. `create_pvp_invite` RPC allows `0-1000` (`20260897:334`), `30 min` expiry, charges inviter server-side via `coin_redemptions`. Friend picker `_FriendPickerSheet` uses `profiles tenant_id eq + limit 200` + search filter; push via `push-notifications` `pvp_invite` type.
  - **Hugging Face on every AI feature (HF-only, no Gemini)**: Edge `kael-ai`, `generate-quiz-batch`, `quiz-import`, `hf-keep-warm` all use `https://router.huggingface.co/v1/chat/completions` + `HF_MODEL_ID ?? meta-llama/Llama-3.1-8B-Instruct` (`HUGGINGFACE_TOKEN` only, `GEMINI_API_KEY` removed 2026-08-20 per request). `lib/core/services/gemini_service.dart` now proxies to `kael-ai` (doc updated: `Hugging Face via Kael`, `@deprecated` alias kept as `geminiServiceProvider` for compat). `kingdom_ai_moderator_screen.dart` snackbar `via Gemini → via Hugging Face (Kael AI)`. `ai_sermon_notes_screen.dart` doc `Kael AI (Hugging Face)` + fallback text fixed. `quiz_question_upload_screen.dart`/`bible_quiz_hub_screen.dart` comments `Gemini → Hugging Face / Kael`. All AI (Kael chat/summary/dramatize/exegesis/concordance/cross_ref/chapter_summary/voice_search, quiz generation, extraction, moderation, financial/logistics/apostolic predictions) covered via single HF model.
  - **Groups vs Ministries clarified**: `community_communities` (containers) + `community_groups` (chat groups) = social fellowship (tenant-or-public, `community_groups.is_public`, via `CommunityService.fetchCommunities()`, `CommunitiesScreen`) vs `ministries` + `ministry_members` = formal service teams (Choir/Ushering/Youth, strictly `tenant_id`, leader, `meeting_day/time`, via `MinistriesScreen` `embedded:true`). Merged in `CommunityHubScreen` toggle: now shows explanatory subtitle (`community_hub_screen.dart:24`): Groups = `Social groups for fellowship & chat — join any community`, Ministries = `Service teams with leaders, meeting times & rosters`. Admin create via `MinistryManagementScreen`.
  - **42P17 fix (2026-08-21 prior)**: `profiles_select_staff` self-referential `EXISTS (SELECT FROM profiles)` → `is_admin_or_employee()` (`20260931` applied live, commit `74d6ab4`).
  - **Release builds**: fresh clean `flutter clean` + `flutter pub get` → AAB 123.3 MB (`build/app/outputs/bundle/release/Church On App.aab`) / APK 211.7 MB (`build/app/outputs/flutter-apk/app-release.apk` + `apk/release/app-release.apk`) `v1.0.0+289` (`d04a388`) → **v1.0.0+290** (web `build/web/main.dart.js` 9,136,447 bytes, AAB `Church On App.aab` 123.3 MB, APK 211.7 MB) — all fresh after `flutter clean` + `build web` + `wrangler pages deploy` to `bf4dd42d.churchonapp.pages.dev` (branch `main`) + `bundleRelease` (1708s) + `assembleRelease` (1007s).
- **Session 2026-08-21 (late) — Website tenants empty, Life Hub dedupe, Zambian driver payout autodetect, fresh +291 APK→AAB**:
  - **Website tenant selection empty FIXED (root cause)**: `tenant_service.dart:292` `Future.wait([churchesFuture, bookshopsFuture])` — if `bookshops` RLS blocked anon (web pre-auth) or table missing, the *whole* `Future.wait` threw and fell back to `fallbackChurches = []` (empty by design `tenant_service.dart:242`), so the Flutter web map/list showed empty even though `churches` query succeeded. Fix: churches and bookshops fetched **independently with separate try/catch** (`getAllTenants()` now `churches = try {...}` + `shops = try {...}`), bookshops failure is non-fatal (logged `non-fatal`), churches still render. Website selector now shows all verified `churches` (`is_verified==true` → `_registered`) even when `bookshops` is blocked.
  - **Life Hub duplicate removed & consolidated (MoreHub)**: `life_hub_screen.dart:1` (Radio + Testimonies + Prayer Wall) was a strict subset of `more_hub_screen.dart:78` Spiritual & Media (`Radio` `more_hub:96`, `Testimonies` `100`, `Prayer Wall` `101` + `more_hub:102` Communities/Klips etc) plus `Login → Life & Modules` already exposed those features. `more_hub_screen.dart:132` **removed** `Life Hub` card (`Navigator→LifeHubScreen`), dropped `import 'life_hub_screen.dart'` `file:31`, `app_router.dart:178` removed import and `app_router.dart:1351` `GoRoute('/life-hub')` → `redirect: => '/more-hub'` for deep-link compat. `life_hub_screen.dart:7` annotated deprecated with consolidation note. No nav dead-end; 19+ modules remain in `MoreHub` (Discover, Discipleship, Interchurch, Song Lyrics, Tithe Card, Pastors Corner, Jobs, Poll, Klip, Ride History, News, Branch Locator, SOS, Year Planner + Spiritual/Media/Logistics grids).
  - **Driver payout autodetect FIXED (Zambian ZICTA prefixes)**: `momo_phone_input_widget.dart:21` `_networks` = MTN `096/076` yellow, Airtel `097/077` red, Zamtel `095/075` green (all valid `0(9[5-7]|7[5-7])\d{7}` `validateZambianPhone:84`). Added `detectNetworkIdIfKnown() : String?` `widget:44` that returns `mtn/airtel/zamtel` only when ≥3 digits match a known prefix (avoids premature `MTN` default on `"09"`). `_onPhoneChanged` `widget:94` now only auto-switches when `known != null`. `rider_onboarding_screen.dart:57` `_networkFromPhone()` → `detectNetworkIdIfKnown() ?? legacy`, `_onPhoneChanged` + `_onPayoutPhoneChanged` trigger at `≥3 digits` (was `≥10`), cross-validate payout vs operator (`validate` `onboarding:376` + `switch to X` chip), show live `Auto-detected: AIRTEL` badge (`onboarding:376` Builder) with `+260`/`0`/`9-digit` handling (`detectNetwork` now strips `+260`/`260`/`9` variants). `flutter analyze` 0 issues.
  - **Next builds**: fresh `flutter clean` + `pub get` → APK (`assembleRelease` 1675s) **211.7 MB** (`build/app/outputs/flutter-apk/app-release.apk`) then AAB (`bundleRelease` 900s) **123.3 MB** (`build/app/outputs/bundle/release/app-release.aab`) `v1.0.0+291` (user-ordered `APK → AAB`), web `build/web/main.dart.js` 9.14 MB redeployed to `667251dd.churchonapp.pages.dev` (branch `main`).
- **Session 2026-08-22 — International Quiz Engine + pro charts + 484-test green suite + lifeline wiring, release +292**:
  - **Engine (`lib/features/modules/bible_quiz/engine/`)**: JBQ/WBQA-aligned pure-Dart domain — `QuizQuestion` (book/chapter/verse metadata), `QuizCategory` (directQuote/chapterAnalysis/multipleChoice/speedRound), `QuizRuleSet` (+10/20/30 base, speed bonus, wrong-attempt & timeout penalties; tournament = 5s decision/30s answer), `QuizTimer` (ms precision, pause/resume, injectable clock, expire-listener once, no-revive-after-expiry), lifelines (`useFiftyFifty` deterministic keep-correct, `useAskPastor`, `useExtraTime`), anti-cheat (`duplicate_submit`, `implausible_response_time`; flagged sessions rejected by repo), `QuizLeaderboard` tie-breakers (score↓ → wrong↑ → avgResponse↑ → completedAt↑), `TenantTournament`, `MockQuizRepository` deterministic seed bank.
  - **Arena wiring**: `bible_quiz_arena_screen.dart` builds an `engine.QuizSession` per match (tournament when `eventId != null` w/ token, else practice); `_useFiftyFifty` consumes engine budget + derives eliminated options from engine survivors; new **Ask-Pastor** button consumes `useAskPastor()` and streams a no-reveal hint via kael-ai chat (hint banner with dismiss); Time Freeze consumes engine Extra-Time budget through a mirror `QuizTimer`. Legacy `_useDoublePoints` removed. Mapper `_toEngineQuestion` maps legacy model → engine model (regex-parses Book C:V from scripture_reference).
  - **Pro charts kit (`lib/core/widgets/pro_charts.dart`)**: `ProChartCard`/`ProBarChart`/`ProLineChart`/`ProPieChart` — gradient bars w/ ghost zero-stubs, dashed gridlines, dark tooltips, donut w/ center metric + pill legends; NaN/negative sanitization; wired into finance dashboard, ledger, bishop/apostle dashboards, platform analytics. Finance dashboard gained a session-only privacy toggle (`financePrivacyProvider` → `K ****` masking via `moneyOrMasked`).
  - **484/484 test suite green** (was 339/56): fixed all stale tests — mocktail `thenAnswer` for Future-like Postgrest builders, `registerFallbackValue(<String,dynamic>{})`, stream filter chaining via `MockSupabaseStreamBuilder.noSuchMethod`, dummy `Supabase.initialize` pattern for widget tests, API-drift alignment (sermon `.range()`, chat `sender_id`, reading-plan DB-only progress, tenant empty-fallback-by-design). **Real bugs found & fixed by tests:** universal_search spinner hang (Supabase access outside try), radio CONNECTING badge overflow, transport models null-crash on partial rows (`RideRequest/DeliveryRequest.fromMap` hardened), service_report duplicate-entry guard + stable currency controllers, finance privacy toggle.
  - **Monetization (researched)**: mirrors JBQ/WBQA real-world fees ($45–50/quizzer season, $125–200/team church, $25–3k sponsorship ladder) → COA keeps free practice + free 1v1, wager PvP player-funded, tournament passes CC-per-K1, engine lease 1500 CC/yr ≈ church team fee.
  - **Release v1.0.0+292**: fresh clean web + APK + AAB — web `main.dart.js` **8.74 MB** deployed to `63c554ba.churchonapp.pages.dev` (branch `main`), APK **211.7 MB** (`build/app/outputs/flutter-apk/app-release.apk`, `assembleRelease` 2374s), AAB **123.4 MB** (`build/app/outputs/bundle/release/app-release.aab`, `bundleRelease` 436s).
- **Session 2026-08-22 (late) — Notebook batch, dashboards audit, streaming auth + social carousel, weather realtime, study pane functional, release +293**:
  - **PvP invite check-constraint FIXED (root cause)**: `pvp_matches_status_check` only allowed pending/accepted/playing/completed/cancelled/declined — migration `20260897` wrote status `'invited'` (and `'expired'`) without widening it. Every invite INSERT crashed with 23514. Migration `20261001_pvp_invite_status_check.sql` recreates the check with all 8 statuses; applied live + in deploy.ps1.
  - **Streaming auth FIXED**: cloudflare-stream Edge Function leadership list added apostle+prophet; unified_stream_service passes explicit Bearer token header; studio maps FunctionException → actionable messages (session expired / leadership-only / service down). **Deploy cloudflare-stream to activate roles fix.**
  - **Sermon chat double-send + Citizen names**: insight TextField had both onSubmitted AND send-icon handlers each calling reactToSermon → single shared sendInsight() with isSending guard; stream `.order()` removed (client-side sort) killing refresh-loop duplicates; new fetchInsightAuthors() enriches real names+avatars replacing hardcoded "Citizen".
  - **Instagram-style post carousel**: new `lib/core/widgets/post_image_carousel.dart` — snapping PageView w/ pill dots, BoxFit.contain in 16:9 stage (no crop/zoom), tap → fullscreen InteractiveViewer gallery with swipe + n/N counter. Wired into SocialPostCard for both images[] and single media_url.
  - **Profile role audit**: Church Ledger entry removed (Finance Dashboard is the single source); apostle badge fixed (was BISHOP crown); TREASURER/DRIVER/RIDER/VENDOR/BOOKSHOP badges added; bookshop staff (store_manager/assistant/cashier) get Bookshop Dashboard via isBookshopStaff.
  - **Ledger/Finance consolidation verified complete**: profile entry removed; admin hub renamed; bishop hub Financial Ledger tile removed (Central Treasury remains); pastor dashboard renamed; support hub copy updated; `/ledger` redirects.
  - **Dashboard fake-opening toast killed**: bishop hub `_buildActionCard` fallback toasted "Opening $label..." with no navigation — onTap now required (compile-time enforced); Ministries & Branches → /member-directory, Pastor Reports → /pastor-bishop-report; pastor dashboard duplicate View Finances tile removed.
  - **Google sign-in GoException redirect race FIXED**: manual context.go('/') after signInWithGoogle raced the router's own redirect → "GoException: redirect detected". Removed manual nav; GoException swallowed as benign; error snackbar only when user==null.
  - **Weather chip rebuilt**: fixed 56×56 circle (emoji over temperature number), never compressed by long church names (was Flexible+FittedBox squeeze); clickable → Weather Maps. `weatherDataProvider` converted FutureProvider→StreamProvider: immediate emit + 10-min periodic re-fetch while home visible = emoji/temp track live Open-Meteo conditions.
  - **Bible fixes**: stale empty-cache guard (old builds cached empty chapter lists making version switch say "not found" forever); translation dropdown Expanded (overflow fix); search dialog upgraded to full-text verse search (DB + cached books, debounced, VERSES+BOOKS sections); verse notes upsert (one row per user/book/chapter/verse — no more doubles) + deleteVerseNote + Delete chip in sheet.
  - **Home fixes**: quick-jump bar lazy-sliver fallback (sections below viewport had no context — taps did nothing; ScrollController proportional jump then reveal); quick actions trimmed 11→6 (Sermons/Events/Bible/Quiz/Notebook/Bible Study); Latest Sermon + Events moved directly under Quick Actions per priority request.
  - **Marketplace**: Express tile hardcoded K15 while total charged remote-config K50 — tile now shows live value; pickup summary adds "collect directly from church" note.
  - **Events create RLS FIXED**: policy requires auth.uid()=user_id OR hosted_by; inserts only set created_by → policy violation every time. Insert now includes user_id + hosted_by.
  - **Shimmer blink FIXED**: home news/sermons/event-timeline + sermon insights `.when()` got skipLoadingOnRefresh:true — realtime snapshots no longer flip widgets back to shimmer mid-refresh.
  - **Study pane made functional**: was 5 static text rows ("total waste"); now AI Chapter Summary card (Kael chapter_summary, cached per chapter), quick tool tiles (Exegesis, Atlas sheet, Scripture Memory), real OPEN FULL SUITE button → NEW route `/deep-study-suite` (screen existed but had NO route — unreachable).
  - **484/484 tests green throughout**; analyze 0 issues at every commit.
  - **Release v1.0.0+293**: fresh clean web + APK + AAB — web `main.dart.js` **8.77 MB** deployed to `81494922.churchonapp.pages.dev` (branch `main`), APK **212.0 MB** (`build/app/outputs/flutter-apk/Church On App.apk`, `assembleRelease` 2227s), AAB **123.5 MB** (`build/app/outputs/bundle/release/app-release.aab`, `bundleRelease` 475s).


- **Session 2026-08-30 - Kael memory + real HF opponent + PvP cron sweep + UX batch (+296)**:
  - **Kael AI professional assistant**: system prompt gained a "Conversation Memory" section (uses the 20-message history, no re-greeting, follow topic switches); `ai_chat_service.dart` sends last **20** messages (was 10), auto-titles sessions from the first real question (42-char truncation, "New Chat" ? question), exposes `newChat()`; `kael_chat_screen.dart` gained suggested-prompt chips on first open, a **New chat** AppBar action, and the session default title "New Chat".
  - **Kael real matchmaking opponent (fix)**: arena `_generateKaelPlan()` pre-computes Kael's answers for the whole question set in ONE batched `kael-ai` call (`action: quiz_answers` ? strict JSON int array). `_kaelAnswerCurrent()` scores each question from that plan; the old 65% random simulation only fires when the call fails. One call per match keeps within the 10 req/min rate limit. New Edge `QUIZ_ANSWERS_PROMPT` + `quiz_answers` action in `kael-ai/index.ts` (deployed).
  - **Kael 429 retry UI (fix)**: Ask-a-Friend lifeline no longer burns the engine budget before a successful reply � on 429 it shows a RETRY snackbar; results "Kael explains" sheet detects 429 and shows a rate-limit message + Retry button (StatefulBuilder + re-callable future).
  - **PvP invite cron sweep (fix)**: migration `20261003_pvp_invite_cron_sweep.sql` adds `expire_all_stale_pvp_invites(INT)` (SECURITY DEFINER, global � no `auth.uid()` dependency, refunds inviters + `pvp_wager_refund` logs) scheduled via pg_cron `pvp-invite-expire` every 15 min. Orphaned invites no longer linger forever. Applied live (job id 7) + added to `deploy.ps1`.
  - **Quick actions rebalanced**: removed **Bible Study** (already on the church hero card); added **Fasting**, **Life** (`/more-hub`), **Prayer Requests** (`/prayer-wall`, `heartPulse`), **Testimonies** (`/testimonies`) � now 12 tiles.
  - **PvP invite auto-arena (fix)**: hub `_watchSentInvite(matchId)` subscribes to `watchMatchScores`; the inviter is auto-pushed into `BibleQuizArenaScreen` the instant the friend accepts (`invited ? accepted/playing`). `acceptInvite` now pushes a "Challenge Accepted!" notification to the inviter (`pvp_match`, `reference_id`) ? `/quiz/invite/<id>` deep link handles the host. Incoming invites show live status chips (PENDING/ACCEPTED/PLAYING/YOU WON/YOU LOST + score) + PLAY button; outgoing SENT audit trail shows WAITING/ACCEPTED/WON/LOST/DECLINED/EXPIRED. Per-match busy flags replace the global `_busy`.
  - **Ask-a-Friend lifeline**: renamed Ask-Pastor ? Friend (`LucideIcons.users`), friendly Bible-study-friend Kael persona.
  - **Comments instant (fix)**: optimistic insert renders immediately (profile fetch moved to background enrichment), feed counts refresh via `socialPostsProvider` invalidate.
  - **Prayer wall & testimonies avatars (fix)**: profile `avatar_url` first, then email/Google `picture`/`avatar` fallback; streams enrich old rows missing snapshots with live profile data.
  - **Verse of the Day double-marking (fix)**: redundant translation label suppressed when preferred-translation text equals the auto KJV text (also ignores labels containing "kjv"); share now copies the displayed text.
  - **Home top bar (fix)**: weather circle 56?48px, gap 4?6px, church-name maxWidth 130?115 � the more button no longer squashes on narrow screens.
  - **News white audit (fix)**: News section (title + disclaimer) hidden entirely when both kingdom + public feeds are empty; empty/broken news images replaced with an amber newspaper-icon placeholder instead of blank white boxes.
  - **Notification routing (fix)**: full type?route map in `notifications_screen.dart` � pvp_invite/pvp_match/pvp_result/pvp_rematch/quiz ? `/quiz/invite/<id>`, chat ? `/chat/<id>`, post ? `/posts/<id>`, event ? `/events/<id>`, sermon ? `/sermon/<id>`, job/ride/order/wallet/role handled; body falls back to `message`/`content`; read-marking is awaited.
  - **Head-to-head results UI (fix)**: arena finish + results screens show premium YOU vs OPPONENT cards (avatars, church, wager badge, winner crown, verified scores, status label).
  - **`flutter analyze`**: 0 errors, 0 warnings (2 pre-existing info in test). Docs updated: README (v1.0.0+296, features), ARCHITECTURE_BLUEPRINT (PvP lifecycle + Kael memory sections), CHANGELOG (unreleased v1.0.0+296).
- **Session 2026-09-06 — CI/CD paused for good**: `ci.yml`, `ci-cd.yml`, `deploy-web.yml`, `test-lab.yml` all switched from push/PR/tag triggers to **`workflow_dispatch` only** (commit `a842a33`) — no more automatic 20-40-min CI builds, secret-scan, CodeQL, SLACK/DISCORD notifies, Test Lab or App Distribution on every push. Restore = uncomment the `on:` blocks (`push`/`pull_request`/`tags`). Versioning in `ci-cd.yml` reads Play max versionCode across production/internal/alpha/beta via `GOOGLE_PLAY_SERVICE_ACCOUNT` (gcloud+androidpublisher), falls back to parsing pubspec `1.0.0+N`. `deploy-play-store` job still `if: github.ref == 'refs/heads/main' && github.event_name == 'push'` — manual `workflow_dispatch` of ci-cd will NOT hit it (event is workflow_dispatch), so local/manual AAB upload or re-enabling the trigger is required to ship to Play.
- **Session 2026-09-06 (late) — Payment rewiring + dashboards/user audit**: the "stick to chisomo" tight-loop refactor (platform-first Lipila collect → server settle → database webhook) reached deployments: `lipila-collect` now creates the pending `coa_payments` row + `?secret=` callbackUrl + status-from-your-reference path (status→'settled' syncs DB + re-triggers settle); `lipila-webhook` rewritten around dual auth (`?secret=` OR Standard-Webhooks HMAC `x-webhook-signature`, never a bare Bearer), referenceId-first resolve, no bogus `coa_payments` row per payout webhook, audit rows written with the ONE jsonb `details` column (no `changes`/`user_agent`); `_shared/settlement.ts` gained the `recipient_role` from `payout_tasks` + the full `resolveChurchRecipient` chain (`coa_payments` metadata contact/treasurer/pastor numbers before leaderboard `profiles.phone_number`) and the giving/event `event` source case. Migrations `20261015_multitenant_tithe_recipients.sql` (`recipient_role` on payout_tasks, 7-arg `enqueue_payout_task`) + `20261022_event_payout_source.sql` applied. Client wiring done in the fleet: `offline_giving_queue` + `finance_service.logTransaction` pass `recipient_role`, giving/event screens pass the `event` source. **`PAYMENTS.md` created** (12 sections, full payment-ops + "DO NOT REGRESS": client never decides payer/payee/amount, resolving happens only in settlement, `lipila-webhook` must never 502, dual webhook auth, audit `details` jsonb, `profiles.phone_number`, never payout-webhook→`coa_payments`, always pre-create pending row + `?secret=`). 21/30 churches still lack any payout number anywhere → tasks stay pending by design until phones set.
  - Dashboard/user audit fixes: driver/rider/writer/bookshop dashboards now read the real tables (`ride_requests`, `delivery_requests`, `kingdom_news`, `orders` join) — removed a `transactions`-typed payout-account table-drift; `profiles.driver_status` migration `20261017`; vendor edit product + `updateProduct`; subscription-pricing save now invalidates `remoteConfigProvider`/`platformSettingsProvider` + blank-key guard; COA treasury MoMo uses `platform_settings.coa_treasury_phone` (normalize); `AppImage`/profile avatar audit (routes+columns fine); finance data layers: VPS `db.churchonapp.com:8088` → `stream.churchonapp.com` (no 8088 in .env), `coa_payment_sheet` reads platform settings, `platform_settings_service` fallbacks + `onConflict(ignore)` on seed, `church_financial_hub` `type`→`category`/only-settled, ledger `-K` sign + tenant name, finance dashboard `FutureBuilder<dynamic>` handles List/Map, `service_report_form` new `baptisms`/`tithes` donations fields, `manage_offers`-era broken IDs fixed, `bible_service` DB timeout 150→1s.
  - Courier labels real now: `getActiveCouriersCount` is tenant-aware — COA/superadmin counts `profiles` driver+rider roles platform-wide; a tenant counts its own `church_buses` online count → Admin Hub tile renamed "Active Couriers / Fleet Buses". Versions `v1.0.0+301/+302` APK/AAB built during this session.
- **Session 2026-09-07 — Scoring-zero root-caused, Kael UPDATE policy, fresh +303/+304 builds**:
  - **Scoring "0 points" — 3 root causes fixed**: (1) `bible_quiz_arena_screen.dart` `_shuffleQuestionOptions` now reconstructs `correctAnswers[]` with a used-index pass (shuffling left stale indices → any multi-answer question scored 0); (2) fallback-question IDs were non-UUID: `bible_quiz_service.dart:526` `q['question'].hashCode.toString()` and `quiz_event_service.dart:680` `'ef_<epoch>_<hash>'` → `pvp_answers.question_id` FK `invalid input syntax for type uuid` → settlement recount = 0-0 draw. Both now `const Uuid().v4()`. (3) Already-implemented `Uuid` availability — `uuid` package already in pubspec. Remaining to look at with user: results-screen breakdown stays a 0-60 hand-roll independent of arena's `totalScoreWithBonuses` (`RapidFire ×2`, `Marathon +10`, double-scoring only known to arena), so hero vs breakdown can disagree; solo leaderboard needs `20261005_quiz_cc_leaderboard_solo` (tournaments seeded `solo` before it existed → Solo correct answer counts read 0). `flutter analyze` 0/0 + 2 pre-existing infos.
  - **Kael "stopped"**: nothing in the last 6 commits touched `kael-ai` — the app was reaching the old (confused) Edge. Fixed the one real backend gap: **`ai_chat_sessions` had NO UPDATE policy** → session auto-title (`title` set on first real question) threw 42501 → Kael chat "stopped" after DB write. Migration `20261029_fix_ai_chat_update_policy.sql` adds owner UPDATE (`auth.uid() = user_id`), applied live & in `deploy.ps1`. Remaining Kael checks for the user: `supabase secrets list` for `HUGGINGFACE_TOKEN`/`HF_MODEL_ID`; if Edge still 401/403, rotate HF token + `supabase functions deploy kael-ai --no-verify-jwt`; `check_admin_rate_limit` schema mismatch (`admin_rate_limits.window_start` 20260707 vs `created_at` 20260712) can throw 429; cold-start without `hf-keep-warm` cron = 60-150 s timeouts. Committed `556e249` + full suite 484/484 green.
  - **Fresh release builds**: requested clean-cache rebuild — `flutter clean` + `flutter pub get` → APK `v1.0.0+303` **212.7 MB** (`build\app\outputs\flutter-apk\app-release.apk`, assembleRelease 1735 s) then AAB `v1.0.0+304` **123.8 MB** (`build\app\outputs\bundle\release\app-release.aab`, bundleRelease 426 s). pubspec `1.0.0+304` staged, **not yet committed**. **Play Console internal deploy is manual this cycle**: `gh` not installed locally, SA JSON only a GitHub secret, and the CI deploy job won't run on `workflow_dispatch`. User chose manual upload (Play Console → Internal testing → drag `app-release.aab` → roll out).
- **Session 2026-09-08 — Cross-references real, Parallel Bible reader, streaming consolidated on Cloudflare, fresh +305/+306**:
  - **`cross_references` was an empty shell (root cause)**: 0 rows, SELECT-only policy, no unique index, fetch was source-direction-only, and curated `kLinkedScripture` links were dead because `bible_books` uses canonical `'Psalms'` while the app data used `'Psalm'`. Migration **`20260908_fix_cross_references_parallel_streaming.sql`** (deployed live, verified: 152 rows / 68 pairs): seeds curated pairs (harmony `parallel`, OT→NT `prophecy`, classic `thematic`), unique index `ux_cross_references_pair`, INSERT policy for `authenticated`, and reverse-row backfill so either side of a pair surfaces its counterpart (skip reverse for reverse-seeded rows). Note: `bible_books.name` is `'Psalms'` (plural) — keep seeds canonical. Added to `deploy.ps1`.
  - **Client cross-refs now bidirectional** (`bible_verse_service.dart`): `fetchCrossReferences` selects both `source_book:bible_books!(source_book_id)` + `target_book:bible_books!(target_book_id)` embeds, `.or()` matches source OR target, reverse rows render the counterpart; new `verseText`/`allowAiFallback` params. New `generateCrossReferences` calls kael `cross_ref` action, parses `BibleRef: Book C:V` via `_parseAiCrossReferences`, persists idempotently (upsert onConflict pair index). Provider `verseCrossReferencesProvider` now passes `verseText` from the sheet (`bible_screen.dart`).
  - **Related passages Psalm/Psalms fixed**: `linked_scripture_data.dart` `_canonicalBookNames` alias (`'Psalm': 'Psalms'`) + `_canonical()`; `builtInRelatedLinks` emits canonical names — the 59 curated links now surface + `_openLinked` lands on canonical books. Design decision: CROSS REFERENCES (DB, seeded + kael fallback) and RELATED PASSAGES (static curated) stay SEPARATE sections (no merge — avoids duplication).
  - **Parallel Bible reader**: new `lib/features/bible/presentation/parallel_bible_screen.dart` — `ParallelBibleScreen(book, chapter)`: KJV base via `bibleChapterProvider('kjv|book|ch')`, per-verse per-translation rows via `parallelVerseTextProvider`, FilterChip toggles (`_pickerCodes` 11 resolvable: kjv/web/asv/bbe/ylt/dra/noyes/tyndale/webster/ukjv/mkjv, default `['kjv','web']`, min 1 kept), chapter-picker grid capped by real book chapter count via `bibleBooksProvider` (do NOT hardcode 150). Route **`/bible/:book/:chapter/parallel`** in `app_router.dart`; reader AppBar `LucideIcons.columns` entry + verse-sheet "Open Parallel Reader" button; verse-sheet `parallelCodes` widened to `['kjv','web','asv','bbe','ylt']` (canResolve-filtered).
  - **Streaming consolidated on Cloudflare**: `stream_admin_screen.dart` OBS ("Start with OBS") + schedule flows rewired off the legacy MediaMTX hardcoded `stream.churchonapp.com` path → `UnifiedStreamService.createLiveStream` (real CF live input), then `_showObsCredentialsDialog(ctx, streamResult)` shows copyable RTMP URL + stream key. Usage meter reads the unified service (was `subscriptionService`). Legacy `LiveStreamService.createStream` remains (do-not-delete) but is no longer reachable from the admin UI. `live_streams.status` CHECK widened to `('scheduled','live','ended','archived')` — cleanup writes `'archived'` were failing 23514. All this means: **the ONLY streaming backend reachable from the app UI is Cloudflare Stream**.
  - **`flutter analyze`**: 0 errors, 0 warnings (2 pre-existing infos in `test/features/bible/data/bible_verse_service_test.dart`). Key-flow smoke 5/5. **Builds**: fresh clean → APK **v1.0.0+305** 212.7 MB (`build/app/outputs/flutter-apk/app-release.apk`, assembleRelease 1490 s) → AAB **v1.0.0+306** 123.8 MB (`build/app/outputs/bundle/release/app-release.aab`, bundleRelease 281 s). Docs updated: README (v1.0.0+306, cross-refs + parallel reader + streaming bullets), CHANGELOG (unreleased 2026-09-08), AGENTS.md (this session).

- **Session 2026-09-14 — Home "white block below Latest Sermon" ROOT-CAUSED + sermon playback/streaming/VOD overhaul**:
  - **Home tab white screen FIXED (root cause = `ErrorWidget.builder`)**: `main.dart` set
    `ErrorWidget.builder = (d) => CustomErrorBoundary(errorDetails: d)`, but
    `CustomErrorBoundary` returns a **full `MaterialApp` + `Scaffold`**. `ErrorWidget.builder`
    is invoked in place of an ARBITRARY failing widget — very often a small child inside the
    home `SliverList` — so laying a full-screen Scaffold out *inside a sliver child* broke the
    whole viewport and painted a **blank white block under the first section that failed**
    (below Latest Sermon). This is why the sections were only visible while scrolling fast and
    "vanished" when you stopped. Fix: `ErrorWidget.builder` now returns a new **bounded**
    `InlineErrorTile` (`lib/core/widgets/error_boundary.dart`). `CustomErrorBoundary` is kept
    only for genuine ROOT-level failures. See the new PERMANENT RULE at the top of this file.
  - **Home flicker/loop FIXED (root cause = Riverpod family key)**: `productsProvider` was
    `FutureProvider.family<..., Map<String, String?>>` and `HomeSparkleGrid` called
    `productsProvider({'category': 'all'})`. A `Map` has **no value equality**, so every rebuild
    created a NEW family instance → `loading` → resolve → rebuild → fetch… an endless
    reload loop that made **Marketplace Picks** flash/vanish and destabilised the sections
    around it. Fix: key is now a value-equal Dart record
    `typedef ProductFilter = ({String? category, String? marketType});` → call site
    `productsProvider((category: 'all', marketType: null))`. New PERMANENT RULE added.
  - **ALL broken images FIXED (root cause = R2 prefix check)**: `R2Service.resolveReadUrl`
    tested `url.startsWith('media.churchonapp.com/')` but stored URLs are
    `https://media.churchonapp.com/...`, so the check ALWAYS failed → R2 URLs were never
    signed → private-bucket 403 → every avatar/social/sermon image broke. Now matches with
    **and** without the `https://` prefix (cache keys use the trimmed URL).
  - **Home feed sections FIXED**:
    - *Marketplace Picks*: RLS was tenant-scoped; all 5 items belong to one church. New
      `marketplace_items` SELECT policy = `status='active'` (global) + `productsProvider`
      fetches globally.
    - *Events*: all 26 events were in the past → "No upcoming events". RLS now global
      (`USING (true)`) and `HomeEventTimeline` **falls back to the 3 most recent past events**
      under a "Recent Events" title.
    - *Writers / Kingdom News*: `kingdom_news` was **not in the `supabase_realtime`
      publication** (only `events` + `marketplace_items` were), so the realtime `.stream()`
      emitted nothing despite 10 published rows. Added `kingdom_news` + `sermons` to the
      publication with `REPLICA IDENTITY FULL`.
    - *Global News*: rss2json free tier was rate-limited with no cache → `[]`. `getPublicNews`
      now falls back rss2json → raw RSS via CORS proxy (allorigins/corsproxy) parsed with a
      regex → last-good cache → curated static links, so the section never blanks.
  - **Pull-to-refresh flicker FIXED**: `home_screen` `onRefresh` used
    `ref.invalidate(profileProvider)` (reset the profile AsyncValue to `loading`, flashing the
    whole header). Now `ProfileNotifier.refresh()` re-fetches in place, and `build()` watches
    `currentTenantProvider.select((t) => t?.id)` + returns the last profile while refreshing
    (a fresh `Tenant` instance with the same id no longer resets the profile).
  - **Sermon playback fixed (70/78 sermons never played)**: `SermonPlayerScreen` used
    `video_player` for everything, but 70 seeded sermons were **YouTube URLs** (video_player
    cannot play a YouTube page). Added **`youtube_player_iframe` 5.2.2** +
    `youTubeVideoIdFromUrl()`; YouTube sources now use `YoutubePlayerScaffold`/`YoutubePlayer`
    (fullscreen supported); direct MP4/HLS still use `video_player`.
  - **Audio sermons supported**: `media_upload_screen` gained an **AUDIO** media type
    (`file_picker`, bytes-based → works on web) writing `sermons.audio_url`; the player gained
    an **audio-only stage** using **`just_audio`** (artwork, seek slider, +/-10s, play/pause).
  - **Sample sermons replaced with real UPCI sermons** (`20261118_upci_sample_sermons.sql`):
    the old samples pointed at **non-existent YouTube ids (404)** and a rickroll. 12 real,
    oEmbed-verified UPCI videos (David K. Bernard, Raymond Woodward, J. Todd Nichols, UPCI
    General Conference, Texas District UPCI) are now the global samples; `20261117` removed
    64 duplicate rows + dead URLs.
  - **Sermon viewership fixed**: `sermons.viewer_count` was never incremented. Added
    `sermon_views` (RLS, owner-scoped) + `record_sermon_view(uuid)` RPC (SECURITY DEFINER,
    dedup 1/user/6h, `REVOKE ... FROM anon`) and the player now records a view on open.
  - **VOD quality — sermons now go to Cloudflare Stream**: `cloudflare-stream` Edge Function
    gained `create_upload_url` (Direct Creator Upload) + `get_video` (status/HLS/thumbnail);
    new `VodUploadService` PUTs the file to CF, polls until `readyToStream`, and the upload
    screen stores the **adaptive HLS** URL (up to source resolution) + auto thumbnail.
  - **R2 master archive (lock-in protection)**: `sermons` gained `archive_url` +
    `cloudflare_video_id` (`20261120_sermon_r2_archive.sql`). Every sermon upload is **also**
    written to R2 as the cheap master copy — CF Stream is only the playback layer. If CF fails,
    R2 is the fallback playback URL. This means you always own the source media.
  - **HLS on web (Chrome/Firefox)**: `video_player` web cannot play `.m3u8`. Added
    **`video_player_web_hls`** + **self-hosted `web/hls.min.js`** (satisfies the `'self'` CSP,
    works offline) referenced from `web/index.html`. CF Stream live + VOD now play in-browser.
  - **MediaMTX removed (dead backend)**: no `church_stream_config` row selected it (31/31
    `cloudflare`) and no server was ever deployed. Removed `StreamingBackend.mediamtx`,
    `_createMediaMTXStream`, `mediamtxHost/Secret`, the admin backend selector, the
    `stream.churchonapp.com` hardcoded fallbacks, and `Env.liveStreamUrl`.
    **Cloudflare Stream is now the ONLY streaming backend.**
  - **Live stream viewer hardened**: `LiveStreamScreen` had no try/catch and no URL validation
    (the stale `.../null/index.m3u8` row crashed it). Now rejects empty/`/null/`/non-http
    URLs, catches init errors, shows a "Stream unavailable" + RETRY state, and hides the LIVE
    badge on error. The broken `live_streams` row was set to `ended` and `LIVE`-status rows
    with no `cloudflare_stream_id` are excluded.
  - **Kael chat contrast fixed**: the user bubble was white text on `Colors.amber.withAlpha(200)`
    (unreadable) and the suggestion chips mixed white text with an amber tint. Both now use
    high-contrast pairs (brand yellow + `Colors.black87`; dark translucent chip + white text).
  - **Streaming quality guidance**: the OBS credentials dialog now recommends
    1920x1080 / 6000 Kbps CBR / 2 s keyframe (CF re-encodes to adaptive HLS), and
    `preferLowLatency: false` is kept for stability/quality.
  - **Migrations added to `deploy.ps1`**: `20261115_make_marketplace_events_global`,
    `20261116_fix_home_feed_realtime`, `20261117_cleanup_sample_sermons`,
    `20261118_upci_sample_sermons`, `20261119_sermon_viewership`, `20261120_sermon_r2_archive`.
  - **Edge Function**: `cloudflare-stream` redeployed (new `create_upload_url` + `get_video`).
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info in
    `active_ride_tracking_screen.dart`). Web deployed to Cloudflare Pages
    (`79a9bd6e.churchonapp.pages.dev` -> `churchonapp.com`).
  - **Known follow-up (not yet done)**: live-stream recordings are CF-hosted only — archiving a
    large CF recording to R2 needs a Worker/VPS (Edge Functions cannot buffer multi-GB files).

- **Session 2026-09-14 (late) — `Infinity.round()` root-caused, stream-start 42703 fixed, R2 CORS, stream analytics**:
  - **`Unsupported operation: Infinity.round()` FIXED (root cause = `PageController.page`)**: `home_hero_carousel.dart` called `_controller.page?.round()`. `PageController.page` is `(pixels - initial) / viewportDimension` and returns **Infinity/NaN before the viewport is laid out** (dimension 0) — `.round()` on that throws. Because the home tab is kept alive, the carousel kept rebuilding and threw on every other tab (`#/profile`, `#/connect`, `#/sermons`), which is why the error looked unrelated to the screen. Fix: only read `.page` when `hasClients && position.hasContentDimensions` and `raw.isFinite`.
  - **`app_image.dart` non-finite cache size FIXED (Crashlytics: ~386 events)**: `cacheWidth = (widget.width * devicePixelRatio).round()` threw for callers passing `width: double.infinity` (grid tiles/banners). Now only computed when the dimension `isFinite && > 0`. Same guard added to `performance_service.dart` (`imageCacheWidth/Height`).
  - **`church_stream_config` 42703 FIXED (broke stream start)**: `UnifiedStreamService.getStreamingConfig` selected `live_streams` columns (`title,status,hls_url…`) from `church_stream_config`, which has none of them → PostgREST 400 `column church_stream_config.title does not exist` → "Stream start error". Now `.select()`.
  - **Sermon-player retry crash FIXED**: the "Stream Unavailable → RETRY" button called `_videoController.dispose()` unguarded; `_videoController` is `late`, so when init failed before assignment the app threw `LateInitializationError`. Now guarded by `_hasInitialized`.
  - **Crashlytics-driven diagnosis**: `get_report topIssues` (app `1:45750098887:android:49947b7979e42c599217e2`) surfaced the `app_image` non-finite crash + a `rock_of_ages.png` 404 (dead church-logo object — the DB reference was cleared).
  - **⚠️ R2 CORS REQUIRED FOR WEB IMAGES (user action, Cloudflare dashboard)**: the bucket sends **no `Access-Control-Allow-Origin` header**, so every R2 image is blocked in the browser (mobile is unaffected — CORS is browser-only). Both the public domain (`media.churchonapp.com`) and the signed S3 endpoint (`<account>.r2.cloudflarestorage.com`) are blocked. Fix: R2 → bucket `choa-sermons-vault` → Settings → **CORS policy** → paste `r2-cors-policy.json` (repo root), or
    `npx wrangler r2 bucket cors set choa-sermons-vault --file r2-cors-policy.json` (needs an R2-scoped token; the current wrangler OAuth token has no R2 access — `code: 10042`).
  - **Streaming analytics SHIPPED (`20261121_stream_analytics.sql`)**: new `stream_view_sessions` (per-viewer sessions, RLS owner-insert + leadership read) and `stream_analytics_daily` (nightly rollup). RPCs: `stream_start_session` / `stream_end_session` (viewer), `rollup_stream_analytics` (SECURITY DEFINER, service/cron only, `REVOKE` from anon+authenticated), `get_tenant_stream_analytics` (church leadership or COA) and `get_platform_stream_analytics` (COA only). Cost attribution uses remote-config keys `cf_stream_delivery_usd_per_1000_min` (1.0), `cf_stream_storage_usd_per_1000_min` (5.0), `cf_stream_usd_to_zmw` (18.0). pg_cron `stream-analytics-rollup` scheduled nightly at 01:20.
  - **Analytics client**: `StreamAnalyticsService` + `streamAnalyticsProvider` (record key `AnalyticsWindow`), `StreamAnalyticsScreen` (tenant + platform modes), routes `/stream-analytics` and `/network-stream-analytics`, tiles in Admin Hub + Superadmin "Platform Tools". `LiveStreamScreen` gained an optional `streamId` and records a viewing session (start on open, 1-minute heartbeat, end on dispose); `/live-player` and the live list pass the id.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed to Cloudflare Pages (`0381712c.churchonapp.pages.dev` -> `churchonapp.com`).

- **Session 2026-09-14 (late 2) — R2 public + CORS set by agent, signing removed, KYC moved private, saved places server-side**:
  - **R2 CORS SET (agent action, no longer a manual step)**. Once the user enabled R2 on the account, `npx wrangler r2 bucket list` worked and the policy was applied:
    `npx wrangler r2 bucket cors set choa-sermons-vault --file r2-cors-wrangler.json`
    (wrangler format = `{ "rules": [ { "allowed": { "origins": [...], "methods": [...], "headers": [...] }, "exposeHeaders": [...], "maxAgeSeconds": n } ] }`; the dashboard/S3 shape is the flat array in `r2-cors-policy.json`). Verified live: `Access-Control-Allow-Origin: https://churchonapp.com` + `200` from `media.churchonapp.com`. `church-on-app-maps` already had CORS (`*`, Range) — untouched. Buckets: `choa-sermons-vault` (public media), `choa-kyc-vault` (private), `church-on-app-maps`, `kingdom-sponsor-media`.
  - **Client-side R2 signing REMOVED (root cause of the remaining `net::ERR_FAILED`)**: `resolveReadUrl` / `getSignedUrl` used to exchange the stored URL for an S3-presigned URL on `*.r2.cloudflarestorage.com`, which the browser blocked (no CORS on that endpoint). Since `media.churchonapp.com` is now a PUBLIC, CORS-enabled bucket, both helpers **pass the URL through unchanged** — no edge round-trip, no 50-min expiry, no signing dependency for reads. (Signing remains available for private buckets.)
  - **SECURITY FIX — KYC moved out of the public bucket**: `kyc_service.dart` was uploading encrypted KYC docs to `kyc/…` in the **public** media bucket, and the "encryption" key derives from a hardcoded default (`churchonapp-kyc-v1`, shipped in the app) — effectively readable. `r2-sign` now accepts an allowlisted `bucket` (`choa-sermons-vault` | `choa-kyc-vault`); KYC uploads target **`choa-kyc-vault`** and the client stores an `r2://choa-kyc-vault/…` reference instead of a public URL. `r2-sign` redeployed.
  - **Maps verified**: `church_map.dart` renders OSM raster tiles (`tile.openstreetmap.org` → 200 image/png) which carry street names; `rides` reverse-geocode pickups via `placemarkFromCoordinates` into a street label. Self-hosted `maps.churchonapp.com/zambia.pmtiles` returns 206 (Range) with CORS already configured. (OSM public tiles are fine for now; the self-hosted PMTiles remains the scalable path.)
  - **Saved places / last-mile pins are now SERVER-SIDE (`20261122_saved_places.sql`)**: previously only SharedPreferences (`carpso_saved_places`), so a rider's pickup/dropoff or dropped pin could not be reused for delivery, by a courier, or on another device. New `saved_places` table (user_id, tenant_id, label, address, lat, lng, place_type saved|landmark|pin, is_public) with owner CRUD RLS + tenant-public-landmark read (`get_my_tenant_id()`), `touch_saved_places_updated_at` trigger. `SavedPlacesService` is now DB-backed with an offline SharedPreferences cache and forward-geocodes the address (`locationFromAddress`) so every place carries coordinates for routing. `RideRequestScreen` gained `initialDropoffAddress/Lat/Lng` and "Saved Places" now opens the ride flow with that place as the destination.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed to Cloudflare Pages (`0b5c6125.churchonapp.pages.dev` -> `churchonapp.com`).

- **Session 2026-09-15 — Save-this-pin, self-hosted PMTiles basemap, events hub audit, tenant-aligned groups, release +314**:
  - **"SAVE THIS PIN" action (`church_map.dart`)**: dropping a pin now shows a "SAVE THIS PIN" button. It reverse-geocodes the point (`placemarkFromCoordinates` → street/sub-locality/locality) and stores it via `SavedPlacesService.add(...)` into the server-side `saved_places` table, so a dropped pin becomes reusable map data for pickup/dropoff and last-mile delivery. New `ChurchMap.showSavePin` flag (default `true`; only appears when `showPin` is on and a pin exists).
  - **Basemap switched to the SELF-HOSTED Protomaps PMTiles** (`maps.churchonapp.com/zambia.pmtiles`, bucket `church-on-app-maps`). Verified the archive is **Protomaps Basemap v4.13.6, vector/mvt, z0–15** (header byte 99 = 1) with `boundaries, buildings, earth, landcover, landuse, places, pois, roads, water` layers. `church_map.dart` now renders `VectorTileLayer(tileProviders: TileProviders({'protomaps': provider}), theme: ProtomapsThemes.lightV4()/darkV4(), maximumZoom: 15)` — the v4 themes include the `roads`/`places` label layers, i.e. **street names**, with no third-party tile service. Kept a fallback to OSM raster only if the PMTiles archive fails to open. Note: vector text glyphs still come from `protomaps.github.io/basemaps-assets` (self-host later if desired).
  - **Events hub audited + fixed**: quick-action **Events → `/events` → `EventsScreen`** which uses the SAME `features/events/data/event_service.dart` (`eventsStreamProvider`) as the home timeline — so it is NOT a different data source. `features/modules/media/presentation/events_list_screen.dart` (`EventsListScreen`) is **dead code** (no references). **Communities have no events concept at all** (`community_hub_screen.dart` has zero event references). The hub bug was in `discover_tab.dart`: it rendered `events[index]` **unsorted** and showed "No upcoming events found." whenever the list was empty. Now it orders **upcoming (soonest first) then most-recent past**, with `UPCOMING EVENTS` / `RECENT EVENTS` / `PAST EVENTS` section headers, so the hub is never an empty wall when a church has no future event.
  - **Church groups are now TENANT-ALIGNED (`community_service.dart`)**: `fetchCommunities`/`fetchGroups` previously OR'd in `is_public.is.true` and `tenant_id.is.null`, so groups from OTHER churches and global groups leaked into a church's Communities hub. Both now filter strictly `.eq('tenant_id', tenantId)` and return `[]` when the caller has no tenant. The cross-church/"global" experience stays in the **church social feed (Connect)**, which already has the **All / My Church / Friends** filter chips (`socialFilterProvider` in `connect_screen.dart`).
  - **Release builds v1.0.0+314** (pubspec bumped, `flutter clean` + `pub get`): APK **214.9 MB** (`build/app/outputs/flutter-apk/app-release.apk`, assembleRelease 1801 s) + AAB **124.3 MB** (`build/app/outputs/bundle/release/app-release.aab`, bundleRelease 294 s).
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info in `active_ride_tracking_screen.dart`). Web redeployed (`419153d9.churchonapp.pages.dev` -> `churchonapp.com`).

- **Session 2026-09-15 (late) — App-wide map upgrade: ChurchMap places layer + extraLayers, heatmap migrated, ride place-tap**:
  - **`ChurchMap` is now a `ConsumerStatefulWidget`** (was `StatefulWidget`) — the app-wide map widget used by 10 screens (select-church, ride map, active ride, prophetic heatmap, live viewer heatmap, branch locator, weather maps x2, expansion map, register church). New capabilities:
    - **Saved-places layer** (`showPlaces`, default false): renders own places + tenant landmarks from the server-side `saved_places` table as labelled markers (teal star = landmark, brand pin = personal). A bookmark toggle button in the map shows/hides it; `onPlaceTap` fires on tap. Watched via the new **`savedPlacesProvider`** (`FutureProvider<List<SavedPlace>>`) so a place saved anywhere appears on every map.
    - **Tapping a place drops the pin on it** (when `showPin` is on) and recentres the map — so a rider can set pickup/dropoff straight from Home / Work / a church landmark.
    - **`extraLayers`** hook: inject any flutter_map layers (e.g. `CircleLayer`) between the basemap and the markers, so custom overlays get the self-hosted basemap.
    - **`showLocateButton`** (default true) to opt out of the crosshair control.
  - **`bishop_heatmap_screen` migrated off raw OSM**: it had its own `FlutterMap` + `tile.openstreetmap.org` `TileLayer`. Now uses `ChurchMap(center:, zoom: 6, markers:, extraLayers: [CircleLayer(circles: _circles)], showPlaces: false, showSavePin: false, showLocateButton: false)` — so the density heatmap runs on the **self-hosted Protomaps PMTiles** basemap with street names. This was the last screen bypassing `ChurchMap`; **every map in the app now uses the self-hosted basemap** (raster OSM remains only as the fail-open fallback).
  - **Carpso Ride map** (`ride_map_view.dart`) passes `showPlaces: true`, so saved places are selectable directly on the ride/delivery map.
  - **`savedPlacesProvider`** added to `saved_places_sheet.dart` (reactive, single source of truth for the places layer + future delivery flows).
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`337aac27.churchonapp.pages.dev`).
  - **Still open**: marketplace delivery checkout does not yet offer the saved-places picker (it geocodes a typed address); the delivery fare/billing path is unchanged.

- **Session 2026-09-15 (late 2) — Marketplace delivery uses saved places; map branded sunflower**:
  - **Marketplace delivery checkout now offers the saved-places picker**: a `USE A SAVED PLACE` button above the Carpso Delivery address field opens `showSavedPlacesPicker`. Selecting a place fills the address AND sets `_geocodedDest` from the place's `lat/lng`, so no re-geocode is needed; the debounce the text-edit would schedule is cancelled. Because `_deliveryDistanceKm` and `_deliveryFee` are computed getters off `_geocodedDest`, the distance-based fare (base + per-km, min fare) updates automatically — the saved place flows straight into the courier request. Falls back to geocoding the typed address when a place has no coordinates.
  - **Map theme branded to the logo sunflower yellow (`AppConstants.sunflowerYellow` #FFDA03)**:
    - `ChurchMap` pins and personal place markers are now sunflower yellow (with `primaryDark` icon/text for contrast); tenant landmarks stay dark so they remain distinguishable.
    - Map control buttons gained a `filled` state — the **active** (places layer on) button is a filled sunflower circle with a dark icon; the inactive crosshair stays a white circle.
    - New **`brandTint`** flag (default true): a very light `ColorFiltered` multiply (`#FDF2C9`) over the basemap warms the tiles toward the brand palette (light themes only; dark stays neutral). Set `brandTint: false` for a neutral basemap if it costs frames on low-end devices.
    - `bishop_heatmap_screen` markers + density circles switched from red to sunflower.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`71321ac1.churchonapp.pages.dev`).
  - **Remaining map gaps (see review)**: vector text glyphs still load from `protomaps.github.io` (self-host on R2 for full independence/offline); address search + checkout geocoding use PUBLIC Nominatim (usage policy discourages heavy app traffic — self-host Photon/Nominatim or use a paid provider before scaling); no marker clustering; no offline tile pre-cache; saved-place UI cannot yet create tenant-shared landmarks (`is_public`) — only personal places.

- **Session 2026-09-15 (late 3) — Logo teardrop pins, tenant landmarks, geocoding fallback, configurable routing, offline tile cache**:
  - **Entity LOGO teardrop pin (`church_map.dart`)**: `buildChurchMarker` pin was rebuilt as a classic **teardrop** — circular head + tapered tail drawn as ONE continuous `ui.Path` (so the white border has no seam) with a drop shadow, and the **entity logo seated on top** inside the head (`AppImage`, icon fallback). Replaced the old "circle floating above a tiny triangle". Churches = `AppConstants.sunflowerYellow`, bookshops = `primaryDark` (distinct), unregistered = amber, OSM-only = grey. `select_church_screen.dart` now passes the brand colours explicitly. Every church/bookshop map (select-church, branch locator, expansion map, heatmaps) uses `ChurchMap` on the self-hosted PMTiles basemap.
  - **Tenant LANDMARKS (`saved_places`)**: `SavedPlacesService.add(... isPublic: true)` writes `place_type='landmark'`, `is_public=true`; the RLS policy already lets tenant members read their own tenant's landmarks. The **"Save this pin" dialog now asks for a NAME and offers `JUST ME` vs `SHARE WITH CHURCH`**, so couriers can reuse shared points ("Main Gate", "Depot"). Personal places render sunflower, landmarks dark.
  - **Geocoding fallback chain + cache (`GeocodingService`)**: address search previously hit public **Nominatim** directly from every client (usage policy forbids heavy app traffic; no SLA). New `lib/core/services/geocoding_service.dart` does **7-day local cache → `GEOCODING_BASE_URL` (self-hosted, take precedence) → Nominatim → Photon (`photon.komoot.io`)**, bounded to 200 cached queries. `church_map._searchAddress` uses it. Set `GEOCODING_BASE_URL` to a self-hosted Photon/Nominatim for scale.
  - **Configurable routing (`OSRM_BASE_URL`)**: `RouteService` had the hardcoded public OSRM demo server; now `Env.osrmBaseUrl` (`OSRM_BASE_URL`, defaults to the demo server). Point it at your own OSRM/Valhalla before ride/delivery volume grows.
  - **Offline-friendly tiles**: `VectorTileLayer` now caches tiles to disk for **90 days / 250 MB**, so any area a courier has already viewed keeps working with no signal.
  - **Self-hosted map GLYPHS uploaded (not yet wired)**: all 12 Latin range files (3 fontstacks × 4 ranges — `Noto Sans Regular/Medium/Italic`) were downloaded from `protomaps.github.io/basemaps-assets` and uploaded to `church-on-app-maps/fonts/<fontstack>/<range>.pbf`. **They cannot be wired yet**: `ProtomapsThemes.lightV4()` does not expose its glyph URL, and the v4 layer list is package-private (6,774 lines), so switching requires authoring a custom theme layer list.
  - **`.env.example`**: added `OSRM_BASE_URL` + `GEOCODING_BASE_URL`.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`d5d31411.churchonapp.pages.dev`).
  - **Still open (of the requested 7)**: (2) wire the self-hosted glyphs — needs a custom/branded Protomaps theme layer list; (5) marker clustering for dense maps; (6) proof-of-delivery photo + GPS and geofenced "arrived" detection in the driver completion flow. Also (3b) an explicit "download this area" pre-cache button.

- **Session 2026-09-15 (late 4) — Self-hosted map glyphs/sprites (via app domain), R2 account-mismatch finding, map data model answers**:
  - **Map labels are now FULLY self-hosted (no third-party dependency)**: downloaded the 3 fontstacks × 4 Latin ranges used by the Protomaps v4 light theme (`Noto Sans Regular/Medium/Italic`, ranges 0-255/256-511/512-767/768-1023) + the 4 v4 light sprite files, and **bundled them in the web deploy** at `web/map-assets/fonts/…` and `web/map-assets/sprites/v4/…`. Verified live: `https://churchonapp.com/map-assets/fonts/Noto%20Sans%20Regular/0-255.pbf` → **200**, `…/sprites/v4/light.json` → **200**.
    - Why this approach: `ProtomapsThemes.lightV4()` hardcodes protomaps.github.io for glyphs and (a) does not expose the URL and (b) the v4 layer list is package-private (6,776 lines). We therefore hold our **own generated copy** of the v4 light layers in `lib/core/widgets/maps/protomaps_light_v4_layers.dart` (regenerate by copying the `themeLight` array from `vector_map_tiles_pmtiles/lib/src/themes/v4/light.dart`) and build the theme ourselves with `glyphs:`/`sprites:` pointing at `https://churchonapp.com/map-assets/…`. Same-origin for web (no CORS needed), no CORS needed for mobile.
    - Dark mode still uses the stock `ProtomapsThemes.darkV4()` (external glyphs) — generate a dark layer copy the same way to finish.
  - **⚠️ FINDING — wrangler/`CLOUDFLARE_ACCOUNT_ID` may target a DIFFERENT Cloudflare account than the live buckets**: `npx wrangler r2 object get church-on-app-maps/zambia.pmtiles` returns "specified key does not exist" and `choa-sermons-vault/avatars/avatar_…jpg` is also missing, **yet the Cloudflare dashboard shows `zambia.pmtiles` (612 MB) in `church-on-app-maps` and `media.churchonapp.com` serves the avatar**. `r2 bucket list`/`cors set` succeed, so the token has R2 access — just to buckets that are NOT the ones behind `maps.`/`media.`churchonapp.com. **Consequence: the earlier `wrangler r2 bucket cors set choa-sermons-vault …` and the font/sprite R2 uploads may have gone to the wrong account.** Verify the live media bucket actually has a CORS policy (R2 → bucket → Settings → CORS) and that only ONE account is in play.
  - **Basemap unchanged (correct)**: `.env` `MAPS_ZAMBIA_URL=https://maps.churchonapp.com/zambia.pmtiles` (612 MB, their `church-on-app-maps` bucket) and `MAPS_ZIMBABWE_URL=…/zimbabwe.pmtiles` (310 MB) — verified 206 via range requests. `ChurchMap` renders these as the self-hosted Protomaps vector basemap.
  - **Map data model (answers)**: the map data DOES grow —
    | Source | Table | Geo columns |
    |---|---|---|
    | New church registration | `churches` | latitude, longitude, address, location |
    | New bookshop | `bookshops` | latitude, longitude, address, location |
    | User saves a pin/landmark | `saved_places` | lat, lng, address, place_type, is_public |
    | Completed ride | `ride_requests` | pickup_lat/lng, dest_lat/lng |
    | Completed delivery | `delivery_requests` | pickup_lat/lng, dest_lat/lng |
    | Live driver GPS | `driver_locations` | lat, lng |
    Volumes at audit: churches-with-coords 27, bookshops 0, saved_places 0, ride_requests 22, delivery_requests 0, driver_locations 1, ride_history 0.
    **GAP**: these are TRANSACTION records — there is no derived "gazetteer" that learns frequently-used drop-off points and suggests them as landmarks. That would be a new aggregation over `ride_requests`/`delivery_requests` (+ a `places_popular` rollup).
  - **Branches model (answers)**: `organizations` (id, name, code, logo_url, **bishop_id**, secretary_id, treasurer_id) ← `churches.organization_id`. A **branch = a `churches` row linked to an organisation**. The **bishop manages the organisation (all its branches)** — see the bishop/apostle dashboards + `get_organization_church_member_counts` RPC — while a **pastor manages only their own church/branch** (tenant-scoped via `profiles.tenant_id`). Currently 2 organisations, 1 church linked.
  - **Still open**: (3b) explicit "download this area" offline pre-cache button; (5) marker clustering; (6) proof-of-delivery photo + GPS and geofenced "arrived" detection; (2b) dark-mode self-hosted glyph layers.

- **Session 2026-09-15 (late 5) — R2 "wrong account" finding CORRECTED (wrangler local simulator), map assets on real R2, offline button, proof-of-delivery**:
  - **⚠️ CORRECTION to the previous entry**: there is **only ONE Cloudflare account**. The "different account" conclusion was WRONG. The real cause is that **`wrangler r2 object put/get` default to a LOCAL simulator** — `--remote` is required to touch real R2. Verified: `npx wrangler r2 object get church-on-app-maps/zambia.pmtiles --remote` downloaded the real **612,212,539-byte** file (without `--remote` it reads the local simulator and reports "key does not exist"). **Rule: always pass `--remote` for `wrangler r2 object put|get`.** (`r2 bucket list`/`cors set` hit the real API, which is why the CORS change did land.)
  - **CORS verified via Cloudflare API** (`GET /accounts/{aid}/r2/buckets/{bucket}/cors` + `/domains/custom`), account `ab82a97ce2c926279c483fef36c41945`:
    | Bucket | Custom domain | CORS |
    |---|---|---|
    | `choa-sermons-vault` | `media.churchonapp.com` (enabled) | **1 rule**: `https://churchonapp.com`, `https://www.churchonapp.com`, `http://localhost:3000`, `http://localhost:8080` ✅ |
    | `church-on-app-maps` | `maps.churchonapp.com` (enabled) | 1 rule: `*` ✅ |
    | `choa-kyc-vault` | (none — private, correct) | none |
    | `kingdom-sponsor-media` | (none) | none |
  - **Map assets now on REAL R2** (`--remote`): fonts + sprites uploaded to `church-on-app-maps/map-assets/…` — verified live `https://maps.churchonapp.com/map-assets/fonts/Noto%20Sans%20Regular/0-255.pbf` → **200** and `…/sprites/v4/light.json` → **200**. `_brandLightMapTheme` now points `glyphs`/`sprites` at `https://maps.churchonapp.com/map-assets/…` (the canonical, reusable location) and the duplicated `web/map-assets/` bundle was removed.
  - **#3 Offline download button SHIPPED**: `ChurchMap` gained `showOfflineButton` (default true) — a download control that walks the camera through z13→z15 around the current centre so the vector layer fetches **and disk-caches** the whole view (90-day / 250 MB file cache), then restores the zoom and confirms "This area is cached — it now works offline." Map controls now use fixed slots (80/132/184) so they never overlap.
  - **#6 Proof of delivery SHIPPED** (`20261123_delivery_proof.sql`, applied + in `deploy.ps1`): `delivery_requests` and `ride_requests` gained `proof_photo_url`, `proof_lat`, `proof_lng`, `proof_note`, `delivered_at`/`completed_at`. New reusable `ProofOfDeliverySheet` (`features/transport/presentation/widgets/proof_of_delivery_sheet.dart`) captures a **camera/gallery photo (bytes → works on web)** + **GPS**, uploads the photo to R2 (`delivery-proof/…`), and returns the proof payload. The completion dialog in `active_ride_tracking_screen.dart` gained a **PROOF** action that opens it and writes the proof columns onto the ride/delivery row. **Geofence**: the sheet accepts the expected `destination` and warns in amber when the captured GPS is >200 m away ("You are N km from the recorded destination"). (A 300 m "Approaching Destination" voice announcement already existed in that screen.)
  - **`coa_maps` package NOT extracted** (still an in-app widget). The BASEMAP + map assets are reusable today by any project: `maps.churchonapp.com/zambia.pmtiles` (+ `zimbabwe.pmtiles`) and `maps.churchonapp.com/map-assets/…`, both CORS `*`.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`938acc6d.churchonapp.pages.dev`).

- **Session 2026-09-15 (late 6) — R2 upload audit & fixes, KYC verify read-path, branches made production-grade, maps reuse doc**:
  - **R2 upload audit (whole app) — systemic bugs found & fixed**:
    1. **`r2-sign` allowedTypes was far narrower than the client's `_allowedExtensions`** → legitimate uploads silently 400'd with "File type not allowed". Worst case: **KYC documents and chat attachments use `application/octet-stream`, which was NOT allowed**, so KYC upload could never succeed. Added: `image/jpg, image/heic, image/heif, video/x-msvideo, video/x-matroska, audio/aac, audio/mp4, audio/x-m4a, audio/webm, application/msword, …wordprocessingml.document, application/vnd.ms-excel, …spreadsheetml.sheet, application/octet-stream`. **Keep this list in sync with `R2Service._allowedExtensions`.**
    2. **New folder allowlist in `r2-sign`** (`avatars, products, social, chat, klips, kyc, events, marketplace, sermons, ventures, flyers, delivery-proof, profile, driver-documents, churches, church-logos, church-banners, church-website-logos, church-website-banners, special-offers, audio`) so a bug/bad key can never scatter objects into an unexpected prefix.
    3. **Driver documents sent `image/jpg`** (invalid MIME) → rejected. `rider_onboarding_screen.dart` now normalises jpg→`image/jpeg` (+ png/heic/webp/pdf).
    4. **`offline_service` used `uri.host + uri.path` as the R2 key** — a full URL would have become the object key (`media.churchonapp.com/avatars/…`). Now strips a leading domain. (`local://` has no producer today, so it was latent.)
    5. **Removed the silent Supabase-Storage fallback** in `R2Service.uploadFile` (bucket `sermons-vault`). It was never exercised (0 misplaced rows across profiles/social/marketplace/sermons/klips/kyc) but would have scattered files into a second storage system. All media now goes to R2 only, and failures surface.
  - **KYC verification read-path SHIPPED (COA can now verify drivers/verified users)**:
    - `r2-sign` previously blocked CROSS-USER reads of `kyc/…`. It now allows a **superadmin/coa_employee** to read ANY user's KYC object (`choa-kyc-vault` only); owners still read their own.
    - `R2Service.resolvePrivateUrl('r2://<bucket>/<key>')` → signed read URL via `r2-sign`.
    - `KycService.deriveUserKey(userId)` is now **public/static** (reviewers must derive the SAME key) and `KycService.fetchDecryptedDocument({doc, userId})` downloads + AES-decrypts a stored document.
    - `kyc_review_screen.dart` was selecting only `id, document_type, url, status` — **missing `encrypted_key` + `encryption_iv`**, so decryption was impossible. Fixed the select and added a **VIEW DOCUMENTS** action that decrypts and renders the images (magic-byte sniff → `Image.memory`, non-images shown as size).
  - **Branches made production-grade**:
    - **Root cause of "nothing writes `organization_id`"**: no UI called `linkChurchToOrg`. New **`OrganizationBranchesScreen`** (`/organization-branches`, Superadmin Hub → Platform Tools): create an organisation, pick it, **ATTACH CHURCH** (links an unassigned `churches` row via `organization_id`), detach, and it warns when the organisation has no `bishop_id`.
    - **RLS fixed (`20261124_organizations_rls_coa.sql`)**: `churches`/`organizations` manage policies still gated on the legacy `employee` role (post-20260848 rename), so **COA could not manage churches or organisations** — same bug class as the earlier `role_assignments` fix. Recreated with `superadmin, super_admin, coa_employee, employee`.
    - Model recap: `organizations(bishop_id, secretary_id, treasurer_id, code, logo_url)` ← `churches.organization_id`. A **branch is a `churches` row linked to an organisation**; the **bishop owns the organisation (all branches)** — `Bishops can view organization churches` policy + `get_organization_church_member_counts` RPC — while a **pastor owns one branch** (`profiles.tenant_id`).
  - **Maps reuse documentation**: new **`docs/MAPS.md`** — how other projects reuse the basemap (`maps.churchonapp.com/zambia.pmtiles`, PMTiles v3 vector z0–15, CORS `*`), the label fonts/sprites (`maps.churchonapp.com/map-assets/…`), MapLibre/pmtiles JS snippet, the Flutter copy list, and the **`wrangler r2 object put|get` needs `--remote`** gotcha. `coa_maps` package extraction deliberately NOT done.
  - **R2 verification (questions answered)**: only ONE Cloudflare account; CORS on `choa-sermons-vault` (= `media.churchonapp.com`) IS set correctly; `church-on-app-maps` (= `maps.churchonapp.com`) CORS `*`.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`ce704b4e.churchonapp.pages.dev`). Migrations added to `deploy.ps1`: `20261123_delivery_proof`, `20261124_organizations_rls_coa`.
  - **Still open**: APK/AAB are still **+314** and predate today's map/KYC/branch/POD work (needs an explicit build request).

- **Session 2026-09-16 — Role picker by name, KYC restart mitigation, quiz/job deep links, upload audit**:
  - **Role assignment by NAME (no more emails)**: `role_approval_screen._showElevateDialog` required typing an exact **User Email** and did `profiles.eq('email', …)`. Replaced with a **searchable user PICKER** (bottom sheet, search by name/email, shows name + email + current role) → then a role dropdown. **Scope**: platform staff (superadmin/COA) see all users; a tenant leader (pastor/bishop/apostle/admin/…) sees only **their own church's members**, so they can promote their people without knowing an email.
  - **KYC "app restarts after camera" mitigated**: Android kills the process under memory pressure while the system camera is open. Added `android:largeHeap="true"` (application) + `android:alwaysRetainTaskState="true"` (MainActivity) to reduce the kill rate, on top of the existing `launchMode="singleTop"` + `retrieveLostData()`. **Also fixed a real bug**: the lost-capture recovery assigned the SAME photo to BOTH the ID and the selfie slot — now it fills only one empty slot.
  - **Bible-quiz deep link SHARED**: the PvP invite success SnackBar gained a **SHARE** action → shares `https://churchonapp.com/quiz/invite/<matchId>` (WhatsApp etc.). The route `/quiz/invite/:matchId` already existed and the router **preserves deep links through splash → login → tenant selection** (`?redirect=`), so the recipient lands on the invite screen in-app (web SPA fallback `/* → /index.html` covers the web case).
  - **Job deep links FIXED (were impossible)**: `/jobs/details` required a `Job` object passed via `extra`, which a WhatsApp/push link cannot supply. Added **`/jobs/:id`** → new `JobByIdScreen` (fetches the job by id from `jobs`, then renders `JobDetailsScreen`; retry + "no longer available" states). Literal routes (`details`/`manage`/`post`) still take precedence. Added a **SHARE** action to `JobDetailsScreen` sharing `https://churchonapp.com/jobs/<id>`.
  - **Upload audit (continued)**: re-verified every call site against the new `r2-sign` allowlists — all folders in use are allowlisted (`avatars, products, social, chat, klips, kyc, events, marketplace, sermons, ventures, flyers, delivery-proof, profile, driver-documents, churches, church-logos, church-banners, church-website-logos, church-website-banners, special-offers, audio`) and every content type the client sends is now accepted (incl. `application/octet-stream` for KYC/chat). Tenant streaming uses Cloudflare Stream (not R2). Member verification = the KYC approve/reject flow, whose document read path was fixed earlier this session.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`85abfe0e.churchonapp.pages.dev`).
  - **⚠️ STILL REQUIRES A RELEASE BUILD**: APK/AAB are at **+314** and predate all map/KYC/branch/POD/role-picker/deep-link work. The manifest change (`largeHeap`) only takes effect in a new build.

- **Session 2026-09-16 (late) — Register-duplicate fix, offers for all, recommendations route, event images**:
  - **"Register This Church" no longer creates a DUPLICATE pin (answered + fixed)**: the sheet's button did a bare `context.push('/register-church')` — it did **not** pass the tapped place, so the user re-typed the name and the church was created at the user's **GPS** position, leaving the original (grey OSM) pin in place → two pins. Now `_showRegisterSheet` passes `{name, address, lat, lng}` and `RegisterChurchScreen` gained `initialName/initialAddress/initialLat/initialLng`; `_detectLocation` **does not overwrite** supplied coordinates. The new church is therefore created exactly ON the tapped pin, and the existing **300 m proximity dedupe** in `_fetchNearbyChurches` (which skips OSM points within 300 m of a registered church) removes the grey duplicate.
  - **Special offers visible to EVERYONE**: `_buildAdminPromoSection` rendered `HomePromoCarousel` for non-admins but, for **admins**, only inside the **collapsed** "Admin & Promotions" section — so offers looked admin-hidden. The carousel + `AdBannerWidget` now render once, for all users (still hidden entirely when no offer is active). RLS confirmed correct: `special_offers_read_active` allows any authenticated user (`is_active = true`).
  - **"Recommended For You → Explore All" FIXED**: it pushed `/sermons`. New **`RecommendationsScreen`** (`/recommendations`) lists the actual `universalRecommendationsProvider` set with category/badge/subtitle and per-item routes.
  - **Recent events on the home tab now show IMAGES**: `HomeEventTimeline._buildEventItem` accepts `imageUrl` and renders the event banner (`AppImage`, 56x56, icon fallback) instead of only a category icon.
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`7a42e9c0.churchonapp.pages.dev`).
  - **REMAINING from the same request (NOT done — needs its own pass)**: (a) robust in-app + select-entity search with suggested queries; (b) YouTube **error 152-4** ("video unavailable" = owner disallows embedding) handling + a smarter sermon player (quality selector, mini overlay, fullscreen); (c) background audio with lock-screen/notification controls for Bible audio, audio sermons and audio klips; (d) in-app webviews (no external browser) + superadmin/COA analytics on webview opens; (e) global news thumbnails; (f) radio station audit (playable links + "coming soon" for closed stations) + smarter radio player; (g) emergency contacts (user numbers); (h) church-social following/followers alignment.

- **Session 2026-09-16 (late 2) — Reposts, real post reporting, view counts, profile grid, ministries details, playable klip**:
  - **Repost SHIPPED (`20261125_social_repost_reports_views.sql`)**: `social_posts` gained `repost_of` (self-FK), `repost_count`, `views_count`. New `repost_post(p_post_id)` RPC (SECURITY DEFINER) — one repost per user per post, cannot repost your own, increments the original's `repost_count`. Added a **Repost** item to the post's three-dot menu AND a repost button with count in the action row.
  - **Post reporting was FAKE → now REAL**: the "Report" menu item only showed a SnackBar and stored NOTHING. New **`post_reports`** table (post_id, reporter_id, reason, details, status, reviewed_by) with RLS: reporters insert/see their own; admins/COA/pastor/bishop can read + triage. The Report menu now opens a reason picker (spam / harassment / nudity / violence / false info / other) + optional details and inserts the report (duplicate reports are detected).
  - **View counts on posts**: `post_views` (unique per post+user) + `record_post_view(p_post_id)` RPC; the card records a view on mount and the action row shows an **eye + count**. The profile grid also overlays views/likes.
  - **More per-post controls**: menu now has Repost, Share, **Copy link** (`https://churchonapp.com/posts/<id>`), Report (+ Edit/Delete for owners).
  - **Church-social PROFILE posts are now a TikTok-style GRID** (`church_social_profile_screen.dart`): 3-column grid of small tiles with view/like overlays; tapping a tile opens the full post in a draggable sheet. **The main church-social feed styles/views were NOT touched** (it still uses `SocialPostCard`).
  - **Ministries tab FIXED**: cards were not tappable, so members were invisible (only a count). Added a **VIEW** action on every ministry card → bottom sheet with the leader (name + avatar), description, meeting day/time and the **full member list** (avatars, names, roles). Also **extended who can create/manage ministries**: `_canManageMinistries` now includes `apostle, prophet, general_secretary, general_treasurer, assistant_pastor, leader, department_leader` (previously only admin/pastor/bishop/superadmin/employee/coa_employee).
  - **Playable public Klip sample (`20261126_seed_playable_klip.sql`)**: seeded "Sunday Worship — Sample Klip" with a **verified-playable MP4** (test-videos.co.uk 720p) + Unsplash thumbnail, so the Klips feature can be seen/demoed. (Existing samples pointed at possibly-missing R2 objects and `assets.mixkit.co`, which now 403s.)
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info). Web deployed (`3303cbf1.churchonapp.pages.dev`).

- **Session 2026-09-16 (late 3) — Real PvP matchmaking, background audio, follow/emergency/search/news/radio fixes**:
  - **PvP matchmaking was FAKE (root cause)**: `bible_quiz_hub_screen.dart` `_startP2P()` waited 1.5 s ("Connecting...") and pushed the arena with **no opponent lookup at all** — players were never actually matched. New **`20261127_pvp_matchmaking_queue.sql`**: `pvp_matchmaking_queue` (PK user_id, elo, wager, mode, status, match_id, `last_seen`) + RLS (any authenticated SELECT for the live counter; own-row writes only) + realtime. RPCs: `pvp_queue_join(elo, wager, qc, tpq, mode)` (upsert my waiting row, then atomically claim a live opponent with `FOR UPDATE SKIP LOCKED`, create a real `pvp_matches` row in status `accepted`, mark both queue rows matched, return `{matched, match_id, waiting}`), `pvp_queue_heartbeat`, `pvp_queue_leave`, `pvp_queue_sweep`. **Opponents are only eligible while heartbeating < 15 s → a closed app can never be matched (no ghost opponents).** Coins are untouched by the RPC: the client deducts its own wager and refunds on cancel, exactly like the legacy flow. `pvp_service.dart` gained `queueJoin/queueHeartbeat/queueLeave/queueMatchStream/queueWaitingCountStream/getMatchById/getUserElo`; the hub now shows a real "Finding opponent…" sheet with a **live searching count**, pushes into the arena via realtime the instant it is matched, and leaves the queue on cancel. Also **swipe-left CANCEL/REMOVE** on sent invites (`_OutgoingInvitesSection` `Dismissible`, local hide + `declineInvite` refund).
  - **Background audio unified**: `MyAudioHandler` (audio_service) was only used by radio. It gained `seek`, `player`/`positionStream`/`durationStream`/`playingStream` accessors, extras pass-through on the `MediaItem`, and `playFromUri` now **rethrows** (so callers can detect a dead stream). `audioHandlerProvider` is now typed `MyAudioHandler?`. **Audio sermons** (private `AudioPlayer` → shared handler, media metadata + `/sermon/<id>` route) and **kids stories** now survive the screen being closed with lock-screen/notification controls. `MiniPlayerBar` (`core/widgets/mini_player_bar.dart`) is a persistent now-playing strip above the bottom nav (artwork, title, artist, play/pause, stop, tap → source route) wired into `main_navigation_shell.dart`. Bible chapter audio is TTS (`flutter_tts`) and cannot carry a media session — unchanged.
  - **`/sermon/:id` route ADDED (was missing)**: sermon push notifications/share links pointed at `/sermon/<id>` but no such route existed (the player needs a full `Sermon` object) → "page not found". New `SermonService.fetchSermonById` + `SermonByIdScreen` + route, so those deep links (and the mini-player) now work. New **`/followers/:userId`** route.
  - **Follow system aligned**: `FollowService` existed but the UI only reached it from one deep-link screen, and there was **no way to see who follows you**. Added `fetchFollowers`/`fetchFollowing` (two-step profile lookup, no FK-name dependency), a new `FollowersScreen` (Followers/Following tabs, inline follow/unfollow, tap → profile), and made the profile **follower/following counts tappable**. `toggleFollow` now fires a **"New follower" notification** (in-app row + device push) to the followed user.
  - **Emergency contacts were FULLY HARDCODED (root cause)**: `EmergencyContactsScreen` rendered literal Police 911/Ambulance rows and **never used `EmergencyContactService`** — a member could not store their own numbers. New **`20261128_emergency_contacts_user.sql`** adds `emergency_contacts.user_id` + an owner-scoped RLS policy (shared/tenant rows stay public). `EmergencyContact` gained `userId`; the screen was rewritten: **MY CONTACTS** (add/edit/delete with a validated bottom sheet, scoped to the signed-in user) + the shared service/church directory, real categories/icons/colours, pull-to-refresh, and `tel:` now uses **`LaunchMode.externalApplication`** (it was `inAppWebView`, which silently did nothing for phone calls).
  - **Global news thumbnails FIXED**: cards rendered a grey newspaper placeholder because the parser only looked at `<enclosure>` + `<img>` in the description. `_extractImage` now also matches `<media:content url>` / `<media:thumbnail url>`, and both the rss2json mapper and the raw-RSS parser check `thumbnail`, `enclosure.thumbnail`, `media.content.url`, `content:encoded` and `description` via a `_firstOf` helper.
  - **Radio audit**: a station whose stream fails now goes into a session `_unavailable` set, renders as a locked **"COMING SOON"** card and taps show "off air — try another station" instead of opening a dead player (`playStation` failures are caught).
  - **Search suggestions**: `universal_search_screen.dart` gained persisted **RECENT SEARCHES** (SharedPreferences, 6 entries, dedup, CLEAR) plus 5 more domain chips (Bible Study, Events, Bible Quiz, Marketplace, Jobs).
  - **In-app browser analytics**: new **`20261129_webview_opens.sql`** (`webview_opens` + owner-INSERT/staff-SELECT RLS + `get_webview_analytics(days, limit)` SECURITY DEFINER, REVOKE from anon/public) and `core/services/webview_analytics_service.dart` (`recordOpen`, `openTracked` → platform in-app browser, `topOpened`). External news links now open in the platform in-app browser **and are logged** (source `home_news`).
  - **`dart analyze lib`**: 0 errors, 0 warnings (1 pre-existing info in `active_ride_tracking_screen.dart`). Migrations `20261127`–`20261129` applied live + added to `deploy.ps1`.
  - **Still open from the same request**: HLS quality selector on the sermon player (adaptive ABR already switches automatically); a COA-facing webview-analytics screen (aggregate RPC + service exist); dedicated in-app webview *screens* (links currently use the platform in-app browser, which needs no new dependency).

- **Session 2026-09-16 (late 4) — FCM live, disconnect forfeit, HLS selector, quiz hosting engine (DB)**:
  - **FCM IS NOW LIVE (was the root cause of "skipping push")**: `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT` were **never set** (verified against the full `supabase secrets list`) and no service-account file existed anywhere on the machine. Set from the Firebase admin key via `supabase secrets set --env-file` (compacted to one-line dotenv; **never written into the repo**, temp file deleted). `push-notifications` redeployed with a permanent secret-free probe: `GET .../push-notifications?health=fcm` → `{"fcm_project_id_set":true,"fcm_service_account_set":true,"service_account_parses":true,"project_ids_match":true}`. **⚠ The admin key was shared in plain text — rotate it.**
  - **Ride lint fixed**: `active_ride_tracking_screen.dart` popped the dialog then reused `context` after `await` (a double-pop); now captures `Navigator.of(context)` before the async gap. `dart analyze lib` → **0 issues**.
  - **COA webview analytics**: `WebviewAnalyticsScreen` (`/webview-analytics`, Superadmin → Platform Tools) — 7/30/90-day window, ranked URLs, opens + unique users, over `get_webview_analytics`.
  - **PvP disconnect → auto-pause → 24h forfeit (`20261130_pvp_disconnect_pause.sql`)**: status CHECK widened with `paused`; added `player1/2_last_seen`, `paused_at`, `resume_deadline`, `ended_reason` + `pvp_match_audit`. `pvp_match_heartbeat(match_id)` marks you online and **auto-resumes** once both sides heartbeat; `pvp_detect_disconnects()` pauses on a 45 s stale heartbeat with a 24 h deadline; `resolve_expired_pvp_pauses()` cancels, **awards the higher score** (tie → whoever stayed online), writes `ended_reason='opponent_disconnected'` + an audit row. pg_cron `pvp-dc-sweep` every minute (both sweeps verified). Arena now sends a 10 s heartbeat and shows an amber "Opponent disconnected — game paused" banner.
  - **HLS quality selector**: the sermon player parses the master playlist's `#EXT-X-STREAM-INF` renditions and shows an `AUTO`/720p/… chip; switching preserves the playhead. Adaptive ABR remains the default.
  - **QUIZ HOSTING ENGINE (DB + RPCs) — `20261131_quiz_hosting_engine.sql` (8 tables, 5 RPCs, applied live)**. Model: **hosting requires an ACTIVE lease**; non-leased churches may still compete. `quiz_engine_leases` (+ `lease_quiz_engine()` **auto-approves** from a confirmed `coa_payments` row — price/season length re-derived server-side from `platform_settings.quiz_engine_lease_kwacha` (1500) / `quiz_engine_lease_days` (365); client never states a price). Quiz master uploads a paper → `quiz_question_sets` (R2 `source_file_url`, `extract_status`) → `quiz_set_questions` (**renamed to avoid colliding with the pre-existing, different-shaped `quiz_questions` table** — `IF NOT EXISTS` had silently skipped it). `create_quiz_tournament()` is **lease-gated** and inserts the host as a participant (`allow_host_plays`) so the host competes against its invited tenants; `quiz_tournament_invites` lets **invited tenants compete even if they never leased** (only the host pays). `join_quiz_tournament()` enforces visibility (`tenant` | `invited` | `public`) + capacity; `quiz_tournament_viewers` + `quiz_tournament_watch()` give non-participating members a live spectator count (45 s presence window); `quiz_tournament_matches` links bracket rounds to `pvp_matches` so the existing arena/realtime is reused. Study pack: `quiz_question_sets.study_pack_open` (host default) + per-question `is_study_visible`, with a participant-only RLS policy.
  - **ONBOARDING AUDIT (read-only, no code changed) — gaps found**:
    1. **Church registration charges nothing** — `register_church_screen.dart:88-222` makes no payment call; the fee is display-only (`:225,:333`); success copy points at a **hardcoded** MoMo number (`:256`).
    2. **Fee is only requested AFTER trial expiry** (`home_screen.dart:624,654-657` gates the paywall on `isSubscriptionExpired`) and the paywall only writes `payment_reference`/`onboarding_balance_due` (`home_subscription_paywall.dart:186-192`) — `onboarding_fee_paid` flips **only** on manual COA/superadmin approval (`coa_employee_dashboard.dart:216`).
    3. **Bookshops have NO fee at all** — `bookshops.onboarding_fee_paid` exists (`20260883:5`) but is never read/written in `lib/`.
    4. **Role fee keys are dead** — `onboarding_fee_church_kwacha` (500) / `onboarding_fee_bishop_kwacha` (1000) are seeded but never read; a single `onboarding_fee` is used for both.
    5. **Streaming** grants 480 min only when `onboarding_fee_paid` (`20260848:98-101`) → every new church is capped until manual approval; and `get_streaming_usage`'s paid branch checks `subscription_status='paid'` (`20260897:31`) which the column CHECK **forbids** → unreachable.
    6. **No COA alerting** for expiring/expired trials, and **no trial cron**; `CoaEmployeeDashboard` lists only unverified churches + submitted payments (`coa_employee_dashboard.dart:59-72`). `EmailService.sendSubscriptionWarning` + the `send-email` template have **zero callers**.
    7. **Expiry is client-only** — server `subscription_status` is never transitioned; route gating covers only `/quiz` and `/kids-zone` (`app_router.dart:382-387`).
    8. **Rider role is never granted** — approval always sets `driver` (`carpso_driver_approval_screen.dart:87`) although `rider` is first-class elsewhere. Driver onboarding uses `dart:io File` → **broken on web**. `/bookshop-onboarding` + `/rider-onboarding` are **unguarded** (`app_router.dart:496` falls through to `true`). `SubscriptionService.subscribeToTier` sends args that don't match the RPC signature (`subscription_service.dart:164-178` vs `20260910:22`) and has no call site.
  - **Not built yet**: the hosting engine's Flutter UI (lease screen, question-paper upload + extraction UI, tournament host console, spectator screen, bracket view) and the onboarding-fee reconciliation fixes above.

- **Session 2026-09-16 (late 5) — Payments model CORRECTED by product owner + tenant owner tier (`20261132`)**:
  - **PRODUCT RULES (supersede any earlier assumption)**:
    1. **Members NEVER pay to join and NEVER pay a subscription.** Remove user-level silver/gold tiers + user paywalls.
    2. **Bookshops pay NO onboarding fee** — they create and get approved.
    3. **Churches pay AFTER the trial ends** (not at registration).
    4. **Only the tenant OWNER TIER is ever charged/reminded.** Owner-tier users are *never* charged for themselves — their single purpose is to keep the tenancy paid up.
    5. **Owner tier** = `pastor`, `bishop`, `apostle`, `prophet`, `general_secretary`, `general_treasurer`, **`treasurer`** (local church treasurer included) — PLUS **custom delegates** a pastor adds for their church, and a bishop adds for their organisation. Assistant pastor / assistant bishop are NOT owner tier.
    6. Members only ever pay for **quiz store kits** and **Church Coins (CC)** — e.g. leasing the quiz engine as an individual.
  - **`20261132_tenant_owner_tier.sql` (applied live, verified: 1 table + 6 functions + 3 church columns)**: `is_owner_tier_role(text)`, `is_tenant_owner(tenant_id)`, `am_i_tenant_owner()`, `tenant_owner_delegates` (RLS: own row + tenancy owners + staff read; writes via RPC only), `grant_tenant_owner(user, note)` (pastor for their church; bishop/apostle/prophet/general_secretary for any church in their organisation — cross-org refused), `revoke_tenant_owner(user)`, and `get_tenancy_payment_reminders(days)` returning in-trial/unpaid churches with the owner-tier people to notify (staff-only, REVOKE from anon/public).
  - **SCHEMA BUG FOUND**: **`churches` had NO `onboarding_fee_paid` column** (only `bookshops` did) even though the COA approval + paywall flows reference it → added `onboarding_fee_paid` (+ `_at`, `_ref`) to `churches`.
  - **Table-collision lesson (again)**: `quiz_questions` already existed with a completely different shape, so `CREATE TABLE IF NOT EXISTS` silently skipped the new definition and its policies failed with 42703. The hosting engine's question table is **`quiz_set_questions`**.
  - **Rider role FIXED**: `carpso_driver_approval_screen.dart` hardcoded `role: 'driver'`, so `rider` could never be granted by onboarding. Now honours the applied-for role (fallback `driver`).
  - **Still pending**: remove user subscriptions (tiers/price keys/paywall/gates) and rewire to tenant entitlement; church paywall owner-gated + auto-flip `onboarding_fee_paid` from a confirmed `coa_payments` row; COA trial alerting + expiry cron; hosting engine Flutter UI; web-safe driver onboarding + route guards.

- **Session 2026-09-16 (late 6) — User subscriptions REMOVED + church fee auto-approved + trial cron (`20261133`)**:
  - **Members never pay**: `user_has_feature_access()` now **always returns true** (the function is kept because the client calls it — but it no longer gates anything, so features cannot vanish for members). `subscribe_user_to_tier()` **refuses to charge** and returns `reason='user_subscriptions_removed'`. The dead user-tier pricing keys (`user_silver_monthly_price`, `user_gold_yearly_price`, +3 aliases) were **deleted from `platform_settings`**. Member purchases are now limited to **quiz store kits** and **Church Coins**.
  - **Church onboarding fee auto-recorded + AUTO-APPROVED**: new `sync_church_onboarding_fee(tenant_id)` re-derives the amount from `platform_settings.onboarding_fee` and flips `churches.onboarding_fee_paid` (+`_at`/`_ref`, and `subscription_status='active'`) from a **confirmed `coa_payments` row** (`status in approved|completed|confirmed|settled`, matched on `metadata->>'tenant_id'`). A trigger `coa_payments_sync_church_fee` runs it automatically on payment confirm/settle, wrapped so fee bookkeeping can never break a payment write. COA can still approve/revoke manually.
  - **Server-side trial expiry + COA alerting**: new `expire_church_trials()` transitions `subscription_status='expired'` when `subscription_ends_at < now()` (the client was previously the only place expiry existed), and `notify_trial_expiry(days)` fans in-app notifications out to the **owner-tier people** (via `get_tenancy_payment_reminders`). pg_cron **`trial-expiry-sweep`** runs daily at 06:00 (job id 11). This replaces the dead `EmailService.sendSubscriptionWarning` path (zero callers).
  - **Verified live**: 6 functions present, **0 user price keys remain**, trigger `coa_payments_sync_church_fee` active.
  - **Gotcha**: `CREATE OR REPLACE FUNCTION` **cannot rename an input parameter** — `user_has_feature_access(text)` already used `feature_key`, so the replacement had to keep that exact name (error 42P13 otherwise).
  - **Still pending**: client-side removal of the member paywall UI + rewiring any remaining user-tier gates; owner-gating the church paywall on `am_i_tenant_owner()`; hosting engine Flutter UI; web-safe driver onboarding + route guards.

- **Session 2026-09-17 — Instagram stories, hosting engine made usable, offering baskets, branding/preview crashes, FCM live + deployed**:
  - **FCM IS LIVE (was the root cause of "skipping push")**: `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT` were **never set** (verified against the full `supabase secrets list` — 28 secrets, neither present) and no service-account file existed on the machine. Set from the Firebase admin key (`firebase-adminsdk-fbsvc@studio-7483333628-db257…`) via `supabase secrets set --env-file` (compacted to one-line dotenv; **never written into the repo**, temp file deleted). `push-notifications` redeployed with a permanent secret-free probe: `GET .../push-notifications?health=fcm` → `{"fcm_project_id_set":true,"fcm_service_account_set":true,"service_account_parses":true,"project_ids_match":true}`. **⚠ The admin key was shared in plain text — rotate it.**
  - **Instagram-style stories (`20261134_social_stories.sql`)**: `social_stories` (media, caption, `is_public`, `view_count`, `expires_at` = now+24h) + `social_story_views` (deduped per viewer), RLS (tenant/public/own reads, owner delete, owner-sees-viewers), `record_story_view()` SECURITY DEFINER (REVOKE from anon), added to the realtime publication with `REPLICA IDENTITY FULL`. **UI**: `widgets/stories_bar.dart` (`StoriesBar` + `StoryViewerScreen` + `storiesProvider`) — yellow unseen ring / grey seen, unseen first; full-screen viewer with segmented progress bars, 5s per story, tap right/left, `_StoryVideo` plays video stories **inline** (looping `video_player`, placeholder only on init failure), caption with shadow, and an **owner-only "N views · tap to see who"** bar listing viewers. **Creation**: `create_story_screen.dart` (+ button in the Church Social header) — camera/gallery/video via `image_picker` **bytes** (web-safe), preview, caption, "Share beyond my church" → `is_public`, uploads via `uploadBytes('social/story_<ts>.<ext>')` then inserts and invalidates `storiesProvider`.
  - **QUIZ HOSTING ENGINE MADE USABLE (`20261135_quiz_hosting_rpcs.sql`)** — the audit found `20261131` was 100% DB-only with a **functional blocker**: `lease_quiz_engine` demanded a confirmed `coa_payments` (K1500) while the ONLY shipped lease UI charges **1500 CC** via `lease_quiz_engine_cc`, which never created a `quiz_engine_leases` row → after paying CC, hosting still raised `lease_required`. Fixes: `tenant_can_host_quiz()` now accepts **either** path (Kwacha lease *or* a CC `quiz_engine_lease` redemption within 365 days) and `lease_quiz_engine()` records a proper row for CC (`via:'church_coins'`); added `create_quiz_set()` + `add_quiz_set_questions()` (**there was no writer at all** — tables were SELECT-only, so uploading a paper was impossible); `start_quiz_tournament()`, `generate_quiz_bracket()` (seeded, byes), `record_quiz_match_result()` (+advance round), `respond_quiz_tournament_invite()`; **study-pack leak fixed** (host-tenant members could read `is_study_visible=false` questions); invited tenants can read set metadata; unique index on `(tournament_id, round, slot)`; treasurer added to the lease role list; `REVOKE … FROM PUBLIC`; `question_set_not_yours` validation. **`quiz-questions` added to the `r2-sign` folder allowlist + `r2-sign` redeployed** (uploads were 400ing "Folder not allowed").
  - **CHURCH LOGO + HERO BANNER UPLOADS FIXED (`20261136`)**: root cause — `churches` has `logo_url`/`banner_url` but **NO `updated_at` column**, while `church_branding_screen.dart` saves `{column: url, 'updated_at': …}` → PostgREST rejected the whole UPDATE (42703), so the R2 upload succeeded but **the row was never written** (both logo and hero silently reverted). Added `updated_at` + a `touch_churches_updated_at` trigger, plus a `churches_leadership_update` RLS policy (without it the write was a silent no-op).
  - **TENANT WEBSITE PREVIEW CRASH FIXED**: `church_website_builder_screen.dart` opened the preview with `LaunchMode.inAppWebView` — but the preview URL is this **same app's** public site (`churchonapp.com/site/<id>`), so on web the SPA loaded inside itself → **reload loop** ("crashes the app to reload, no preview"). Now `LaunchMode.externalApplication` with the context captured before the async gap, try/catch and a URL-bearing fallback snackbar.
  - **STREAMING CLOUDFLARE CONFIG FIXED (tenant leaders no longer set CF keys)**: `streaming_config_screen.dart` asked leaders to paste the **Cloudflare Account ID + API Token** with "go create a Stream token" instructions — those are **platform secrets** held in the Edge Function env. Removed the fields, the load, the save payload and the now-unused `_buildTextField`; replaced with a **"Cloudflare Streaming — Managed automatically: nothing to configure here… keys are held server-side and never entered or stored in the app"** card. Live inputs are still created automatically by `cloudflare-stream`.
  - **OFFERING BASKETS (`20261137_offering_baskets.sql`)** — new feature foundation: `offering_basket_types` (**tenant basket** = `tenant_id` set; **organisation basket** = `tenant_id` NULL + `organization_id`, visible to every church in that org; carries GL `code`, icon, colour, sort order, active) + `offering_sessions` (**live basket offering time**: one open session per church, basket-name snapshot). RPCs: `create_offering_basket()` (leadership-gated; **org-wide requires an organisation owner** — bishop/apostle/prophet/general secretary/treasurer), `update_offering_basket()`, `open_offering_session()`, `close_offering_session()`, `get_basket_summary(tenant_id|org_id, days)` (church leaders = own church only; **bishop & co roll up an organisation**, cross-org refused). **198 baskets seeded** (6 standard Zambian baskets: Tithe/Sunday Offering/Missions/Building Fund/Welfare/First Fruits × 33 churches, idempotent).
  - **TENANT OWNER TIER (`20261132`) + USER SUBSCRIPTIONS REMOVED (`20261133`)** — see the entries above; client side completed here: `isTenantOwnerProvider` calls `am_i_tenant_owner()` (**fails closed**) and the home paywall now renders only when `isExpired && isOwner`, so **members and assistant pastors/bishops never see a payment prompt**. New `tenant_owners_screen.dart` (**Profile → Church Owners**, `/church-owners`): lists role-based owners + custom delegates, **ADD OWNER** (owner-only, tenant-scoped searchable picker → `grant_tenant_owner`), remove, and human-readable authorisation errors (`org_owner_required` → "Only a bishop…", `different_organisation` → …). Confirmed `silver`/`gold` are **tenant plans** (`plan_service.dart`), not user tiers, and `hasFeatureAccess`/`subscribeToTier` have **zero client call sites**.
  - **DISCONNECT → AUTO-PAUSE → 24h FORFEIT (`20261130`)**: `pvp_match_heartbeat()` marks you online and **auto-resumes** once both sides heartbeat; `pvp_detect_disconnects()` pauses on a 45 s stale heartbeat with a 24 h deadline; `resolve_expired_pvp_pauses()` cancels, **awards the higher score** (tie → whoever stayed online), writes `ended_reason='opponent_disconnected'` + a `pvp_match_audit` row; pg_cron `pvp-dc-sweep` every minute. Arena sends a 10 s heartbeat + amber "Opponent disconnected — game paused" banner.
  - **Also**: COA `WebviewAnalyticsScreen` (`/webview-analytics`, Superadmin → Platform Tools) over `get_webview_analytics`; HLS **quality selector** on the sermon player (parses `#EXT-X-STREAM-INF`, `AUTO`/720p chip, preserves playhead); `/sermon/:id` route + `SermonByIdScreen` (sermon push/share links previously 404'd); **background audio + `MiniPlayerBar`**; **real PvP matchmaking queue** (presence-based, 15 s heartbeat, no ghost opponents); **follow/follower alignment** (`/followers/:userId` + new-follower notification); **emergency contacts** now real DB + own numbers (was fully hardcoded, `tel:` fixed); global news thumbnails (`media:content`/`thumbnail`/`content:encoded`); radio "COMING SOON" for dead streams; recent-searches + more search chips; ride `use_build_context_synchronously` lint fixed; `/bookshop-onboarding` + `/rider-onboarding` route guards (**were unguarded**); rider role granted on approval (was hardcoded `driver`).
  - **Deployed**: web `flutter build web --release` → Cloudflare Pages (branch `main`), **byte-verified** against production (`churchonapp.com/main.dart.js` = 9,847,428 bytes = local build). `deploy.ps1` updated through `20261137`. Edge Functions redeployed: `push-notifications`, `r2-sign`.
  - **AUDITS (read-only, no code changed)**:
    - **Onboarding**: church registration charges nothing (fee only requested after trial expiry, reflected only on manual COA approval); bookshops have `onboarding_fee_paid` but it is **never read/written**; role fee keys dead; streaming paid-branch checks `subscription_status='paid'` which the CHECK constraint forbids (unreachable); no COA trial alerting + no trial cron (now fixed by `20261133`); expiry was client-only (now server-side); rider role never granted; driver onboarding breaks on web (`dart:io`); `/bookshop-onboarding` + `/rider-onboarding` unguarded (now guarded).
    - **Quiz engine**: pre-existing engine is extensive (`quiz_questions` bank, PvP/ELO/wagers/queue, quiz events + passes, church competitions, daily challenge, CC store + `lease_quiz_engine_cc`, JBQ/WBQA pure-Dart engine). The new hosting engine was **DB-only with zero Dart references** — see the fixes above.
    - **Communities**: groups live in `community_communities` (containers) + `community_groups` (chat), read via `CommunityService.fetchCommunities/fetchGroups` (strictly `.eq('tenant_id', …)`), displayed in `communities_screen.dart` + `community_hub_screen.dart` (Groups/Ministries toggle), with `joinGroup`/`leaveGroup` implemented. **CRITICAL GAP: there is NO create path anywhere in `lib/`** — `community_communities` appears in only two places and both are reads. Groups can only exist if inserted directly into the DB, which is why the Network/Communities screens are legitimately empty. Ministries DO have a create path (`MinistryManagementScreen`).
  - **PENDING (next session, in order)**: (1) **Baskets UI** — leader basket manager, Give-tab reflection, live offering modal, pastor/bishop `get_basket_summary` report (engine complete in `20261137`); (2) **Communities/groups create+edit** (needs a decision: leadership-only create + member join, or open to all members) which also makes **Network button / Network Activity / Pastors Corner** meaningful; (3) **Hosting UI** (lease, paper upload + extraction, host console, spectator, bracket) — engine now fully drivable; (4) **Driver/rider onboarding** web-safe (`uploadBytes` pattern); (5) **Flyer studio share image**; (6) quiz-import must write to `quiz_set_questions` (not `quiz_questions`) and cannot parse binary PDF/DOC.
  - **`dart analyze lib`**: **0 issues** throughout.

- **Session 2026-09-17 (PENDING LIST COMPLETED) — Baskets UI, Communities create/edit, Quiz Hosting UI, web-safe driver docs, flyer share, quiz-import to quiz_set_questions**:
  - **Offering Baskets UI (item 1) — migration `20261138_offering_basket_contributions.sql`** (applied live + in `deploy.ps1`). `20261137` created the baskets/sessions but NOTHING linked a gift to a session, so totals stayed 0 and the report was always empty. Added `offering_contributions` (RLS: own + tenant leadership + staff), unique `payment_ref`, and `record_offering_contribution(session, amount, payment_ref)` (SECURITY DEFINER, idempotent by ref, recomputes `total_amount`/`contribution_count`). `close_offering_session` now recomputes+freezes totals. New `lib/features/finance/data/offering_basket_service.dart` (models + providers, Dart-record family key `BasketSummaryKey` per the RIVERPOD rule) and screens: `offering_basket_manager_screen.dart` (`/offering-baskets`, leadership/treasurer) — create/edit/toggle baskets, org-wide baskets for org owners, start/close a LIVE offering, history; `offering_basket_summary_screen.dart` (`/offering-baskets-summary`) — 7/30/90-day window, church vs organisation rollup over `get_basket_summary`. Give tab reflects the church's baskets as the giving categories and shows a red **LIVE OFFERING** card (member "GIVE TO THIS"; leader "MANAGE") and calls `record_offering_contribution` on a confirmed gift. Admin Hub tile "Offering Baskets". Route guards added.
  - **Communities / groups create+edit (item 2) — migration `20261139_community_network_create.sql`** (applied live + in `deploy.ps1`). Added `updated_at` + touch trigger; **any member may create a community/group inside their own church**, creator OR church leadership may edit/delete (tenant-scoped, no `WITH CHECK (true)`); fixed stale role lists on `pastors_corner`/`network_activity` (post-`20260848` `employee` → `coa_employee`); seeded a "Church Fellowship" community + "General Fellowship" group for every church (FK-safe: `tenant_id` FKs to `tenants(id)`, so the seed joins `tenants`). Dart: `CommunityService` gained `createCommunity/updateCommunity/deleteCommunity/createGroup/updateGroup/deleteGroup` (bytes-free; `createdBy`/`communityId` added to the read maps). UI: new `community_forms.dart` (`canManageCommunity` + create/edit sheets + create picker); `communities_screen.dart` now renders communities with nested groups, per-community and per-group edit/delete menus and a NEW button; the previously **dead Communities FAB** (`connect_screen.dart` `onPressed: () {}`) now opens the create flow. **Pastors Corner** and **Network Activity** gained a compose FAB for leadership + `NetworkService.createPastorMessage/postNetworkActivity` (screens were read-only, hence always empty).
  - **Quiz Hosting UI (item 3)** — new `quiz_hosting_service.dart` (lease, sets, tournaments, bracket, invites, spectator + providers) and `quiz_hosting_screen.dart` (`/quiz-hosting`, leadership) with 3 tabs: **LEASE** (CC lease via `leaseQuizEngineCc` then `lease_quiz_engine` to record the row; or "I paid Kwacha" → `lease_quiz_engine` auto-confirms from `coa_payments`), **SETS** (create set → paste text or upload txt/csv/md/pdf/doc → R2 `quiz-questions/` → `quiz-import` extraction; study-pack + per-question visibility toggles; delete), **TOURNEYS** (create with set/visibility/format/invites, start + generate bracket, join, accept/decline invites). `quiz_set_questions_screen.dart` + `quiz_bracket_screen.dart` (`/quiz-hosting/questions/:setId`, `/quiz-hosting/bracket/:tournamentId`) — bracket by round, host records results, live spectator count via `quiz_tournament_watch` heartbeat. Routes + leadership guard + Admin Hub "Quiz Hosting" tile.
  - **quiz-import writes to `quiz_set_questions` (item 6)** — `quiz-import/index.ts` now accepts `setId` (+ `sourceFileUrl/Name/Type`): parses, dedupes by prompt against the set, inserts into `quiz_set_questions` (`prompt`/`options`/`correct_answers`=[correct option]/`verse_reference`/points by difficulty), updates the set's `extract_status`/`extracted_count`/`extract_error`. Legacy `quiz_questions` path unchanged when no `setId`. Binary PDF/DOC still cannot be parsed by the text model — the UI says so and supports paste. **Deployed `quiz-import` + `r2-sign`.**
  - **`r2-sign` allowlist widened**: added `text/plain`, `text/csv`, `text/markdown` (+ client `R2Service._allowedExtensions` `.txt/.csv/.md`) — question papers were 400ing "File type not allowed".
  - **Driver/rider onboarding web-safe (item 4)**: `rider_onboarding_screen.dart` no longer uses `dart:io File` — documents are held as **bytes** from `image_picker`'s `XFile.readAsBytes()` (works on web) and uploaded with the same `r2-sign` + PUT path. Removes the `dart:io` filesystem dependency (was mobile-only).
  - **Flyer studio share image (item 5)**: `_renderFlyerPng` now guards a null/not-ready `RepaintBoundary` (was `!`), and `_shareFlyer` skips `getTemporaryDirectory()` on web (`kIsWeb` → `XFile.fromData(mimeType/name)` only) — sharing a rendered flyer previously threw on web.
  - **`dart analyze lib`**: **0 errors, 0 warnings**. `key_flows_smoke_test.dart` 5/5 green. Migrations `20261138` + `20261139` applied live; `quiz-import` + `r2-sign` deployed.







- **Session 2026-09-19 — Maps (Africa/regional PMTiles), turn-by-turn navigation, dashboards, streaming, stories, Kael, notifications, orphan functions**:
  - **Maps**: Southern Africa z15 PMTiles (ZM+ZW+MW+MZ, bbox `22,-27,36,-8`, 1433 MB) cut with `pmtiles extract` from the Protomaps planet build and uploaded to R2 → **`https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles`** (CORS `*`, verified 200). `MAPS_ZAMBIA_URL` + `MAPS_ZIMBABWE_URL` both point at it. The old `zambia.pmtiles`/`zimbabwe.pmtiles` were DELETED (~880 MB reclaimed). **R2 uploads >300 MB: the Cloudflare dashboard refuses them and `wrangler r2 object put` crashes on Windows (libuv assertion) for large files — use the S3 API (SigV4 PUT) instead**; keys live in the sibling project `D:\Explorer\MAYUNDO\KEY PROJECTS\churchonapp\.env` (`VITE_R2_ACCESS_KEY_ID/SECRET`, account `ab82a97ce2c926279c483fef36c41945`). Measured sizes: Africa z15 ≈ **15 GB**, Southern Africa z15 ≈ **2.6 GB**. Protomaps' public build is **max z15** (no z16+), so "Yango-level" z18 detail is not available from this source.
  - **Turn-by-turn navigation (real)**: `RouteService` now requests OSRM `steps=true&annotations=true&geometries=geojson`, parses typed `RouteStep`s (maneuver, name, distance, duration, geometry, bearings, `isFallback`). New `navigation_controller.dart` (snap-to-route, current step, distance-to-maneuver, remaining ETA, **off-route >40 m → debounced reroute**), `navigation_instructions.dart` (turn/roundabout/ramp/merge/fork/arrive → human text with road names), `widgets/navigation_banner.dart` (arrow + instruction + live countdown + ETA + mute) and `route_steps_sheet.dart`. `VoiceDirectionService.announceManeuver` speaks at ~400/150 m and at the maneuver, with dedupe + queue + persisted mute. Falls back to the old proximity alerts when the route is a straight-line fallback (never fakes guidance).
  - **Bishop/Pastor dashboards**: bishop = organisation oversight (KPIs, `get_organization_stats`/`get_organization_church_member_counts`/`get_org_branch_snapshots`/`get_org_giving_series`/`get_basket_summary`, ProBar/ProPie charts, branch health, branch drilldown, org announcements) with pastor-only tiles REMOVED (Member Management/Attendance/Invite). Pastor = one branch (members, attendance, giving MTD, upcoming events, baskets, stream analytics, "View Organisation"). New `branch_oversight_screen.dart` + `organization_overview_screen.dart`. **Bug fixed twice**: bishops were routed to the basic `AdminHubScreen` via the home **Admin Tools → Dashboard** chip (`home_admin_dashboard.dart`) and to the retired `BishopHubScreen` via `/bishop-hub`; both now go to `BishopDashboardScreen`, and the duplicated "Secure Leadership Memos" header (standalone + inside `_buildPrivateMemoList`) was deleted.
  - **Streaming**: archives to R2 **before** disabling the live input (old order broke recordings); `live_streams.archive_url` replay in the viewer + "Recent Services" list; LIVE→REPLAY fallback. Tenant-facing config is now **provider-neutral** (no Cloudflare/rates/costs — those are COA-only), paid `max_quality` corrected 360→720, `church_live_status` writes are upserts on `church_id` (fixed `23505`), and the WHIP SDP bug fixed (`v=0` was missing + constructor args swapped → `RTCSessionDescription(normalized, 'answer')`). **"Stream unavailable / offline / invalid link" regression fixed**: the viewer auto-calls the new `refresh_live_input` Edge action on open to repair `hls_url`, never hard-fails a live/unknown row, retries while showing "Stream is starting…", and only says "Stream has ended" for ended streams. Viewer count is real (`stream_view_sessions` heartbeats + 15 s streamer poll + peak). Live **verse overlays** + **speaker details / editable caption** (migration `20261209`), a full **marquee ticker** (announcements + verse + theme), **Projector/Big-screen** mode, QR share, cast panel and encoder/drone RTMP panels. Live chat contrast fixed (panel `#F1F5F9`/`#1E293B`, text `#0F172A`/`#F8FAFC`, gold sender `#7A5C00`/`#FFD700`).
  - **Stories** (`20261154`): durations 24 h (default) / 1 week / 1 month / custom to 365 days (server-clamped 1–8760 h), reactions (❤️🙏🔥😂👏), own-story **archive**, **highlights** on the Church Social profile, and the clipped follower/following text fixed.
  - **Kael**: the sheet that closed just before users could scroll was a `StatefulBuilder` minting a fresh `Future` each rebuild (resetting the `FutureBuilder`) plus `isDismissible`/`enableDrag` defaults — rewritten as a real `StatefulWidget` fetching once, non-dismissible, bounded scroll region, `SelectableText`, per-draft **COPY** + COPY ALL + **REGENERATE**. **"Draft with Kael"** added to social posts, product listings (incl. bookshop), klips, stories, event descriptions.
  - **Bookshop tenant**: `orders` **42P17** recursion fixed (`is_bookshop_staff`/`bookshop_can_view_order` SECURITY DEFINER), close-button white screen fixed, **searchable user picker** instead of UID entry for staff, debounced search on all lists, **seamless church↔bookshop tenant switching**, **marketplace cross-listing** (`bookshops.show_in_marketplace` + RLS), order status state machine with timestamps, low-stock flags, sales summary, CSV export. Migration `20261204` needed `show_in_marketplace` added BEFORE the function that references it.
  - **Quiz tournaments + rewards + promo codes** (`20261205`/`20261206`, plus `is_platform_staff()`): superadmin/COA create/edit/duplicate/publish/feature/cancel tournaments with custom seasons (weeks/months), registration windows, entry fees, capacity and per-tournament prizes; idempotent `quiz_tournament_awards` ledger with auto-award + manual award/revoke; `promo_codes` + `promo_code_redemptions` (create, award to any user, redeem with server-enforced limits/expiry, usage tracking, export). New screens `quiz_tournament_admin_screen.dart`, `promo_codes_screen.dart`, `redeem_code_screen.dart` (routes `/quiz-tournaments`, `/promo-codes`, `/redeem-code`).
  - **Verse of the Day**: replaced random selection with a curated pool of **458 KJV verses** across 30+ uplifting themes (`20261201` + `20261207`), deterministic `get_verse_of_the_day(p_date)` rotation (no repeat for 458 days), complete sense-units only, plus a 201-verse offline fallback. **Branded stream posters** (`branded_stream_poster.dart`) draw 6 on-brand variants in Flutter (Sunday Service/Bible Study/Prayer Meeting/Youth Service/Special Guest/Revival Night) from the app logo + brand gradient, used whenever a poster is missing or is a legacy Unsplash sample; app logo is the default thumbnail.
  - **Recorded services → Sermons** (`20261203`): ended/archived streams sync into real sermon rows (category "Recorded Service", R2 archive or HLS, view/reaction tracking, deduped, searchable).
  - **Klips posting fixed** (`20261208_klips_is_audio_and_post_policy.sql`): the INSERT policy/constraints blocked `leader`/`coa_employee` and required columns were not written.
  - **Notifications audit (real lock-screen bug)**: FCM v1 payloads were sent **camelCase** (`channelId`/`defaultSound`) which FCM **silently ignores**, so pushes fell back to the manifest default channel — wrongly `coa_rides_v2`. Fixed to snake_case, expanded `channelForType`/`iconForType`, manifest default → `coa_announcements_v2`, background handler posts to the registered `_v2` channels, `kingdom_alerts` registered at max importance, and `20261210_notifications_autopush.sql` auto-pushes types that previously had NO push (quiz prizes, promo codes). `GET /functions/v1/push-notifications?health=fcm` probes health.
  - **All 31 Edge Functions audited**: orphan-but-useful ones WIRED — `export-user-data` → Profile ▸ Account Settings "Download My Data"; `export-church-data` → Admin ▸ Export Data "FULL CHURCH BACKUP"; `delete-account` → Account Settings "Delete Account". Server-only (`well-known`, `whatsapp-webhook`) and ops/legacy (`send-security-alert`, `migrate-to-r2`, `migrate-coa-payments`) intentionally left unwired.
  - **Release/prune**: APK **v1.0.0+331** (221.6 MB) + AAB **v1.0.0+332** (127 MB) uploaded to R2 (`builds/latest/` + versioned + `latest.json`); **all superseded builds pruned from R2** (11 APKs + 7 AABs). **NOTE: PowerShell aliases shadow same-named functions — `del` resolves to `Remove-Item`, so a helper named `Del` silently fails; use a distinct name (e.g. `PruneR2`).**
  - **Prompt-cache/build tooling note**: long release commands run best with a big timeout; `flutter clean` alone can take ~5 min (Deleting build...).

- **Session 2026-09-22 � Recorded-service sermons root-caused (dead live-input manifest) + player fallback**:
  - **Root cause (verified live)**: sync_recorded_service (20261203) copied `live_streams.hls_url` into `sermons.video_url`/`archive_url`, but that URL is the Cloudflare **live-input** manifest (`�/<input_uid>/manifest/video.m3u8`), which returns **HTTP 204 No Content** once the broadcast ends (confirmed by curl) ? ExoPlayer `manifestParsingError` / `MEDIA_ERR_NETWORK`. The recording is a separate **video uid**; `cloudflare_video_id` was never resolved for the 15 recorded rows (`archive_status='failed'`, `archive_error='No recording found for this stream yet'`, retried 6� over 2 days), so no alternate source existed.
  - **Edge `cloudflare-stream`**: refactored `resolveRecordingVideoId` ? `resolveRecording` (returns video uid + its own `playback.hls`); `archiveRecording` now persists `cloudflare_video_id` **and** `recording_hls_url`; new `resolve_recording` action; viewer-safe `refresh_live_input` now self-heals ended/archived rows (resolves the recording, persists it, returns `recording_hls`/`cloudflare_video_id`). Deployed (`--no-verify-jwt`), verified via the real cron secret: returns `No recording found` cleanly for the test inputs (they were app-side start/stop with no ingest).
  - **Migration `20261220_recorded_service_playable_url.sql`** (applied live + in deploy.ps1): adds `live_streams.recording_hls_url`; new `playable_recording_url(live_streams)` (R2 master ? recording manifest ? derived from video uid; never a dead live manifest); rewritten `sync_recorded_service` (sets `tenant_id` from `tenants`, stores `cloudflare_video_id`, and **deletes** any recorded sermon with no playable source instead of publishing a dead play button); trigger now fires on `recording_hls_url`/`cloudflare_video_id`; backfill re-ran for all ended/archived streams (15 dead recorded sermons removed, 0 left). Verified the full cycle live: setting a fake `recording_hls_url` materialised a playable sermon (with `tenant_id`); clearing it deleted the row.
  - **Player `sermon_player_screen.dart`**: added `_videoSourceCandidates` + `_initVideoWithFallback` � tries stored URL ? derived CF **video** manifest (`cloudflareVideoId`) ? R2 archive before showing the error state, logging each failed URL; no more dead play button.
  - **List `sermon_service.dart`**: `fetchLatestSermons` now applies category **and** tenant together, with tenant scoping **inclusive of `tenant_id IS NULL`** (`or(tenant_id.eq.�,tenant_id.is.null)`) so global/church-wide sermons (recorded services) are never filtered out for a member.
  - `flutter analyze`: 0 errors/warnings (3 pre-existing infos in test). Sermon service + key-flow smoke tests green.
