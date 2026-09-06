# Church On App — Payment System (Lipila Mobile Money)

**Status: FIXED — 2026-09-06. Read this before touching anything payment-related.**

This is the authoritative reference for how money moves through Church On App:
collection (giver → platform), confirmation, settlement (platform → church
treasury / tithe recipient), and payouts.

---

## 1. The model in one picture

```
 Giver's phone                    Church On App platform              Church / leader
 (MTN/Airtel/Zamtel)              (Lipila merchant wallet)            (final recipient)
        │                                    │                                │
        │ 1. lipila-collect "initiate"       │                                │
        │    (pre-creates pending row)       │                                │
        ├───────────────────────────────────►│                                │
        │                                    │                                │
        │ 2. Giver approves PIN on handset   │                                │
        │                                    │                                │
        │ 3. Lipila confirms ────────────────┤                                │
        │      ├─ webhook  (lipila-webhook)  │                                │
        │      └─ or status poll             │                                │
        │         (lipila-collect "status")  │                                │
        │                                    │                                │
        │                       4. coa_payments → settled                     │
        │                       5. settleReference()                          │
        │                       6. resolve recipient (server-side chain)      │
        │                       7. disburse() ───────────────────────────────►│
        │                          (payout_tasks → Lipila /payouts)           │
        │                                                                     │
        └─ 8. Church auto-payout: aggregate balance ≥ threshold → one payout
```

**Platform-first model:** money is always collected to the COA merchant wallet
first, then disbursed to the church/leader. The client NEVER moves money
directly and never decides who gets paid.

---

## 2. Edge Functions

| Function | Role |
|---|---|
| `lipila-collect` | `initiate` (creates collection + pre-creates a pending `coa_payments` row) and `status` (polls Lipila, and on a Lipila-verified success writes `settled` + runs settlement) |
| `lipila-webhook` | Receives Lipila delivery → marks `coa_payments` settled → runs settlement → enqueues church auto-payouts |
| `lipila-settle` | Cron retry: settles any `payout_tasks` still `pending` whose anchor is ready |
| `lipila-payout` | Manual/anchored payout path (requires a confirmed `coa_payments` anchor) |
| `_shared/settlement.ts` | The single settlement engine shared by webhook + cron. **All money-out decisions live here.** |

---

## 3. Collection (`lipila-collect`)

`POST /v1/collections/mobile-money` with:
`{ referenceId, amount (Kwacha), accountNumber (giver's 260…), currency: "ZMW", narration }`
headers: `x-api-key`, `callbackUrl`.

Base URL: `lsk_` keys → `https://blz.lipila.io/api` (production), otherwise
`https://api.lipila.dev/api`.

**Before** calling Lipila, the function pre-creates a `coa_payments` row with
`status: 'pending'`, `payment_ref = referenceId`, `user_id`, and metadata
(`tenant_id`, `user_id`, `category`, …). This is essential:

- the client poller finds the row immediately, and
- tenant/branch metadata survives to settlement even if the webhook payload is
  thin.

The `status` action (used by the client poller) tries, in order:
1. `/v1/collections/check-status?referenceId=<ref>` (chisomo/kingdom contract)
2. `/v1/collections/mobile-money/status/<ref>`
3. `/v1/collections/mobile-money/<ref>`

When Lipila itself reports the collection settled, the status action **writes
`settled` into `coa_payments` and runs settlement**. This is deliberate
belt-and-suspenders: a lost webhook can no longer strand a church payout.

---

## 4. Webhook authentication — DUAL SCHEME (do not "simplify" this)

`lipila-webhook` accepts **either**:

1. **`?secret=<LIPILA_WEBHOOK_SECRET>`** on the callback URL — the callback we
   send to Lipila carries this query string. (Verified production pattern from
   the chisomo/kingdom projects.)
2. **Standard Webhooks HMAC headers** — `webhook-id`, `webhook-timestamp`,
   `webhook-signature` = `v1,<base64(HMAC-SHA256(secret, id.ts.body))>`, with a
   300s replay window.

Responses:

