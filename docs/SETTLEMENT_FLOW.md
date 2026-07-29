# Church On App — Payout, Settlement & Disbursement Flow

## Overview

Church On App uses **Lipila** (Bank of Zambia regulated) as the payment gateway for all real-money flows. A single shared Lipila merchant account serves all tenant churches. Four Supabase Edge Functions handle server-side processing: `lipila-collect`, `lipila-payout`, `lipila-webhook`, and `lipila-settle`.

---

## Flow A — Church Giving (Tithe / Offering / Missions)

```
User → App → Lipila Collect → User's MoMo → Lipila Webhook → Church MoMo
```

**Step-by-step:**

1. User selects giving type, enters amount in `giving_screen.dart`
2. User taps "PROCEED TO SECURE PAYMENT"
3. `LipilaPaymentGateway` opens — user picks Mobile Money (MTN/Airtel/Zamtel) or Card
4. Client calls `supabase.functions.invoke('lipila-collect', { action: 'initiate', ... })`
5. Edge Function persists intent to `pending_payments`, POSTs to Lipila API
6. User receives USSD PIN prompt on phone; enters PIN
7. Client polls status every 4s (up to 30 attempts / 2 min)
8. On success, client logs to `transactions` (status=pending)
9. **Meanwhile**, Lipila calls back to `lipila-webhook` — the authoritative step
10. Webhook verifies HMAC-SHA-256, calculates platform fee, sets `transactions.status = completed`
11. Webhook auto-disburses net amount to church's registered MoMo (`churches.payout_mobile`)

**What the church receives:** `amount − platformFee`

---

## Flow B — Platform Revenue & Fee Structure

| Category | Category Type | Platform Commission / Profit | Settlement & Payer Rule |
|---|---|---|---|
| **Commercial Commerce** *(Bookshops, Writers, Vendors, Marketplace, Events, Rides)* | Commercial | **10% Flat Commission** | **Seller/Driver/Host receives 90% net payout**. Buyer/Passenger pays Lipila processing fees. |
| **Church Giving** *(Tithe, Offering, Building Fund, Missions, Donations)* | Sacred / Non-Profit | **Capped Fee (Min K3.00, Max K50.00)** | **Church receives 100% of base intended gift**. Donor covers Lipila fees + capped COA fee. |

### Fee Calculation Breakdown:

1. **Commercial Transactions (Bookshops, Writers, Vendors, Events, Rides)**:
   - **Base Amount**: Set by the seller/driver/organizer.
   - **COA Profit**: 10% deducted from the base amount (`baseAmount * 0.10`).
   - **Net Payout**: 90% (`baseAmount * 0.90`) disbursed to the merchant's Mobile Money account.
   - **Lipila Gateway Fee**: Added on top to the buyer's checkout bill (`2.9% + Lipila tier fee`).

2. **Church Giving (Tithe, Offering, Building Fund, Donations)**:
   - **Base Intended Gift**: 100% reserved for the church (`netPayout = baseAmount`).
   - **COA Profit**: Calculated as `min(max(baseAmount * 0.01, K3.00), K50.00)`.
     - *K20.00 gift*: COA profit is **K3.00** (floor).
     - *K1,000.00 gift*: COA profit is **K10.00** (1%).
     - *K10,000.00 gift*: COA profit is **K50.00** (capped max).
   - **Donor Surcharge**: Donor pays `baseAmount + Lipila Processing Fee + COA Profit`.

Both client screens and server (`lipila-webhook`) log `platform_fee` on the `transactions` row and `payment_logs` audit table.

---

## Flow C — Ride / Delivery Settlement

```
Passenger pays → Lipila → Webhook (lipila-settle) → Driver MoMo (90% of fare)
```

- **Ride settlement:** `lipila-settle` validates ride completed → `netEarning = fare × 0.90` → disburses to driver's MoMo
- **Delivery settlement:** Same 90/10 split + vendor escrow release for item price
- Both set `payout_disbursed = true` (idempotent flag)

---

## Flow D — Church Coins (In-App Only)

Church Coins are an in-app reward currency earned via daily collect, quizzes, and attendance.

- **Exchange rate:** 1 ZMW = 10 Church Coins
- **Giving with coins:** `deduct_coins(user_id, amount)` RPC — coins go to the church's in-app balance
- **No real-money conversion:** Coins are NOT withdrawable; they stay within the app ecosystem
- **Coin balance:** Stored in `profiles.coins` and `profiles.balance_cc`

---

## Flow E — Admin Payout Approval

### Who Can Approve?

| Role | Can Approve? | How |
|---|---|---|
| **Superadmin** | Always | Inherent from `profile.isSuperadmin` |
| **Elevated COA Employee** | Yes | Added to `payout_approvers` by superadmin |
| **Pastor, Bishop, Admin** | No | See "Awaiting superadmin approval" |
| **Regular members** | No | See locked banner |

