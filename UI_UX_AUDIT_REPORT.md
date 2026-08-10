# Church On App — UI/UX Audit

**Date:** 2026-08-05
**Scope:** Flutter presentation layers — `lib/features/*/presentation/`, `lib/core/theme/`, `lib/core/widgets/`, `lib/features/navigation/presentation/`.
**Method:** Static code inspection of theme, navigation shell, home, auth, profile, transport, finance, marketplace, support, admin and games screens. Pattern searches for hardcoded colors, sub-12px font sizes, raw error strings, navigation API usage, and empty-state adoption. **No device/emulator run, no `flutter analyze`, no screenshot review.** This report complements (does not replace) `AUDIT_REPORT.md`.

---

## TL;DR — 3 high-impact issues, 6 systemic problems

| # | Severity | Area | Issue |
|---|----------|------|-------|
| 1 | 🔴 High | Accessibility | **300+ occurrences of 8–11 px text** (labels, badges, disclaimers, nav bar) — below the 12sp legibility floor; Google Play accessibility reviewers flag this. |
| 2 | 🔴 High | Theming / dark mode | **300+ hardcoded `Colors.*` literals** bypass `ColorScheme` and `Tenant` theming — dark mode is broken on many screens (login inputs, support hub, verification tiles) and church-branded colors are ignored. |
| 3 | 🟠 High | Navigation | **300+ `Navigator.push/pop` calls vs `go_router`** — deep-link redirects (e.g., quiz/subscription gating) can be bypassed; no standard transition/analytics; route incoherence. |
| 4 | 🟠 Medium | Error UX | **129 raw `"Error: $e"` user-facing strings** — exposes internal exceptions, no retry affordance, no friendly copy. |
| 5 | 🟠 Medium | Theme spec | **Missing global `inputDecorationTheme`, `snackBarTheme`, `dialogTheme`, `bottomSheetTheme`, `filledButtonTheme`, `chipTheme`, `switchTheme`** — every screen hand-rolls its own variant, so inputs, snackbars, dialogs, chips and buttons look different everywhere. |
| 6 | 🟠 Medium | State handling | Loading/empty/error states are inconsistent: 3 different skeleton types, mixed `Colors.amber`/`grey` progress spinners, `EmptyStateWidget` used in only ~10 of ~80 list screens. |
| 7 | 🟡 Medium | Home UX | Home stacks **18 vertical sections** (ticker → live indicator → streak → carpso → quick start → carousel → verse → reminder → hero → admin → quick actions → promo → ad → sparkle → sermon → events → news) with a 9 px disclaimer — exhausting scroll, no jump-nav, ad mixed with content. |
| 8 | 🟡 Low | Accessibility | `GestureDetector`-only tap targets (home top bar, profile items) under 48×48 dp; labels may shrink further under system font scaling — no `textScaler` clamping. |
| 9 | 🟡 Low | Typography | 30+ runtime Google Fonts registered per-tenant — font flashes/falls back when offline; prefer bundling 2–3 families. |

---

## 1. Accessibility: sub-12 px type

### 1.1 Scale of the problem 🔴
Regex over `lib/` for `fontSize: 8..11` returned **300+ matches** across ~70 files. Highest offenders and examples:

| File | Font size | Content |
|------|-----------|---------|
| `profile_screen.dart` | 8 px | "SPIRITUAL GROWTH INDEX", "ON DUTY / OFF DUTY", stats labels |
| `profile_screen.dart` | 9 px | wallet section header labels |
| `home_screen.dart` | 9 px | news disclaimer |
| `membership_card_screen.dart` | 8 px | "MEMBER SINCE", "VERIFIED" badges |
| `marketplace_screen.dart` | 8 px | "VERIFIED" vendor badge, 9 px price labels |
| `giving_screen.dart` | 9 px | "ZMW BALANCE", "REWARDS CC" |
| `my_pledges_screen.dart` | 9 px | stat labels |
| `game_engines.dart` | 8 px | "(In-app activity points, no cash value)" |
| `my_jobs_screen.dart` | 8 px | "PROMOTED" badge |
| `main_navigation_shell.dart` | 10 px | bottom nav labels |
| `sermon_library_screen.dart` | 8 px | "NEW" badge |
| `home_hero_card.dart` | 8 px | "LIVE" badge |
| `ticket_detail_screen.dart` | 8–9 px | ticket PDF + on-screen ticket ID |
| `map_screen.dart` | 8 px | map type labels |

