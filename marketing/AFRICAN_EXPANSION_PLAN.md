# Church On App — UI/UX Audit Report & African Expansion Plan

**Date:** August 1, 2026  
**Version:** 1.0.0+238  
**Scope:** Bottom navigation screens, country handling, expansion readiness

---

## TABLE OF CONTENTS

1. [Bottom Navigation Audit](#1-bottom-navigation-audit)
2. [UI Overlap Analysis](#2-ui-overlap-analysis)
3. [Country Handling Audit](#3-country-handling-audit)
4. [African Expansion Plan](#4-african-expansion-plan)
5. [Recommendations](#5-recommendations)

---

## 1. BOTTOM NAVIGATION AUDIT

### Navigation Bar Design
- **5 tabs:** Home, Sermons, Give, Connect, Profile
- **Icons:** LucideIcons (home, headphones, hand, users, user)
- **Active state:** Primary color icon + text, bold weight
- **Hide-on-scroll:** YES — bar animates to 0px on scroll down, returns on scroll up
- **Back button:** PopScope — double-tap to exit on Home, single tap to return to Home from other tabs

### Tab-by-Tab Findings

#### HOME TAB
**Layout:** CustomScrollView with 18+ sections (ticker → live indicator → greeting → streak → carpso → onboarding → recommendations → verse → smart reminder → hero card → admin tools → quick actions → promo → ad → sparkle grid → sermon → events → news)

**Critical Issues:**
- Hardcoded event data in `home_event_timeline.dart` (lines 20-21) — fake events never change
- Broken share functionality in `home_daily_verse.dart` (lines 52-54) — shows "copied" but doesn't copy
- "VIEW ALL" text in event timeline is not tappable (line 17)
- Coin balance in greeting header looks interactive but has no onTap handler
- Weather error shows fake "28°C Clear" data (lines 203-217)
- 18+ scrollable sections with no content prioritization
- Inconsistent section title widgets — 5+ local reimplementations instead of using `HomeSectionTitle`

**Color Issues:**
- Sermon library uses hardcoded `Color(0xFFFFFAEB)` instead of theme
- News list uses hardcoded `Colors.white` background
- Sparkle grid uses hardcoded `Colors.white`

#### GIVE TAB
**Layout:** SingleChildScrollView with balance card → feature tiles → amount input → payment methods → proceed button

**Critical Issues:**
- Payment methods "Church Wallet" and "Credit/Debit Card" are non-functional dead UI (lines 329-335)
- Fee calculation duplicated in inline closure (lines 301-309)
- Buy Coins screen uses completely different dark theme (`Color(0xFF0F172A)`) — jarring transition from warm cream
- Tithe history `LinearProgressIndicator` always at 1.0 — misleading
- Tithe history error state uses raw `Text("Error: $err")` instead of `ErrorRetryWidget`
- Wallet card is copy-pasted 3 times across giving, wallet, and giving_widget screens

**Color Issues:**
- Buy Coins: `Color(0xFF0F172A)` dark background — only finance screen with dark theme
- All others: `Color(0xFFFFFAEB)` warm cream

#### SERMONS TAB
**Layout:** AppBar + category filter + ListView.builder with pagination

**Critical Issues:**
- Category filter doesn't actually filter — `_selectedCategory` updated but never used in query (lines 25-29, 218-238)
- Empty state uses `ListView.builder` with switch statement — overly complex
- Preacher avatar reuses sermon thumbnail image (line 309)
- No loading feedback on "Load More" error

**Color Issues:**
- Uses `Color(0xFFFFFAEB)` hardcoded background
- Live banner uses red gradient not from theme

#### CONNECT TAB
**Layout:** TabBarView with 4 tabs (KLIPS, COMMUNITIES, CHURCH SOCIAL, GAMES)

**Critical Issues:**
- Chat messenger screen looks like WhatsApp — uses `Color(0xFF075E54)` green (38 locations)
- Video call button actually starts audio call (lines 329-337) — functional bug
- "Report", "Block", "Clear Chat" are stub functions (show SnackBar only)
- FAB visible on ALL tabs including KLIPS and GAMES — irrelevant on non-social tabs
- Create post screen uses `Colors.white` background while parent uses `Color(0xFFFFFAEB)`
- Location pin toolbar button is dead UI ("coming soon" snackbar)

**Color Issues:**
- Chat: WhatsApp green `Color(0xFF075E54)` — completely different from brand
- Create Post: `Colors.white` — breaks warm cream pattern

#### PROFILE TAB
**Layout:** CustomScrollView with SliverAppBar → wallet card → faith dashboard → ministry actions → account list → asset grid

**Critical Issues:**
- Background hardcoded `Color(0xFF0F0F0F)` — dark theme, IGNORES app theme entirely
- Account Settings screen shows edit icons on READ-ONLY fields — deeply misleading
- Account Settings displays raw UUID instead of user-friendly code
- "REDEEM" action appears TWICE in wallet (lines 334 and 361)
- Privacy mode toggle doesn't persist to database — local dialog state only
- Camera Settings and Emergency Contacts screens are orphaned (no navigation path)
- Verification request uses Material icons instead of Lucide — inconsistent
- PDF certificates hardcode "Believer" instead of actual user name

**Color Issues:**
- Profile: `Color(0xFF0F0F0F)` dark — jarring from warm cream in other tabs
- Account Settings: `Color(0xFFFFFAEB)` light — jarring from profile's dark
- Security: `Color(0xFF0F0F0F)` dark — matches profile
- Camera Settings: `Color(0xFFFFFAEB)` light — mismatch
- Emergency Contacts: `Color(0xFFFFFAEB)` light — mismatch

---

## 2. UI OVERLAP ANALYSIS

### 2.1 Duplicated Components Across Tabs

| Component | Occurrences | Files | Recommendation |
|-----------|-------------|-------|----------------|
| **Balance/Summary Card** | 3 identical | giving_screen:165-212, wallet_screen:133-173, giving_widget:133-222 | Extract `StewardshipBalanceCard` |
| **Filter Pill Row** | 4 variations | giving_category_selector, sermon_library:207-242, connect_screen:293-316, create_social_post:238-271 | Extract `FilterPillRow` |
| **Transaction List Item** | 2 identical | tithe_history:121-157, wallet_screen:347-388 | Extract `TransactionListItem` |
| **Section Title (accent bar)** | 5+ local copies | home_quick_actions:121, home_latest_sermon:85, home_event_timeline:55, home_admin_dashboard:58, news_list:95 | Use existing `HomeSectionTitle` |
| **Empty State** | 6 variations | tithe_history:69, wallet:300, connect:238, sermon_library:111, devotions:91, bible:158 | Extract `EmptyStateView` |
| **Error State** | 3 patterns | ErrorRetryWidget (giving, wallet), raw text (tithe_history, buy_coins), custom (bible, devotions) | Standardize on `ErrorRetryWidget` |
| **Loading State** | 4 patterns | Shimmer (giving), CircularProgressIndicator (tithe_history), ListSkeleton (wallet), raw spinner (buy_coins) | Standardize per screen type |

### 2.2 Duplicated Country Detection Logic

| File | Lines | Pattern |
|------|-------|---------|
| `select_church_screen.dart` | 72-76 | Bounding box: `lat < -17.5 && lng > 25.0` = Zimbabwe |
| `church_onboarding_screen.dart` | 61-65 | Identical bounding box |
| `register_church_screen.dart` | 37-48 | Uses geocoding (different, better) |

### 2.3 Duplicated Avatar Upload Logic

| File | Lines | Pattern |
|------|-------|---------|
| `profile_screen.dart` | 850-879 | Image picker → R2 upload |
| `account_settings_screen.dart` | 21-56 | Image picker → R2 upload |

### 2.4 Mixed Navigation Patterns

| Pattern | Screens Using It | Issue |
|---------|-----------------|-------|
| `Navigator.push(MaterialPageRoute(...))` | Profile, Give, Sermons, Connect | Standard but no deep link support |
| `context.push('/route')` (GoRouter) | Home sub-screens, Smart Reminder | Deep link compatible |
| `showModalBottomSheet` | Bible, Profile security | Inconsistent with push navigation |
| Mixed in same screen | Giving (line 76 vs 240) | Confusing back navigation |

---

## 3. COUNTRY HANDLING AUDIT

### 3.1 Current State

**Active Countries:** Zambia, Zimbabwe  
**Supported (Coming Soon):** Kenya, Nigeria, Ghana, South Africa, Tanzania, Uganda, Rwanda, Malawi, Mozambique, Angola, Botswana, Namibia, DR Congo, Ethiopia, Cameroon, Ivory Coast, Senegal, Mali, Burundi, South Sudan, Eswatini, Lesotho, Madagascar (25 total)

**Country Detection:**
- GPS bounding box: crude heuristic, misclassifies border regions
- Manual dropdown in church selection screen
- Church registration hard-falls back to Zambia if not ZW/ZM

### 3.2 Zambia-Specific Code (Would Break for Other Countries)

| Category | What's Hardcoded | Files |
|----------|-----------------|-------|
| **Payment Gateway** | Lipila (Zambian processor) | lipila_payment_gateway.dart, checkout_screen.dart, coa_missions_donate_screen.dart |
| **Mobile Networks** | MTN/Airtel/Zamtel with +260 prefixes | momo_phone_input_widget.dart (enum ZambianNetwork), checkout_screen.dart |
| **Phone Validation** | `validateZambianPhone()` rejects non-ZM numbers | momo_phone_input_widget.dart:72 |
| **Currency** | "K " symbol in 12+ dashboards | bookshop_dashboard, bishop_dashboard, driver_dashboard, etc. |
| **Tax/Payroll** | NHIMA, NAPSA, PAYE with ZM rates | zambian_payroll_screen.dart |
| **Turnover Tax** | 3% Zambian rate | turnover_tax_ledger_screen.dart |
| **Regulatory Text** | "Regulated by Bank of Zambia" | receipt_screen, lipila_payment_gateway, coa_missions_donate |
| **Phone Numbers** | +260 numbers in 8+ screens | emergency_contacts, about, privacy, terms, landing_screen |
| **Radio Stations** | All Zambian fallback stations | radio_service.dart:46-57 |
| **Onboarding Copy** | "Zambia's leading church management suite" | register_church_screen:237 |

### 3.3 Zimbabwe Status

| Feature | Status |
|---------|--------|
| Country in dropdown | Listed but shows "Coming Soon" |
| Map tiles | Configured (`MAPS_ZIMBABWE_URL`) but never loaded |
| Payment gateway | NOT IMPLEMENTED (no EcoCash) |
| Currency | NOT IMPLEMENTED (no ZWL in AppCurrency enum) |
| Phone validation | NOT IMPLEMENTED (no +263 support) |
| Tax/compliance | NOT IMPLEMENTED (no NSSA/ZIMRA) |
| Seed churches | Exist in tenant_service.dart (zw_1 through zw_12) |

---

## 4. AFRICAN EXPANSION PLAN

### Phase 1: Zimbabwe (Immediate — Q3 2026)

**Payment Integration: EcoCash (Econet)**
- Register as EcoCash Merchant via Econet Business Portal
- Integrate EcoCash API (REST, merchant-initiated push payments)
- Create `ecocash-collect` Edge Function (parallel to `lipila-collect`)
- Add `EcoCashNetwork` enum: `ecocash` (077/078/073 prefixes)
- Create `validateZimbabweanPhone()` function
- Add ZWL currency to `AppCurrency` enum
- Create `ZimbabweanPayrollScreen` with NSSA, ZIMRA PAYE, Aids Levy

**Technical Changes:**
- Make `_activeCountries` database-driven (add `countries` table with `is_active` flag)
- Switch PMTiles URL based on selected country in `church_map.dart`
- Add `NumberFormat.currency(symbol: 'Z$ ', locale: 'en_ZW')` for ZWL
- Update `MomoPhoneInputWidget` to support Zimbabwean networks
- Add country-aware regulatory text ("Reserve Bank of Zimbabwe")

**Estimated Effort:** 3-4 weeks

### Phase 2: East Africa — Kenya & Tanzania (Q4 2026)

**Kenya — M-Pesa Integration:**
- Register as Safaricom Lipia Na M-Pesa merchant
- Integrate M-Pesa Daraja API (STK Push for customer payments, B2C for payouts)
- Create `mpesa-collect` Edge Function
- Currency: KES (`KSh `)
- Networks: Safaricom (0700-0729, 0110-0111), Airtel (0730-0739)
- Tax: KRA PAYE, NHIF, NSSF

**Tanzania — M-Pesa + Tigo Pesa:**
- Vodacom M-Pesa API integration
- Tigo Pesa API integration
- Currency: TZS (`TSh `)
- Networks: Vodacom (0750-0759), Airtel (0780-0789), Tigo (0650-0659)
- Tax: TRA PAYE, NHIF, Workers Compensation

**Technical Changes per Country:**
1. Add `AppCurrency` variants (KES, TZS)
2. Create country-specific phone validation
3. Create country-specific Edge Functions for payment gateways
4. Add country-specific tax calculation screens
5. Localize phone number display (+254 for KE, +255 for TZ)
6. Add country-specific radio station fallbacks
7. Host country-specific PMTiles at `maps.churchonapp.com/{country}.pmtiles`

**Estimated Effort:** 4-6 weeks per country

### Phase 3: West Africa — Nigeria & Ghana (Q1 2027)

**Nigeria — Paystack/Flutterwave:**
- Register as Paystack/Flutterwave merchant
- Integrate Paystack Inline SDK (card, bank transfer, USSD)
- Currency: NGN (`₦`)
- Networks: MTN (0803, 0806, 0816), Airtel (0802, 0808, 0812), Glo (0805, 0807, 0815), 9mobile (0809, 0817)
- Tax: FIRS PAYE, Pension (CPS), NHIS

**Ghana — MTN MoMo Ghana:**
- Register as MTN MoMo Ghana merchant
- Integrate MTN MoMo API (collect + disburse)
- Currency: GHS (`GH₵`)
- Networks: MTN (024, 054, 055, 059), Vodafone (020, 050), AirtelTigo (026, 027, 056)
- Tax: GRA PAYE, SSNIT, GETLED

**Estimated Effort:** 4-6 weeks per country

### Phase 4: Francophone Africa (Q2 2027)

**Ivory Coast, Senegal, Cameroon, Mali:**
- Orange Money API integration (primary mobile money in Francophone Africa)
- Currency: XOF/XAF (CFA Franc — shared across 8 countries)
- Networks: Orange (all Francophone countries)
- **Language:** French localization required (add `GlobalAppState.languageCode` support)
- Tax: Country-specific PAYE rates

**Estimated Effort:** 6-8 weeks (includes French localization)

### Phase 5: Southern Africa — South Africa, Botswana, Namibia (Q3 2027)

**South Africa — PayFast/Yoco:**
- PayFast for card payments (most common)
- Yoco for POS integration
- Currency: ZAR (`R `)
- Networks: Vodacom, MTN, Cell C, Telkom Mobile
- Tax: SARS PAYE, UIF, SDL

**Botswana — Orange Money Botswana:**
- Currency: BWP (`P `)
- Networks: Mascom, Orange, BTC Mobile

**Namibia — MTC MoMo:**
- Currency: NAD (`N$ `)
- Networks: MTC, Telecom

**Estimated Effort:** 4-6 weeks per country

---

## 5. RECOMMENDATIONS

### Priority 1: Fix Critical UX Bugs (Immediate)

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 1 | Video call button starts audio call | Functional bug | 5 min |
| 2 | Sermon category filter doesn't filter | Feature broken | 15 min |
| 3 | Daily verse share doesn't copy | Feature broken | 10 min |
| 4 | Account Settings shows edit icons on read-only fields | Misleading UX | 30 min |
| 5 | Account Settings shows raw UUID | Security/UX | 10 min |
| 6 | Duplicate REDEEM button in profile wallet | Confusing UX | 5 min |
| 7 | Privacy mode toggle doesn't persist | Feature broken | 30 min |
| 8 | Tithe history LinearProgressIndicator always 100% | Misleading UX | 5 min |

### Priority 2: Extract Shared Components (1-2 weeks)

| # | Component | Consolidates | Impact |
|---|-----------|-------------|--------|
| 1 | `StewardshipBalanceCard` | 3 duplicate implementations | DRY |
| 2 | `FilterPillRow` | 4 variations | Consistent UX |
| 3 | `TransactionListItem` | 2 duplicate implementations | DRY |
| 4 | `EmptyStateView` | 6 variations | Consistent UX |
| 5 | `StandardErrorView` | 3 patterns → 1 | Consistent UX |
| 6 | `SectionTitle` (use existing HomeSectionTitle) | 5 local copies | DRY |

### Priority 3: Theme Consistency (1 week)

| # | Action | Files Affected |
|---|--------|---------------|
| 1 | Replace all hardcoded `Color(0xFFFFFAEB)` with `Theme.of(context).scaffoldBackgroundColor` | 100+ locations |
| 2 | Replace all hardcoded `Colors.white` backgrounds with themed surface color | 20+ locations |
| 3 | Decide: Profile tab dark theme or light theme? Unify all sub-screens. | 8 profile screens |
| 4 | Remove WhatsApp green from chat — use brand colors | 38 locations |
| 5 | Remove Buy Coins dark theme or make it optional | 1 screen |
| 6 | Standardize border radius (pick 16, 20, or 24) | All screens |
| 7 | Standardize padding (pick 16 or 20) | All screens |

### Priority 4: Navigation Consistency (1 week)

| # | Action | Impact |
|---|--------|--------|
| 1 | Convert all `Navigator.push(MaterialPageRoute)` to GoRouter `context.push` | Deep link support |
| 2 | Remove orphaned screens or add navigation paths | Discoverability |
| 3 | Add pull-to-refresh to profile screen | Expected UX |
| 4 | Standardize error states to use `ErrorRetryWidget` | Consistent UX |

### Priority 5: Country Architecture (2-3 weeks)

| # | Action | Impact |
|---|--------|--------|
| 1 | Make `_activeCountries` database-driven | Runtime configurability |
| 2 | Extract country detection into shared utility | DRY |
| 3 | Make currency formatting country-aware | Multi-country ready |
| 4 | Make phone validation country-aware | Multi-country ready |
| 5 | Make payment gateway country-aware | Multi-country ready |
| 6 | Make tax calculation country-aware | Multi-country ready |
| 7 | Add country-specific regulatory text | Compliance |
| 8 | Host country-specific PMTiles | Maps |

---

## APPENDIX: FILE-BY-FILE ISSUE COUNT

| Screen | Critical | High | Medium | Low | Total |
|--------|----------|------|--------|-----|-------|
| select_church_screen | 3 | 4 | 6 | 5 | 18 |
| home_screen + widgets | 5 | 6 | 8 | 4 | 23 |
| giving_screen | 2 | 3 | 4 | 2 | 11 |
| sermon_library_screen | 2 | 2 | 3 | 2 | 9 |
| connect_screen | 3 | 4 | 5 | 3 | 15 |
| profile_screen | 5 | 6 | 8 | 4 | 23 |
| account_settings_screen | 3 | 2 | 1 | 1 | 7 |
| chat_messenger_screen | 3 | 3 | 2 | 1 | 9 |
| bible_screen | 2 | 3 | 4 | 2 | 11 |
| **TOTAL** | **28** | **33** | **41** | **24** | **126** |
