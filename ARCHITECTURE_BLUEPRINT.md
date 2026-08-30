# Church On App — Enterprise Architecture Blueprint

> **v1.0.0+296 | August 2026 | Flutter + Supabase + Cloudflare**

---

## 1A. PvP Quiz Invite Lifecycle & Kael AI Opponent

```
Friend PvP invites (pvp_matches.status):
  invited ──▶ accepted ──▶ playing ──▶ completed
     │            │                     │ (winner_id, scores, ELO, wager
     │            └── (no 'playing' is  │  settled server-side via
     │                written today —   │  complete_pvp_match RPC)
     │                waitForMatch      │
     │                watches both)     │
     ├──▶ declined  (inviter refunded)
     └──▶ expired   (30-min sweep:
                      expire_stale_pvp_invites auth-scoped +
                      expire_all_stale_pvp_invites GLOBAL pg_cron
                      job 'pvp-invite-expire' every 15 min)
```

**Key design rules:**
- **Lifecycle statuses** are written ONLY by SECURITY DEFINER RPCs (`create_pvp_invite`, `accept_pvp_invite`, `decline_pvp_invite`, `expire_*`, `join_pvp_match`, `complete_pvp_match`) — the client never `UPDATE`s `pvp_matches`.
- **Invite watcher**: the inviter's client subscribes to `watchMatchScores(matchId)`; on `invited → accepted/playing` it auto-pushes the inviter into the arena (fix: inviters previously never saw the game start). A `pvp_match` push notification + `/quiz/invite/<id>` deep link covers the inviter when they're outside the app.
- **Invite visibility**: `incomingInvitesStream` / `outgoingInvitesStream` track the full lifecycle (PENDING/ACCEPTED/PLAYING/WON/LOST/DECLINED/EXPIRED chips + scores) and are driven by realtime `pvp_matches` changes filtered on `player2_id` / `player1_id`.
- **Kael AI opponent (real inference)**: when no human joins within 25s, `_generateKaelPlan()` sends ALL questions in ONE batched `kael-ai` call (`action: quiz_answers`, strict JSON array of option indices). The arena scores Kael per question from that plan; a 65% random simulation is only the fallback if the call fails. One call per match keeps it inside the 10 req/min rate limit.
- **Rate-limit UX**: the Ask-a-Friend lifeline and the results "Kael explains" sheet detect 429s, never consume the lifeline budget on failure, and surface a Retry action.
- **Cron sweep**: migration `20261003` adds `expire_all_stale_pvp_invites(INT)` (SECURITY DEFINER, no auth dependency, refunds inviters + logs `pvp_wager_refund`) scheduled every 15 min via `cron.schedule('pvp-invite-expire', '*/15 * * * *', ...)`.

---

## 1B. Kael AI Assistant (conversational memory)

```
Flutter KaelChatScreen ── ai_chat_service.dart ──▶ supabase.functions.invoke / raw SSE
   │  (suggested chips, New Chat, streaming,     │  POST /functions/v1/kael-ai
   │   regenerate, typing dots)                  │  action='chat' (SSE) | 'exegesis' | ...
   ▼                                              ▼
ai_chat_sessions (auto-titled) + ai_chat_messages ──▶ kael-ai Edge Function
   (history: last 20 rows fed back oldest→newest, 20-msg window)
```

- **History**: `_fetchMessageHistory(limit: 20)` builds the `messages[]` sent to the Edge Function; error rows are excluded; the system prompt now instructs Kael to use that history for continuity (refer back, no re-greeting, follow topic switches).
- **Auto-title**: sessions start as "New Chat"; the first real user question becomes the title (42-char truncation) so history stays navigable.
- **User context**: name, role, church, streak, level, coins are injected as `userContext` for personalised replies.
- **Professional guardrails**: anti-cheat (never answers active quiz questions), no political/denominational claims, no sensitive PII, concise warm responses with Scripture references.

---

## 1. Multi-Tenant Architecture

```
                                organizations
                                      │
        ┌─────────────────┬───────────┼───────────┬─────────────────┐
        │                 │           │           │                 │
   hierarchy_nodes    churches    bookshops   tenants(id, name, type)
   (presbytery tree)     │                       type = 'church' | 'bookshop'
                         │
              ┌──────────┼──────────┐
              │          │          │
         profiles   ministries   service_reports
         (tenant_id)             (tenant_id: text)
              │
      ┌───────┼───────┬──────────┬──────────┐
      │       │       │          │          │
  transactions events live_streams ministries  data_imports
  (.tenant_id)        (.church_id)           (.tenant_id)
```

**Key rules:**
- Every data-bearing table has either `tenant_id` (UUID FK → churches) or `church_id`
- Row-Level Security (RLS) enforces tenant isolation: users see only their church's data
- 152+ migrations applied; no `USING (true)` policies remain on mutable tables
- Known gap: `profiles.tenant_id` is still `text` type (migration `20260837` ready, awaiting safe deployment window)
- Organization hierarchy via `hierarchy_nodes` (parent→child) enables bishop/apostle network oversight
- Superadmins/COA employees have `tenant_id`-independent access via explicit role checks in RLS policies