### Elevation Flow

```
Superadmin → Admin Hub → Payout Settlement Queue
  → "Elevate COA Employees" panel
  → Toggle switch per employee (role='employee')
  → INSERT/DELETE from payout_approvers table
```

### Payout Execution

Three admin screens handle different aspects:

1. **Payout Settlement Queue** (`withdrawal_approval_screen.dart`) — Review and approve/reject individual payout requests
2. **Global Payout Command** (`global_payout_command_screen.dart`) — Execute actual Lipila disbursements for approved requests
3. **Execute Multi-Payout** — Batch auto-approve and settle for authorized internal roles

### Multi-Payout Authorization

Auto-payout is available for roles: `superadmin`, `employee`, `pastor`, `bishop`, `usher`, `writer`, `driver`, `rider`

---

## Security Measures

| Measure | Implementation |
|---|---|
| Server-side source of truth | `pending_payments` created by Edge Function before Lipila call |
| HMAC webhook verification | SHA-256 signature + 300s timestamp freshness |
| Idempotency | `payment_logs` dedup by `webhook_id`; `payout_disbursed` boolean flags |
| Amount integrity | Webhook uses Lipila-confirmed amount, not client-supplied |
| Payout amount verification | Edge Function checks `abs(stored - requested) > 0.01` |
| Recipient verification | Uses `payout_requests.mobile_number` from DB, ignores client phone |
| Double-pay prevention | `status` set to `processing` before Lipila call |
| Rate limiting | 10 requests/min per user on all Edge Functions |
| RLS | All financial tables have Row Level Security |

---

## Flow F — Payout Mobile Enforcement & In-App Purchases (Ads & Quiz Hosting)

### 1. Mobile Money Payout Rule (No Card Payouts)
- **No Card Payouts**: Disbursements are strictly made via Mobile Money (`/v1/payouts/mobile-money` to MTN, Airtel, or Zamtel wallets).
- **Unregistered Lipila Accounts Supported**: Recipient churches, vendors, authors, or drivers do **not** need a registered Lipila merchant account. They only require a standard Mobile Money wallet on their respective MNO network (MTN/Airtel/Zamtel).
- **Resolution Order**:
  1. `tenants.payout_mobile` / `churches.payout_mobile`
  2. `tenants.treasurer_phone` / `churches.treasurer_phone`
  3. Registered admin/pastor/treasurer Mobile Money phone number from `profiles`

### 2. In-App Platform Purchases (Ads, Quiz Hosting & Host Lease)

All in-app platform services route through `LipilaPaymentGateway` using the unified fee structure:

| In-App Purchase Category | Category Key | Fee & Settlement Rule |
|---|---|---|
| **Platform Ad Campaigns** | `category: 'ad'` | 100% platform revenue. Direct collection via `LipilaPaymentGateway`. |
| **Quiz Event Hosting Fee** | `category: 'quiz_host'` | 100% platform revenue. Collected when a host creates a paid quiz event. |
| **Quiz Host Lease Subscription** | `category: 'quiz_lease'` | 100% platform revenue. Monthly lease for church quiz hosting privileges. |

---

## Key Database Tables

| Table | Purpose |
|---|---|
| `pending_payments` | Server-side payment intent (source of truth) |
| `transactions` | Completed transaction ledger |
| `payment_logs` | Audit trail for every Lipila API call |
| `wallet_transactions` | Internal ledger for coin/payout entries |
| `payout_requests` | User-initiated withdrawal requests |
| `payout_approvers` | Whitelist of employees who can approve payouts |
| `churches` | `payout_mobile` and `payout_network` per tenant |
| `coa_payments` | Direct payments to COA's own MoMo |

---

## Key Files

| File | Purpose |
|---|---|
| `lib/features/finance/presentation/lipila_payment_gateway.dart` | Unified payment gateway UI (MoMo + Card collection) |
| `lib/features/finance/presentation/giving_screen.dart` | User-facing giving flow |
| `lib/features/admin/presentation/platform_ad_screen.dart` | Platform ad campaign creation with payment gateway |
| `lib/features/modules/bible_quiz/presentation/quiz_event_host_screen.dart` | Quiz hosting & host lease creation |
| `supabase/functions/lipila-collect/index.ts` | Collection Edge Function |
| `supabase/functions/lipila-payout/index.ts` | Payout Edge Function (Strictly Mobile Money MNO) |
| `supabase/functions/lipila-webhook/index.ts` | Authoritative Webhook handler & 100% MoMo payout |
| `supabase/functions/lipila-settle/index.ts` | Ride/delivery/vendor settlement |

---

*Updated: 2026-07-24*
