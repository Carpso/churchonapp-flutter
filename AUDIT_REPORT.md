# Church On App — Project Audit

**Date:** 2026-07-27
**Scope:** `lib/`, `supabase/`, `pubspec.yaml`, env, router, services.
**Method:** Static code inspection of duplicate files, broken provider scopes, dead routes, and security posture. **No `flutter analyze` or test run was executed** (Flutter SDK not invoked in this session).

---

## TL;DR — 3 must-fix bugs, 6 structural problems

| # | Severity | Area | Issue |
|---|----------|------|-------|
| 1 | 🔴 Critical | Live streaming | `live_streaming_screen.dart` redefines `activeStreamsProvider` / `upcomingStreamsProvider` locally, shadowing the service's providers (no fallback, no RLS-respecting query). |
| 2 | 🔴 Critical | Live streaming | `LiveStreamService.sendChatMessage` and `chatMessagesStream` write/read `tenant_id` instead of `stream_id` on `stream_chat_messages` — chat is **silently broken**. |
| 3 | 🔴 Critical | Payment reliability | `LipilaPaymentNotifier._startPolling` enqueues a retry via `PaymentReliabilityService` with `amount: 0.0` and `recipientPhone: ''` after a 40 s timeout — **the queue cannot retry a payment without those fields**. |
| 4 | 🟠 High | Code dup | Two `event_service.dart` files with different models (`ChurchEvent` vs `KingdomEvent`) talking to the same `events` table. |
| 5 | 🟠 High | Code dup | Two `live_stream_screen` / `live_streaming_screen` files, neither registered in the router. |
| 6 | 🟠 High | Structure | Payment service lives under `features/give/data/` but is consumed by tithes, coins, marketplace, payouts. Cross-feature import. |
| 7 | 🟡 Medium | Security | `.env` is present in the working tree (AGENTS.md flags it as exposed; rotate keys before any production deploy). |
| 8 | 🟡 Medium | Dead code | `lib/features/finance/presentation/lipila_payment_gateway.dart` is a 1-line re-export shim — easy to break, low value. |
| 9 | 🟡 Medium | Dead code | `KingdomEvent` service (`features/modules/media/data/event_service.dart`) appears unused — no import of `kingdomEventServiceProvider` or `kingdomUpcomingEventsProvider` outside its own file. |
| 10 | 🟢 Low | R2 | `R2`/`migrate-to-r2` mixed with `coa_payments` (see section 6). |

---

## 1. Critical bugs

### 1.1 Provider shadowing in `live_streaming_screen.dart` 🔴

**File:** `lib/features/modules/live_streaming/presentation/live_streaming_screen.dart` (lines 8–18)

```dart
final activeStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final result = await client.from('live_streams').select().eq('status', 'live').order('started_at', ascending: false);
  return result;
});
```

This is a **top-level** provider defined inside a presentation file. The actual `LiveStreamService` in `lib/features/modules/live_streaming/data/live_stream_service.dart` also exports `activeStreamsProvider` and `upcomingStreamsProvider` (lines 260–268) — but those use the service which:
- joins `churches(id, name, logo_url)` for display
- has a graceful fallback to demo data when the table is empty
- logs errors

**Effect:** The `LiveStreamingScreen` widget **never uses the service**. It calls a separate top-level provider that:
- bypasses the service's `debugPrint` error handling
- has no demo fallback (empty table → empty list)
- ignores RLS column narrowing (no `churches` join)

**Fix:**
```dart
// Remove the top-level providers from live_streaming_screen.dart
// Import from the service file instead:
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
// activeStreamsProvider and upcomingStreamsProvider are already exported.
```

### 1.2 Wrong column in `LiveStreamService` chat 🔴

**File:** `lib/features/modules/live_streaming/data/live_stream_service.dart`

```dart
// Line 174-181 (sendChatMessage)
await _client.from('stream_chat_messages').insert({
  'tenant_id': streamId,        // ❌ This is the streamId being saved as tenant_id
  'user_id': _client.auth.currentUser?.id,
  'content': message,
});

// Line 184-191 (chatMessagesStream)
return _client
    .from('stream_chat_messages')
    .stream(primaryKey: ['id'])
    .eq('tenant_id', streamId)   // ❌ Filtering by tenant_id, not stream_id
    .order('created_at')
    .map((events) => List<Map<String, dynamic>>.from(events));
```

The table `stream_chat_messages` is keyed by `stream_id` and a tenant scope. By writing the `streamId` into the `tenant_id` column, every chat message is attributed to the wrong tenant and **silently fails RLS** (or leaks across tenants if RLS is loose).

**Fix:** Read the actual `stream_chat_messages` schema (likely `stream_id`, `tenant_id`, `user_id`, `content`, `created_at`), then:
```dart
.insert({
  'stream_id': streamId,
  'tenant_id': _resolveTenantForStream(streamId),  // look it up or pass it in
  'user_id':   _client.auth.currentUser?.id,
  'content':   message,
})
```