**Impact:**
- Users over 40, users on low-brightness displays, and users with vision impairment cannot read 8–9 px reliably.
- Google Play's "Accessibility" pre-launch report flags text below 12 sp.
- The bottom-nav labels at 10 px sit directly under a 48–80 px touch target with no enlargement on tap.

**Fix direction:**
- Introduce theme constants: `labelSmall ≥ 11`, `labelTiny ≥ 10`, and ban < 10 in code review.
- Replace badges with `ThemeData.chipTheme` labels (12–13 px default).
- Enforce via `analysis_options.yaml` custom lint or a PR checklist rule during the cleanup sweep.

---

## 2. Hardcoded colors bypass theme & dark mode

### 2.1 Scale of the problem 🔴
Regex `Colors.(red|orange|green|blue|amber|grey|black|white)` returned **300+ matches** (capped at 300). Combined with raw `Color(0xFF...)` literals (`0xFF0c2d48` rider onboarding, `0xFF0F172A` admin, `0xFFFFD700` live stream, `0xFFFFDA03` partner redemption), the app effectively has a second, hidden color system layered on top of `ColorScheme`.

### 2.2 Concrete breakages
- **Dark mode white cards:** `login_screen.dart` (`Colors.white` input containers), `support_hub_screen.dart` (`Colors.white` cards + `Colors.black` chips), `verification_request_screen.dart`, `writer_application_screen.dart` — all stay white under `AppTheme.getDarkTheme()`, producing bright glare blocks in a dark UI.
- **Tenant theming defeated:** rewards/coins/quiz/badges use `Colors.amber` / `Colors.orange` / `Colors.greenAccent` regardless of church `primaryColor`. A church that themes the app navy/blue still sees sunflower-amber rewards everywhere.
- **Status colors duplicated:** every screen re-implements its own status-color switch (`ride_history_screen`, `vendor_dashboard_screen`, `my_applications_screen`, `tithe_card_screen`, `support_hub_screen`, `writer_application_screen`) with literal colors instead of a shared `StatusColor` helper.
- **Snackbars:** 129+ `SnackBar(backgroundColor: Colors.red/green/amber)` — should be `colorScheme.error` / `tertiary`.

### 2.3 Fix direction
1. Extend `AppTheme` with semantic aliases: `error`, `success`, `warning`, `info` derived from `colorScheme` so dark mode and tenant re-theming work automatically.
2. Create `StatusBadge` / `StatusColorResolver` shared widget used by all status lists.
3. Migration sweep: `Colors.red` → `colorScheme.error`, `Colors.green` → `scheme.success`, `Colors.amber` → `scheme.tertiary`, `Colors.white` → `scheme.surface`.
4. Add `snackBarTheme` with `backgroundColor: colorScheme.inverseSurface` and let call sites pass a `status: success|error|warning` parameter.

---

## 3. Navigation: `Navigator.push` vs `go_router`

### 3.1 Scale
Regex `Navigator.(push|pop)\()` returned **300+ matches** (capped), while the app is router-driven (`go_router` in `main.dart`, deep links in `main.dart`, redirect guards in `app_router.dart`). Screen pushes are split roughly:
- Router (`context.push/go`): auth flow, notifications handlers, a few deep-linkable screens.
- `Navigator.push(MaterialPageRoute(...))`: home quick actions, profile premium items, marketplace, events, sermons, support, admin hubs, transport.

### 3.2 Impact
1. **Guard bypass:** `app_router.dart` gates `/quiz/*` behind subscription checks. Any screen that pushes `BibleQuizHubScreen` via `Navigator.push` (e.g., `home_quick_actions.dart`, `game_hub_screen.dart`) **bypasses the redirect guard**.
2. **Loss of route observability:** no consistent `NavigatorObserver` for analytics/session guard; `sessionGuardService` only tracks activity, not screen transitions.
3. **Transition inconsistency:** default platform transition (Android fade-up) vs router transitions produce a non-uniform feel.
4. **Deep-link dead ends:** screens only reachable via `Navigator.push` cannot be opened from a notification or web link without code changes (`news_list_screen.dart` implements a manual `canPop ? pop : go('/')` workaround — evidence of the friction).

### 3.3 Fix direction
- Migrate all `Navigator.push(MaterialPageRoute(...))` to `context.push('/route')`; migrate `Navigator.pop` to `context.pop()` (go_router 14+).
- Register every reachable screen in `app_router.dart` (already 1,000+ lines) or, temporarily, at minimum everything reachable from Home Quick Actions, Profile, Marketplace, Events, Sermons, Support.
- Add a `NavigatorObserver` that reports screen names to `sessionGuard` / analytics.