---

## 2. Edge Function Security Model

All 29 Edge Functions follow the same auth pattern:

```
Client (Flutter) → Bearer JWT → Edge Function
  → supabase.auth.getUser(token) — verify identity
  → supabase.from("profiles").select("role, tenant_id") — fetch role + scope
  → role gate (allowlist) — reject unauthorized roles
  → tenant ownership check (for tenant-scoped operations)
  → business logic (service-role client for privileged ops)
  → Response
```

**Per-function role gates:**

| Function | Allowed roles | Tenant ownership? |
|----------|-------------|-------------------|
| `cloudflare-stream` | leadership ([role list]) | Yes — church_id via meta + ownsStream() |
| `data-import` | leadership | Yes — force-overwrites tenant_id |
| `lipila-payout` | trusted roles ([role list]) | Server-side fee recomputation |
| `lipila-settle` | superadmin/employee only | System-wide |
| `database-backup` | superadmin/employee only | System-wide |
| `delete-account` | owner or superadmin | Last superadmin guard |
| `migrate-to-r2` | any auth (needs role gate — TODO) | None |
| `send-email` | any auth (needs role gate — TODO) | None |
| `generate-quiz-batch` | advisory (needs hard role gate — TODO) | None |
| `whatsapp-webhook` | none (webhook, unsigned — TODO) | None |

---

## 3. Payment Architecture

```
User initiates payment
  → Flutter: LipilaPaymentGateway (MoMo PIN dialog)
  → supabase.functions.invoke("lipila-collect")
  → Edge Function: calls Lipila API (server-side, no token exposure)
  → Lipila: sends payment request to MTN/Airtel/Zamtel USSD
  → User approves via PIN on phone
  → Lipila: POST /lipila-webhook (HMAC-SHA256 verified)
  → webhook handler: marks coa_payments.status = 'settled'
  → For churches: instant settlement (treasury → church wallet)
  → For drivers/vendors: conditional on delivery completion
  → Church payout: leadership requests → lipila-payout (server-side net + fee verification)
```

| Stage | Collection Fee | Disbursement Fee | COA Fee |
|-------|---------------|-----------------|---------|
| MoMo payment (customer) | 2.5% | — | 1.0% |
| Payout to church/driver | — | 1.5% | 1.0% (min K3) |
| Card payment | `card_fee_percent` (config) | — | 1.0% |

All fees are remote-configurable via `platform_settings` → `FeeConfig` (no app update required).

---

## 4. Streaming Architecture

```
OBS / RTMP Encoder → Cloudflare Stream Live Input
  → Cloudflare: transcodes → HLS/DASH renditions (up to 1080p)
  → Flutter: AdaptiveStreamPlayer (video_player + Chewie)
  → HLS .m3u8 playlist for adaptive bitrate

Phone camera (WHIP) → app POSTs SDP to live input's `webRTC.url` (client-side)
  → cloudflare-stream `whip_offer` action (server-side relay: resolves the live
    input via the API, extracts `webRTC.url` — the publish URL IS the credential,
    no auth header) → Cloudflare Stream WebRTC ingest

Supabase:
  live_streams(cloudflare_stream_id, church_id, stream_key, hls_url, viewer_count)
  church_live_status(church_id, status)
  church_stream_config(church_id, is_paid, max_quality, max_minutes_per_week, ...)
```

**WHIP gotcha (fixed 2026-08-18):** Cloudflare's WHIP publish endpoint is the
live input's `webRTC.url` (`https://customer-<CODE>.cloudflarestream.com/<SECRET>/webRTC/publish`)
— there is NO `api.cloudflare.com/.../live_inputs/{id}/whip` endpoint. The
Edge Function relay must resolve it server-side so the secret publish URL
never ships in the app.

**Cost controls (per church):**

| Tier | Minutes/week | Max viewers | Retention | Storage | Max quality |
|------|-------------|-------------|-----------|---------|-------------|
| Trial | 10 min | 25 | 7 days | 1 GB | 720p |
| Paid (K1,500) | 480 min (8hr) | 1,000 | 90 days | 10 GB | 720p |

Auto-cleanup deletes Cloudflare recordings past retention. Storage overage: K50/GB.

**Security:** Cloudflare Stream role-gated to leadership. `delete_live_input` and `whip_offer` verify ownership via `live_streams.cloudflare_stream_id ↔ church_id`. Recordings use `requireSignedURLs: true`.

---

## 5. Data Import Architecture

```
CSV paste / JSON / Document
  → Flutter: DataImportScreen (entity selector → parse → map columns → preview)
  → supabase.functions.invoke("data-import" { action: "import" })
  → Edge Function:
      1. Auth + leadership role gate
      2. Tenant ownership → force-overwrite tenant_id
      3. sp_validate_import_columns() — server-side column blocklist
      4. Per-row upsert via service-role client (bypasses RLS)
      5. Errors → import_errors (per-row audit trail)
      6. Log → data_imports (total_rows, imported_rows, failed_rows, status)
  → Flutter: Results tab (imported/failed counts)

Document extraction (text/PDF/Word) →
  Edge Function → kael-ai (action: "summary") → returns JSON rows → Flutter: auto-populates + import
```