### 1.3 Broken payment retry queue 🔴

**File:** `lib/features/give/data/lipila_service.dart` (lines 342–359)

```dart
if (attempts >= maxAttempts) {
  timer.cancel();
  final reliability = PaymentReliabilityService(client);
  unawaited(reliability.queuePaymentForRetry(
    referenceId: referenceId,
    amount: 0.0,                 // ❌
    recipientPhone: '',          // ❌
    method: 'coa_payment',
    metadata: {'type': 'coa_payment_timeout', 'reference': referenceId},
  ));
  state = AsyncData(...failed: "Payment verification timed out. Your money has been deducted. Reference: $referenceId" ...);
}
```

The retry queue is given **`amount: 0.0`** and an **empty phone** — the original payment call site has both values, so they must be threaded through `_startPolling(referenceId, client, amount, phone)` and used here. As written, the retry will never be actionable.

**Fix:** Pass the values into `_startPolling` and persist them on `LipilaPaymentState` (or look up the original row in `coa_payments` by `payment_ref` to recover the amount). The recovery-by-DB approach is more robust since the user could be offline.

---

## 2. Duplicate code

### 2.1 Two `event_service.dart` files

| File | Model | Schema expectations | Used by |
|------|-------|---------------------|---------|
| `lib/features/events/data/event_service.dart` (228 lines) | `ChurchEvent` | `date`, `image_url`, `ticket_price`, `attendee_count`, `organizer_momo_*` | **App router** (`app_router.dart` line 30, 613), event details screen, event host dashboard |
| `lib/features/modules/media/data/event_service.dart` (81 lines) | `KingdomEvent` | `event_date`, `church_id`, `price` | **Nothing in the repo** (no imports found) |

The "media" version expects `event_date` and `church_id`, but the active schema and the rest of the app use `date` and `tenant_id`. They cannot be reconciled without data migration.

**Fix:** Delete `lib/features/modules/media/data/event_service.dart` and its `kingdomEventServiceProvider` / `kingdomUpcomingEventsProvider` (no consumers). If a separate read model is genuinely needed later, scope it under the `events/` feature, not `media/`.

### 2.2 Two live-stream screens, both un-routed

| File | Status |
|------|--------|
| `lib/features/home/presentation/live_stream_screen.dart` (297 lines) | Has full chat UI; takes `streamUrl` + `title` as constructor args. **No route in `app_router.dart`.** |
| `lib/features/modules/live_streaming/presentation/live_streaming_screen.dart` (143 lines) | The "browser" screen that lists active + upcoming streams. **No route in `app_router.dart` (verified up to line 1000).** |

`app_router.dart` registers `/live-studio` (the broadcasting screen) but no viewer route. Search for `/live-stream` shows no matches in the router file. **Users cannot open a stream from the app.**

**Fix:**
- Pick one: either fold the chat/player from `home/presentation/live_stream_screen.dart` into `live_streaming_screen.dart` and navigate with `context.push('/live/:id')`, or
- Make `live_streaming_screen.dart` the index and add a `/live/:id` route that constructs `LiveStreamScreen(streamUrl, title)` from a `live_streams` row.

Also fix the provider shadowing from §1.1 at the same time.

### 2.3 Lipila re-export shim

`lib/features/finance/presentation/lipila_payment_gateway.dart` (1 line):
```dart
export 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';
```

The actual file is in `give/presentation/`. The re-export was probably created when refactoring `give/` → `finance/`, but the underlying service was not moved.

**Fix:** Decide on a single home for payments:
- Move `lib/features/give/data/lipila_service.dart` → `lib/core/services/payments/lipila_service.dart`
- Move `lib/features/give/presentation/lipila_payment_gateway.dart` → `lib/core/services/payments/lipila_payment_gateway.dart` (or keep it under `features/finance/`)
- Update all imports (router, giving screen, coins, marketplace, tithes)
- Delete the re-export shim

This eliminates a cross-feature import (`features/finance/...` → `features/give/...`).

---

## 3. Security

### 3.1 `.env` in tree 🔴

`.env` exists in the working tree. AGENTS.md already flags this. **Before any production deploy, rotate every secret** (Supabase service role, Lipila, Cloudflare R2, FCM, Resend, TURN) — once a key is in a git history, the only safe action is revocation.

The standard `.gitignore` rules from AGENTS.md look correct; the issue is historical commits.

### 3.2 RLS, function search path, anon EXECUTE

These are policy items already covered by migrations (`20260838_harden_db_and_dashboard_logic.sql`, the series `20260826_*`, and the `anon` REVOKE batch). **No new code-side issue spotted from static review** beyond confirming the migrations are applied to the live project.

### 3.3 TURN credentials

`supabase/functions/turn-credentials` exists; deployment is gated on `TURN_SERVER_URL` + `TURN_SECRET`. Confirm they are set in the Supabase Edge Function environment before relying on the audio/video call features.