| Situation | Response |
|---|---|
| No auth presented at all | `200 {"status":"ignored","reason":"missing_signature"}` |
| Auth presented but invalid | `401 {"status":"ignored","reason":"invalid_signature"}` |
| Body not JSON | `200 ignored / invalid_json` |
| Payout (disbursement) confirmation | `200 ignored / payout_confirmation` — **never** turned into a `coa_payments` row |
| Unknown reference (collection) | `200 ignored / unknown_reference` |

> ⚠️ **Never** re-introduce a bare `Authorization: Bearer <anything>` bypass.
> That was a pre-launch audit finding (C1) and it is fixed.

---

## 5. Reference resolution

```
reference = payload.referenceId ?? payload.reference_id ?? payload.identifier
```

`referenceId` is canonical (Lipila echoes ours back). `identifier` is only a
legacy fallback.

---

## 6. Settlement engine rules (`_shared/settlement.ts`)

### Anchors (money only moves on server-side facts)

| Source | Anchor |
|---|---|
| `giving` / `order` | a `coa_payments` row with `payment_ref` in `('approved','completed','confirmed','settled')`; gross capped by the confirmed amount |
| `ride` / `delivery` | request row `completed`/`delivered` **and** `payment_status = 'paid'`; owner check |
| `ride_cut` / `delivery_cut` | platform cut paid to `ride_payout_mobile` setting |
| `escrow` | delivered delivery + vendor phone |
| `church_payout` | `church_withdrawals` ledger row (authoritative amount) |

### Recipient resolution for giving/tithes — THE CHAIN

Resolved **server-side**, in this order. A designated recipient is re-validated
(same tenant + leadership role + valid `260…` number) before use:

1. `payout_tasks.recipient_user_id` — the tithe recipient the giver named
2. `payout_tasks.recipient_role` — the elected tithe role (`pastor` / `bishop` /
   `treasurer` …) → leadership profile phone in that tenant
3. `churches.treasurer_phone`
4. `churches.contact_phone`
5. `churches.pastor_phone`
6. Any leadership profile `phone_number` in the same tenant
   (priority: treasurer → general_treasurer → pastor → bishop → general_secretary →
   apostle → prophet → admin)
7. **Nothing found → the task stays `pending` and retries forever.**

> ⚠️ **No usable number is NEVER a failure.** Money is never dropped and the
> task is never marked `failed` — it waits until the church sets a number.

### Fees

`net = gross − gross×lipila_disbursement_fee_percent(1.5%) − max(gross×coa_payout_fee_percent(1%), min_fee_kwacha K3)`

Fees are remote-configurable in `platform_settings`. Never send a raw amount to
`lipila-payout`.

### Double-pay protection

- `payout_tasks` is atomically claimed `pending → processing` (guards concurrent
  runs).
- `church_withdrawals` has a partial unique index: **one in-flight withdrawal
  per church**.
- `coa_payments.webhook_idempotency = lipila-<reference>` dedupes deliveries.
- Legacy confirmed payments (pre-2026-08-13) are excluded from aggregate
  auto-payout so old collections are never paid twice.

---

## 7. Church auto-payout (aggregate)

When a church's withdrawable balance crosses `church_payout_min_kwacha`
(default K100), a `church_withdrawals` ledger row + `payout_tasks('church_payout')`
task is created and disbursed to the church's resolved payout number.

```
withdrawable = confirmed giving (metadata->>tenant_id)
             − giving payout_tasks (pending/processing/paid)
             − in-flight church_withdrawals
```

RPCs (service-role only): `_church_withdrawable_balances_svc()`,
`enqueue_church_auto_payouts(p_min_kwacha)`, `get_church_withdrawable_balances()`,
`get_church_withdrawals()`, plus the helper `church_recipient_phone(church_id)`
which implements the same chain as §6 in SQL.

---

## 8. Client flow (`lib/features/give/data/lipila_service.dart`)

1. `initiatePayment` → `lipila-collect` → returns `reference`.
2. Poll every 2s (max 20): **DB first** (`coa_payments.status`), then
   `lipila-collect status`, then DB again.
3. On success → `logTransaction(...)` records the `transactions` row and enqueues
   `enqueue_payout_task(p_source='giving', p_payment_ref=<ref>, p_recipient_role=…)`.
4. If the insert fails offline, `offline_giving_queue` stores the intent and
   replays idempotently via `insert_transaction_idempotent` +
   `enqueue_payout_task`.

---

## 9. DO NOT REGRESS — invariants