**Security boundaries:** Column importable allowlist enforced server-side. Role, coins, balance columns blocked. 5000 row max per batch. Entity allowlist validated against information_schema.columns.

**ChMS presets:** Breeze, Planning Center, RockRMS, MTN-bank (mobile money statements).

---

## 6. Reporting Architecture

```
Church leadership submits service report
  → Flutter: ServiceReportFormScreen → reportingService.submitReport()
  → Supabase: service_reports(tenant_id, attendance, offering, visitors, salvations, online_viewers, ...)

Aggregation (dashboard widgets):
  → get_church_service_summary(p_tenant_id)
     → returns {service_count, attendance, offering, visitors, salvations, online_viewers} (current month)
  → get_organization_service_summary(p_org_id)
     → returns {churches, service_count, attendance, offering, visitors, salvations, online_viewers} (org-wide, current month)
  → Both are SECURITY DEFINER with REVOKE FROM anon — callable only by authenticated users

Network dashboards (bishop/apostle):
  → get_organization_stats(p_org_id) — members, branches, monthly_giving, active_streams
  → get_organization_church_member_counts(p_org_id) — per-church breakdown
  → get_organization_service_summary(p_org_id) — service-level aggregation
```

---

## 7. File Map (enterprise-critical paths)

```
lib/
├── core/
│   ├── config/        env.dart (all API keys from .env)
│   ├── routes/        app_router.dart (149 routes)
│   ├── services/      supabase_service, unified_stream_service, coins_service, code_generator_service
│   └── providers/     profile_provider, auth_provider, tenant_service
├── features/
│   ├── admin/         dashboards (apostle, bishop, pastor, coa_employee, superadmin), payroll, member management, reporting_service
│   ├── data_import/   data_import_service, data_import_provider, data_import_screen
│   ├── finance/       lipila_payment_gateway, giving, wallet, coins, partner_redemption
│   ├── modules/
│   │   └── live_streaming/  live_stream_service, adaptive_stream_player, live_stream_studio_screen
│   └── ...

supabase/
├── functions/         29 Edge Functions (auth'd + role-gated)
│   ├── cloudflare-stream/  live input CRUD + WHIP + analytics
│   ├── data-import/        CSV/JSON/doc import engine
│   ├── lipila-*/            payment collection, settlement, payout, webhook
│   ├── kael-ai/             AI chat + document extraction
│   ├── send-email/          email dispatch (Resend)
│   ├── send-sms/            SMS dispatch (BulkSMS)
│   ├── r2-sign/             signed R2 upload/download URLs
│   └── ...
├── migrations/         152+ migration files
│   ├── 20260860  organization_church_member_counts (bounded org-scoped RPC)
│   ├── 20260861  data_import_system (import tables + validation RPC)
│   ├── 20260863  service_reporting_enhancements (P5 reporting fields + aggregate RPCs)
│   ├── 20260910  subscribe-to-tier anchored on confirmed coa_payments
│   ├── 20260911  server-side 2FA (auth.mfa, no client-side TOTP secrets)
│   ├── 20260917  SOS alerts RLS incl. coa_employee
│   ├── 20260918  prophetic heatmap real-data RPC
│   └── 20260919  church_buses RLS incl. coa_employee
│   └── ...
└── deploy.ps1          unified deploy script (migrations + functions + secrets check + analyze)
```

**KYC (Trust & Identity):** documents/selfie are AES-256-CBC encrypted
(`EncryptionService.encryptBytes`, key derived from user id + app secret,
salt+IV persisted on the `kyc_documents` row) before upload to R2 `kyc/`
folder (r2-sign user-scoped). Pipeline is fully bytes-based — works identically
on mobile and web (no `dart:io` File/temp-dir dependencies).

**Tenant hygiene:** duplicate tenant rows (e.g. the 2026-07-26 registration-bug
duplicates) are merged live — child rows repointed via
`tenant_id::text = '<dup>'` scans, dup row deleted, originals preserved in
`public._backup_dup_tenant_merge` (11 rows, 2026-08-18). Run the same pattern
before deleting any tenant row.

---

## 8. Key Design Rules (DO NOT REGRESS)

| Rule | Reasoning |
|------|-----------|
| All mutations go through Edge Functions (not raw `supabase.from().insert` from client) | Server-side validation + fee computation + audit |
| Service-role client only used AFTER role gate | Never bypass RLS without explicit auth |
| SECURITY DEFINER functions always have `SET search_path = public` + `REVOKE FROM anon` | Prevents privilege escalation via `anon` user |
| Never use `USING (true)` on INSERT/UPDATE policies | All writes must be auth'd + tenant-scoped |
| `tenant_id` is always force-overwritten server-side during imports | Prevents tenant-hopping |
| `.env.example` always contains placeholders; `.env` is in `.gitignore` | No secrets in version control |
| `debugPrint()` in catch blocks, never `print()` | Android lint compliance |
| `flutter analyze` target: 0 errors, 0 warnings in `lib/` | CI gate before release |
| All RPC aggregation functions use `tenant_id` scoping | No full-table scans on profiles/churches |