---

## 4. Error UX: 129 raw `"Error: $e"` strings

### 4.1 Scale
Regex `Text("Error: $e")` / `SnackBar(content: Text("Error: $e"))` / `Scaffold(body: Center(child: Text('Error: $e')))` returned **129 matches** across ~60 files (transport, profile, support, marketplace, games, admin, bible, finance).

### 4.2 Impact
- End users see `SupabaseException`, HTTP status codes, `SocketException` text, and stack fragments.
- No retry button, no back affordance, no "what happened / how to proceed" copy.
- Pattern is copy-pasted per screen — a future friendly-error design would require touching 60 files.

### 4.3 Fix direction
- Create `ErrorStateView` (icon + friendly title + detail collapsed + Retry callback + "Contact Support" button) in `lib/core/widgets/`.
- Replace the 129 call sites with a single `AppErrorView` or `snackBarError(e, context, retry: ...)` helper that maps known exception types to friendly text and logs the raw error to Crashlytics.
- Promote `EmptyStateWidget` adoption (currently only ~10 uses) with an error variant.

---

## 5. Theme spec gaps

`app_theme.dart` defines `colorScheme`, `textTheme`, `appBarTheme`, `elevatedButtonTheme`, `cardTheme` — but **no**:
- `inputDecorationTheme`
- `snackBarTheme`
- `dialogTheme`
- `bottomSheetTheme`
- `filledButtonTheme` / `outlinedButtonTheme` / `textButtonTheme`
- `chipTheme`
- `switchTheme` / `checkboxTheme` / `radioTheme`
- `tabBarTheme` / `dividerTheme`
- `progressIndicatorTheme`
- `floatingActionButtonTheme`
- `iconTheme`

**Consequence:** every screen hand-rolls these. Concrete mismatches:
- **Inputs:** login uses `InputBorder.none` in a white container; support hub uses `OutlineInputBorder` with `BorderSide.none`; rider onboarding uses `OutlineInputBorder(borderRadius: 15, borderSide: BorderSide.none)`; verification request uses `OutlineInputBorder(radius 20)` — 4 different input styles.
- **Buttons:** elevated buttons get `backgroundColor: primary, foregroundColor: secondary` in the theme, but per-screen overrides use `colorScheme.onPrimary` (home welcome dialog), `Colors.white` foreground (rider onboarding, driver earnings), or `Colors.black` (support hub, rewards) — foreground hue depends on which screen you're on.
- **Dialogs:** welcome dialog radius 24, logout radius varies, filter dialogs radius 20 — no single dialog theme.

---

## 6. State handling inconsistency

- **Loading:** `CircularProgressIndicator(color: Colors.amber)`, `CircularProgressIndicator(color: theme.primaryColor)`, `Shimmer.fromColors(baseColor: Colors.grey.shade300)`, `ListSkeleton`, custom `_CoaShimmerPlaceholder` — at least 5 visual languages.
- **Empty:** mostly bare `Text("No X found")` or nothing; `EmptyStateWidget` used in only ~10 screens (fundraising list, bible study list, radio station mgmt).
- **Error:** see §4.

---

## 7. Home screen information density

`home_screen.dart` builds a single `CustomScrollView` with ~18 stacked sections (SliverChildListDelegate):

```
AnnouncementTicker
LiveStreamIndicator
GreetingHeader
StreakPreview
CarpsoSuggestionCard
OnboardingQuickStart
RecommendationCarousel
DailyVerse
SmartReminder            (tenant == null only)
HeroCard
AdminDashboard
QuickActions
PromoCarousel
AdBanner (placement 'home')
SparklePicks grid
LatestSermon
EventTimeline
News (with 9px disclaimer)
+ 80px bottom spacer
```

Issues:
- The visible fold must compete with ads, promo carousel, and admin dashboard before reaching core actions (give, bible, events).
- No sticky section nav / jump list; no collapse-on-scroll top bar.
- `kBottomNavigationBarHeight` is added to the spacer even when nav bar auto-hides — content bottom gap doesn't animate with nav hide/show, causing a jump when the bar disappears.
- "Sparkle Picks" is below 4 other content modules; recommendation engine output competes with ads.

---

## 8. Dark mode breakages (concrete)