### 3.4 iOS universal links

`apple-app-site-association` reads `APPLE_TEAM_ID` from env. Verify this is set; otherwise the file will return without a team id and iOS will reject the association silently.

---

## 4. Dead / suspect code

| File | Reason |
|------|--------|
| `lib/features/finance/presentation/lipila_payment_gateway.dart` | 1-line re-export shim (see §2.3). |
| `lib/features/modules/media/data/event_service.dart` | No consumers; wrong schema assumptions. |
| `lib/features/home/presentation/live_stream_screen.dart` | Not routed; would crash on routes that need it. |
| `lib/features/modules/live_streaming/presentation/live_streaming_screen.dart` | Not routed. |
| `lib/features/give/data/lipila_service.dart` lines 209–241, 309–340 | The `coa_payments` DB poll runs **twice per polling tick** (once before the Edge Function call, once after, with identical logic). The second poll is reachable only if the Edge Function call returns a "pending/empty" status — but that path always succeeds in the early-return before the duplicate, so the second block is unreachable. Collapse it. |
| `lib/features/connect/data/notification_service.dart` vs `lib/core/services/notification_service.dart` | Two notification services; verify which one is canonical. |

---

## 5. Router inventory gap

`app_router.dart` is 1061 lines; routes registered include `/events/:id`, `/wallet`, `/klips/:id`, `/posts/:id`, but **no `/live/:id` or `/live-streams`**. If the live-streaming feature is meant to be reachable, that is the highest-priority missing route.

Also, the route name `/sermons` is referenced from the notifications redirect handler (line 862) but I do not see a corresponding `GoRoute(path: '/sermons', ...)` block in the file (truncated at 1061). **Verify and add it if missing.**

---

## 6. Architecture notes

- **Multi-tenant pattern is sound.** `tenant_id` is consistently applied across event, social, quiz, leaderboard, and admin queries. Seed IDs (`zm_*`, `zw_*`) and UUID production IDs co-exist; the migration `20260827_reassign_users_to_rock_of_ages.sql` and the `20260826_tenants_table.sql` series handle the split.
- **Coin economy is correctly constrained.** `add_coins` RPC, separate `coin_purchases` / `coin_redemptions` tables, and the partner-offer pattern in `coins_service.dart` are aligned with the BoZ loyalty-points (not cryptocurrency) stance.
- **`PaymentReliabilityService` exists but is underused.** It is only called once, from the broken timeout path. Its `startAutoSync` / `queuePaymentForRetry` API should be invoked from any place that touches a `coa_payments` write, including webhook handlers and the coins flow.

---

## 7. Prioritized remediation plan

### P0 (block release)
1. Fix the `stream_chat_messages` `tenant_id` vs `stream_id` bug (§1.2) — currently chat silently fails.
2. Pass `amount` + `phone` through to `PaymentReliabilityService` in the timeout branch (§1.3) — currently the queue is dead.
3. Delete the local providers in `live_streaming_screen.dart` and use the service's providers (§1.1) — currently the screen has wrong schema and no fallback.

### P1 (block release, lower risk)
4. Delete `lib/features/modules/media/data/event_service.dart` (§2.1, §4).
5. Add `/live-streams` and `/live/:id` routes to `app_router.dart` (or delete the screens) (§2.2, §5).
6. Confirm `/sermons` route exists in `app_router.dart` (it is referenced by the notifications redirect) (§5).
7. Consolidate the Lipila service: move to `core/services/payments/` and update all imports; delete the 1-line shim (§2.3).

### P2 (tech debt)
8. Collapse the duplicate `coa_payments` poll block in `lipila_service.dart` (§4).
9. Resolve the two `notification_service.dart` files (§4).
10. Rotate every secret listed in `SECRETS_BACKUP.md` if it has ever been committed (§3.1).
11. Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and fix any new warnings in `lib/` (AGENTS.md target: 0/0 in source, 0/0 in tests after the test fixes noted in `AGENTS.md`).

### P3 (operational)
12. Confirm `TURN_SERVER_URL`, `TURN_SECRET`, `APPLE_TEAM_ID` are set in Supabase Edge Function environment.
13. Confirm R2 secrets and `R2_PUBLIC_DOMAIN` are set (Cloudflare R2 is used by `migrate-to-r2` and `r2-sign`).

---

## 8. What was NOT audited

- `flutter analyze` output (Flutter not invoked in this session).
- Test pass/fail status.
- Database migrations for the 2026-08 series beyond reading the filenames.
- Edge Function runtime behavior beyond the TypeScript signatures.
- The web build (`flutter build web`) and Cloudflare Pages deployment.
- iOS build (no macOS toolchain on this host).
- Asset / image optimization.

To extend this audit: run `flutter analyze`, `flutter test`, and exercise the live-stream end-to-end against a staging Supabase project with a known `live_streams` row.