These were all real bugs that broke real money. Breaking any of them again
silently stops churches from being paid.

1. **`lipila-webhook` must never return 502.** It used to crash before its
   handler ran, so *nothing* was ever confirmed. If you edit it, re-probe:
   ```bash
   curl -X POST https://<ref>.supabase.co/functions/v1/lipila-webhook \
        -H "Content-Type: application/json" -d '{}'
   # expect 200 {"status":"ignored","reason":"missing_signature"}
   ```
2. **`audit_logs` stores the payload in `details` (jsonb).** There is no
   `changes` or `user_agent` column — inserting them fails silently, which is
   why zero webhook audit rows ever existed.
3. **`profiles` has NO `phone` column — only `phone_number`.** Selecting `phone`
   makes PostgREST error and the lookup returns null (this silently broke every
   recipient resolution, including rides/deliveries).
4. **Never let the client decide the payout recipient or amount.** The chain in
   §6 is server-side for a reason.
5. **Never mark a giving task `failed` because no phone number is configured.**
   Retry (`{ retry: true }`), don't fail.
6. **Never create a `coa_payments` row from a disbursement/payout webhook.**
7. **Always pre-create the pending `coa_payments` row before calling Lipila.**
8. **Always append `?secret=` to `callbackUrl`** (both collection and payout)
   and keep the HMAC path working.
9. **After saving `platform_settings`, invalidate `remoteConfigProvider` and
   `platformSettingsProvider`** or changes only appear after an app restart.

---

## 10. Operations: "money didn't arrive" runbook

1. Is the collection confirmed?
   ```sql
   SELECT payment_ref, status, amount, created_at, metadata
   FROM coa_payments ORDER BY created_at DESC LIMIT 10;
   ```
2. Did the webhook arrive?
   ```sql
   SELECT action, details, created_at FROM audit_logs
   WHERE details->>'user_agent' = 'lipila-webhook'
   ORDER BY created_at DESC LIMIT 20;
   ```
3. Is there a payout task, and what state is it in?
   ```sql
   SELECT id, source, payment_ref, recipient_phone, recipient_role,
          gross_amount, net_amount, status, attempt_count, last_error
   FROM payout_tasks ORDER BY created_at DESC LIMIT 20;
   ```
   - `pending` + `attempt_count = 0` → no recipient resolved yet (see chain §6),
     or the anchor isn't confirmed.
   - `failed` + `last_error='no_recipient'` → **this should no longer happen for
     giving** (it now retries); for other sources, the phone is missing.
4. Church aggregate balance:
   ```sql
   SELECT * FROM get_church_withdrawable_balances();
   SELECT * FROM get_church_withdrawals(20);
   ```
5. Does the church have a payout number at all?
   ```sql
   SELECT name, treasurer_phone, contact_phone, pastor_phone
   FROM churches WHERE church_recipient_phone(id::text) IS NULL;
   ```
   (If a church appears here, it has no number anywhere — set any one of the
   three, or a leader's `phone_number`, and queued payouts flow automatically.)

---

## 11. Secrets (Supabase Edge Function env — never in the app)

`LIPILA_API_KEY`, `LIPILA_WEBHOOK_SECRET`, `LIPILA_WEBHOOK_URL`,
`LIPILA_PAYOUT_WEBHOOK_URL`.

`.env` in the app bundle holds **public values only**. Never add payment
secrets to `lib/core/config/env.dart`.

---

## 12. Related code

| Path | Purpose |
|---|---|
| `supabase/functions/lipila-webhook/index.ts` | Delivery handling + auth |
| `supabase/functions/lipila-collect/index.ts` | Collection + status sync |
| `supabase/functions/_shared/settlement.ts` | Settlement engine + recipient chain |
| `supabase/functions/lipila-settle/index.ts` | Cron retry |
| `lib/features/give/data/lipila_service.dart` | Client poll loop |
| `lib/features/finance/data/finance_service.dart` | `logTransaction` → enqueue payout |
| `lib/features/finance/data/offline_giving_queue.dart` | Offline replay |
| `supabase/migrations/20261015_multitenant_tithe_recipients.sql` | `recipient_role`, `church_recipient_phone()` |
| `supabase/migrations/20260890_church_auto_payout.sql` | Auto-payout ledger |