| Screen | Problem |
|--------|---------|
| `login_screen.dart` | `Colors.white` input containers + `Colors.black` shadows; subtitle `Colors.grey.shade600`; "G" logo gradient |
| `support_hub_screen.dart` | `Colors.white` cards, `Colors.black` selected chip |
| `verification_request_screen.dart` | `Colors.white.withValues(alpha:0.03)` tiles on `Colors.black` AppBar — screen is forced dark even in light mode |
| `security_screen.dart` | forced `Colors.black` AppBar + white38 text — same pattern |
| `rewards_screen.dart` | forced dark gradient screen even in light mode |
| `driver_portal_screen.dart` | `Colors.white` cards (unthemed) |
| `marketplace_screen.dart` | `Colors.white` price chips, 8 px "VERIFIED" |
| `home_screen.dart` welcome dialog | `Colors.amber` icons regardless of theme |

Some screens deliberately use dark chrome (identity/security/rewards) — that's a design choice, but it means **three** visual languages: theme-dark, theme-light, and forced-dark screens.

---

## 9. Navigation shell polish

- Custom nav items are `GestureDetector` + `Icon` + 10 px label: no ink ripple, no active indicator (pill/underline), no `InkWell`.
- `AnimatedContainer` `clipBehavior: Clip.hardEdge` with `decoration: const BoxDecoration()` is the previously-fixed crash guard — good, but the hidden-state transition doesn't animate the `GlobalMediaPlayer` up.
- Nav height `80 + padding.bottom` is tall vs Material's 80 total; with the mini player + nav both present, usable height shrinks notably on smaller devices.
- No `BottomNavigationBar`-style `Semantics` "page selected" announcement beyond `selected: true`.

---

## 10. Data-driven / tenant theming risk

- `_fontFactories` supports 30+ Google Fonts by tenant. On a cold offline start, `google_fonts` falls back and then swaps fonts when network returns — visual flash on home.
- Fonts are loaded from the network at runtime; a church setting a non-bundled font will see a flash of wrong font on every launch until cached.
- Recommend: bundle the top 3 fonts (Plus Jakarta Sans, Inter, Playfair) and validate the rest.

---

## 11. Prioritized remediation plan

### P0 — release-blocking accessibility & correctness
1. **Bump all 8–10 px labels to ≥ 11 px** and all body/status text to ≥ 12 px (§1). Priority files: `profile_screen.dart`, `membership_card_screen.dart`, `marketplace_screen.dart`, `giving_screen.dart`, `main_navigation_shell.dart`, `home_screen.dart` disclaimer (9 → 11).
2. **Add `snackBarTheme`, `inputDecorationTheme`, `dialogTheme`, `bottomSheetTheme`, `chipTheme`, `filledButtonTheme`** to `AppTheme` and migrate the top 15 screens (login, support hub, rider onboarding, verification request, writer application) off bespoke styling (§5).

### P1 — dark-mode and theming integrity
3. **Add semantic color aliases** (`success`, `warning`, `info`) to `ColorScheme` and replace the 300+ `Colors.*` literals (sweep order: transport, profile, support, marketplace, jobs, events, admin) using a shared `StatusColor` helper (§2).
4. **Fix dark-mode white-card screens** — login, support hub, profile auth tiles, member management (§8).
5. **Unify snackbar call sites** via a helper `showAppSnackBar(context, message, status)` (§2.3).

### P2 — information architecture
6. **Reduce home density:** move `HomeSmartReminder`, `HomeAdminDashboard`, `AdBanner` and `HomePromoCarousel` into a collapsible "More" section or behind a `FilterChip` row; add sticky section headers with jump chips (§7).
7. **Consolidate loading/empty/error** into `AppLoadingView`, `AppEmptyView`, `AppErrorView` and adopt across list screens (§4, §6).

### P3 — navigation & polish
8. **Migrate `Navigator.push/pop` → go_router** in Home Quick Actions, Profile, Marketplace, Events, Sermons, Support; add a `NavigatorObserver` (§3).
9. **Bottom nav:** replace `GestureDetector` items with `InkWell`/`Material` + active indicator pill, bump label to 11–12 px, animate mini-player when nav hides (§9).
10. **Bundle top-3 fonts** and guard runtime font swapping (§10).

---

## 12. What was NOT audited

- Live device/emulator run, screenshots, or frame profiling.
- `flutter analyze` / `flutter test` output (Flutter not invoked in this session).
- Web (Cloudflare Pages) / iOS-specific UI.
- Widget tests asserting UI behavior (test suite coverage of presentation screens is spotty).
- Dark-mode visual pass on a real device.

To extend: run the app on a low-end Android device with system font scale at 1.3x and screen brightness low; verify home scroll reachability of GIVE/BIBLE/EVENTS; screenshot login + support hub in dark mode.