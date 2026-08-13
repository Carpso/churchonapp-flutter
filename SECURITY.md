# Church On App — Security, Incident Response & Backup

**Last updated:** 2026-08-13
**Owner:** Church On App (COA) platform team

This document is the operating manual for keeping the platform secure, for
responding when something goes wrong, and for recovering from data loss or
compromise. Keep it up to date every time you touch security-sensitive code.

---

## 1. Security Posture (what is protected)

### Threat model
- **Untrusted actors:** end users (authenticated), anonymous visitors, OAuth
  callback hijackers, anyone with a copy of a released APK (which can be
  unzipped and inspected).
- **Assumption:** the client app is **fully untrusted**. Every security control
  that matters lives server-side: Edge Function auth, RLS policies, webhook
  signatures, server-held secrets.
- **Crown jewels:** Lipila API key + payout flows (real money), R2/Cloudflare
  credentials, the database (profiles, KYC docs, transactions), Supabase admin
  access.

### Server-side secrets (Edge Function env ONLY — never in the app)
`LIPILA_API_KEY`, `LIPILA_WEBHOOK_SECRET`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `CLOUDFLARE_API_TOKEN`, `GEMINI_API_KEY`,
`HUGGINGFACE_TOKEN`, `RESEND_API_KEY`, `AFRICASTALKING_API_KEY`,
`TURN_SECRET`, `CRON_SECRET`, `FCM_SERVICE_ACCOUNT`.

**Rule:** none of these may ever be read by the Flutter app, appear in
`lib/`, `.env`, `pubspec.yaml` assets, or any committed file. They are read via
`Deno.env.get()` inside Edge Functions only. `.env` is bundled into every
release build — it must contain **only public values** (Supabase URL + anon key,
map URLs, public media domain).

### Current hardening in place
- **RLS enabled** on all 150+ tables; financial/KYC tables have tenant + owner
  scoping (migrations `20260843`, `20260845`, `20260888`).
- **Edge Function auth:** every authenticated function verifies the JWT via
  `supabase.auth.getUser()` and gates privileged operations by profile role
  (`database-backup`, `migrate-to-r2`, `lipila-settle`, `data-import`,
  `cloudflare-stream`, `send-sms`, etc.). Admin-only functions check
  `['superadmin','coa_employee']`.
- **Webhook integrity:** `lipila-webhook` / `whatsapp-webhook` verify
  HMAC-SHA256 signatures; no Bearer short-circuit bypass.
- **Payouts anchored to real collections:** `lipila-payout` for non-payout
  roles requires a `coa_payments` row with a **confirmed** status
  (approved/completed/confirmed/settled) matching the reference — the
  `transactions` row alone can no longer trigger a payout.
- **Coin RPCs guarded:** `add_coins` / `deduct_coins` require
  `auth.uid() = user_id` and a bounded amount (migration `20260888`).
  `award_coins`, `system_transfer_coins`, `deduct_coins_atomic` are
  service-role-only.
- **No secrets shipped:** `.env` sanitized to public values; secret getters
  removed from `env.dart`; `SECRETS_BACKUP.md` deleted.
- **Android backup disabled:** `android:allowBackup="false"` +
  `dataExtractionRules` exclude all app data (session token, KYC) from cloud
  backup / device transfer.
- **Web:** CSP meta tag, SRI on the third-party passkeys bundle.
- **go_router role guards** on every admin/staff route (see `app_router.dart`
  `hasAccess`).

### Known follow-ups (manual / future work)
- **ROTATE KEYS (ACTION REQUIRED).** The pre-2026-08-13 `.env` was bundled into
  released APKs/AABs and `SECRETS_BACKUP.md` held plaintext copies. Treat these
  as compromised: `CLOUDFLARE_API_TOKEN`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY`, `GEMINI_API_KEY`, `HUGGINGFACE_TOKEN`,
  `RESEND_API_KEY`, `SUPABASE_ANON_KEY`, Africa's Talking keys. Rotate in each
  dashboard and update the Supabase Edge Function env. (See §5.)
- **Anon key in git history:** `20260870`/`20260871` once embedded the anon JWT
  in cron SQL. Fixed: `CRON_SECRET` is set in Edge env and the live `lps-settle`
  job sends `x-cron-secret` (verified working). The orphaned `event-remind` job
  (old JWT, no deployed function) was deleted — see §6 before re-adding.
- **Client-side TOTP service** (`two_factor_service.dart`) encrypts with a key
  derivable from public data — prefer Supabase Auth MFA
  (`enroll`/`challenge`/`verify`), which holds secrets server-side.
- **OAuth callback** uses the custom `io.supabase.churchonapp://` scheme —
  switch to HTTPS App Links (`https://app.churchonapp.com/auth/callback`).
- **Secure token storage:** switch Supabase session persistence from
  SharedPreferences/localStorage to `flutter_secure_storage`.
- **API key referrer restriction** in Google Cloud Console for the web key.
- **Email confirmations** should be enabled in Supabase Auth (verify production
  dashboard; `config.toml` may not mirror production).

---

## 2. Incident Response Runbook

If you suspect a breach, work top-down by **blast radius**. Do not panic-delete
data. Log timestamps for every action.

### Severity triage
| Sev | Definition | Examples |
|-----|-----------|----------|
| **S1 Critical** | Real money moved / full DB or bucket access | Lipila payout abuse, service-role key leak, R2 write access |
| **S2 High** | Account/data compromise of many users | Mass payout fraud, KYC data exposure, coin minting |
| **S3 Medium** | Single account compromise, spam/abuse | Forged referral, coin minting single user, SMS credit burn |
| **S4 Low** | Hygiene / hardening gaps | Dead code with secrets, missing CSP, open RLS noted for cleanup |

### Immediate containment (minutes 0–15)
1. **Stop the bleeding first.**
   - Payout/collection fraud → in Supabase: `UPDATE coa_payments SET status='rejected' WHERE ...` and disable `lipila-payout` calls by setting `LIPILA_API_KEY` to an invalid value in Edge Function env (payouts fail fast). Do this before fixing code.
   - DB/service-role key leak → **rotate** the key immediately in the Supabase dashboard (Database → Settings → API keys) and the affected providers (R2, Cloudflare).
   - Bulk data exfiltration → temporarily enable **RLS lockdown**: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` + revoke `SELECT` for `authenticated` on the affected table until fixed.
2. **Freeze new writes where it matters:** for financial tables, consider `ALTER TABLE public.transactions DISABLE TRIGGER ALL` is NOT enough — instead pause the settlement cron (`PERFORM cron.unschedule('lps-settle')`) and toggle `LIPILA_API_KEY` invalid.
3. **Preserve evidence:** run `database-backup` (superadmin) to a private bucket, dump `admin_audit_log`, `login_history`, relevant Edge Function logs (Functions → Logs in dashboard) to a file. Keep everything for the post-mortem.
4. **Revoke suspicious sessions:** Supabase Auth → Users → sign out the affected users. If a service token leaked, rotate it (token revocation).
5. **Notify:** internal only at this stage. Do not disclose to users until the fix is verified.

### Investigation (minutes 15–120)
- **What was accessed?** Supabase Auth → audit log / Users. Check `login_history`, `admin_audit_log` for unusual admins.
- **What was written?** Search `transactions`, `coa_payments`, `payout_requests` for abnormal patterns (large amounts, self-recipient, odd phones).
- **Was the attacker active now?** Check Edge Function logs + Postgres activity: `SELECT * FROM pg_stat_activity;`.
- **Which key was used?** Cross-reference the exposure list (§5) against what the attacker could have reached.
- **Full timeline:** create a local file `incident_YYYYMMDD.md` with every action + timestamp. This becomes the post-mortem.

### Eradication
1. Apply the code/migration fix.
2. Rotate every key the attacker *could* have reached — assume "could" = "did".
3. Reset affected user sessions/passwords; for payment users, review their recent transactions.
4. Re-deploy Edge Functions + migrations + web (deploy.ps1).

### Recovery & verification
1. Re-enable cron / re-set `LIPILA_API_KEY`.
2. Verify legitimate flows: give, payout, SMS, coin earning, login.
3. Confirm `flutter analyze` clean and web deploys.
4. Document the incident in `SECURITY.md` §8 (log) and AGENTS.md session notes.

### Post-mortem (within 1 week)
Write up: root cause, how it was detected, blast radius, what's now preventing
recurrence, and any control gaps. File it under `marketing/`? No — `docs/` or
the incident file. Update this runbook if the runbook itself failed you.

---

## 3. Backup & Recovery Plan

### What backs up automatically
- **Supabase PITR + daily backups** — managed by Supabase (Project → Database →
  Backups). Verify retention settings in the dashboard. Use PITR to restore the
  last good point-in-time after a bad migration or destructive query.
- **R2 / Cloudflare** — the media bucket (`choa-sermons-vault`,
  `media.churchonapp.com`) is the source of truth for uploaded media. Enable
  **R2 versioning + lifecycle** on the bucket (R2 → bucket → Settings).
- **Web** — Cloudflare Pages keeps deployment history (roll back any deploy).

### Manual on-demand backup
```powershell
# Full DB dump (JSON) — Superadmin only, rate-limited
curl -X POST https://daboihiudmglwhdfvsku.supabase.co/functions/v1/database-backup `
  -H "Authorization: Bearer <user JWT>" -o churchonapp_backup.json

# Or via supabase CLI (requires access to the project)
supabase db dump --linked --data-only -f backup_YYYYMMDD.sql
supabase db dump --linked --schema public -f schema_YYYYMMDD.sql
```

### Restore procedure
1. **Schema regression (bad migration):** Supabase → Database → Backups →
   select a point in time **before** the migration → Restore to a new database →
   verify → promote.
2. **Accidental row deletion:** restore the affected table rows from the last
   `database-backup` JSON (write a small script to re-insert) or use PITR to a
   new DB and copy rows across.
3. **R2 media loss:** R2 versioning → restore a previous object version. R2
   cross-bucket copy via `migrate-to-r2` `copy-bucket` mode (superadmin).
4. **Web rollback:** Cloudflare Pages → Deployments → roll back to the previous
   deployment.

### Backup testing
- **Monthly:** run `database-backup`, restore it into a throwaway Supabase
  project, and verify key tables have data (`SELECT count(*)`).
- **Quarterly:** test an R2 version restore and a Pages rollback.

---

## 4. Monitoring & Detection

- **Supabase dashboard alerts:** Database → Monitoring → set alerts for CPU,
  memory, and **failed auth** spikes.
- **`admin_audit_log`:** superadmin actions (role changes, approvals,
  backups) are logged — review weekly for anomalies.
- **`login_history`:** watch for logins from unexpected IPs/countries, repeated
  failures.
- **Edge Function logs:** grep for repeated 401/403 and rate-limit 429s:
  - Supabase dashboard → Functions → Logs; or `supabase functions logs <name>`.
- **Payment monitoring:** daily query —
  `SELECT date_trunc('day', created_at) d, count(*), sum(amount) FROM transactions GROUP BY 1 ORDER BY 1 DESC LIMIT 14;`
  A sudden jump in payouts = investigate.
- **Web:** Cloudflare dashboard → Analytics for traffic anomalies; Pages
  deployment history for unauthorized deploys (only you have
  `CLOUDFLARE_API_TOKEN`).

---

## 5. Key Inventory & Rotation Checklist

| Key | Where it lives | Compromised? | How to rotate |
|-----|----------------|--------------|---------------|
| `LIPILA_API_KEY` | Edge env | No (never in app) | Lipila dashboard |
| `LIPILA_WEBHOOK_SECRET` | Edge env | No | Lipila dashboard |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | Edge env | **YES** (was in `.env` + SECRETS_BACKUP) | Cloudflare R2 → Manage R2 API tokens |
| `CLOUDFLARE_API_TOKEN` | local + (was in `.env`) | **YES** | Cloudflare → My Profile → API Tokens |
| `GEMINI_API_KEY` | Edge env | **YES** | Google AI Studio → regenerate |
| `HUGGINGFACE_TOKEN` | Edge env | **YES** | HuggingFace → Settings → Tokens |
| `RESEND_API_KEY` | Edge env | **YES** (was in SECRETS_BACKUP) | Resend → API Keys |
| `SUPABASE_ANON_KEY` / `SUPABASE_URL` | `.env` (public by design) | **ROTATE** (was in cron SQL + backup) | Supabase → Settings → API → anon key |
| `AFRICASTALKING_*` | Edge env | likely | Africa's Talking dashboard |
| `FCM_SERVICE_ACCOUNT` | Edge env | No | Firebase → Service accounts |
| `TURN_SECRET` | Edge env | No | Generate new |
| `CRON_SECRET` | Edge env (set this!) | N/A | `openssl rand -hex 32` |

After rotating, update Edge Function env:
```powershell
supabase secrets set R2_SECRET_ACCESS_KEY=<new>
supabase secrets set CLOUDFLARE_API_TOKEN=<new>
supabase secrets set GEMINI_API_KEY=<new>
supabase secrets set HUGGINGFACE_TOKEN=<new>
supabase secrets set RESEND_API_KEY=<new>
supabase secrets set CRON_SECRET=<new>
supabase secrets set LIPILA_API_KEY=<new>
```
Then re-deploy functions (`.\supabase\deploy.ps1`) and rebuild/redeploy the app.

---

## 6. Cron jobs that need `CRON_SECRET`

pg_cron jobs that call Edge Functions must send `x-cron-secret` matching the
`CRON_SECRET` env var — never a hardcoded anon JWT. Live state (2026-08-13):

| Job | Schedule | Target | Status |
|-----|----------|--------|--------|
| `lps-settle` | `*/5 * * * *` | `lipila-settle` (action `settle`) | Active, sends real `x-cron-secret` — verified working |
| `event-remind` | — | (deleted) | Deleted 2026-08-13: no `event-remind` function is deployed, and `push-notifications` requires a user JWT + has no `event_reminder` action, so it cannot serve this job |

To (re)create a cron job once `CRON_SECRET` is set in Edge env:

```sql
SELECT cron.unschedule('lps-settle');
SELECT cron.schedule('lps-settle', '*/5 * * * *',
  'SELECT net.http_post(url := ''https://daboihiudmglwhdfvsku.supabase.co/functions/v1/lipila-settle'', headers := ''{"x-cron-secret":"<CRON_SECRET>","Content-Type":"application/json"}'', body := ''{"action":"settle"}'')');
```

If event reminders are needed again: build a new Edge Function that queries
upcoming `events` and sends pushes via the FCM service account, deploy it, then
add a cron job with the `x-cron-secret` pattern above.

---

## 7. Secure Development Checklist (new features)

- [ ] Secrets never in `lib/`, `.env`, or assets — only Edge Function env via `Deno.env.get()`.
- [ ] New RPC: `SET search_path = public` + `REVOKE EXECUTE FROM anon` (and from `authenticated` too for admin RPCs).
- [ ] New table: RLS **enabled**; policies use `auth.uid()`, tenant scoping, never `USING (true)` / `WITH CHECK (true)` on INSERT/UPDATE.
- [ ] New Edge Function: JWT verified (`auth.getUser`) + role gate; rate-limit added (`checkRateLimit`).
- [ ] Money-movement code: amounts re-derived server-side; payouts anchored to a webhook-verified record.
- [ ] New route in `app_router.dart`: added to `hasAccess` guard.
- [ ] `flutter analyze` → 0 errors, 0 warnings.
- [ ] New config keys go in `platform_settings` (remote-configurable), never hardcoded.
- [ ] No `print()` of tokens/PII; `debugPrint` only.

---

## 8. Security Log

| Date | Event | Action |
|------|-------|--------|
| 2026-08-13 | `.env` bundled into release builds contained R2/Cloudflare/Gemini/HF secrets | Sanitized `.env` to public values; removed secret getters from `env.dart`; deleted `SECRETS_BACKUP.md`; **rotate keys (pending)** |
| 2026-08-13 | `add_coins`/`deduct_coins` allowed unlimited minting | Guarded with `auth.uid()` + amount cap (migration `20260888`) |
| 2026-08-13 | Client-created `transactions` rows could trigger payouts | `lipila-payout` now requires a confirmed `coa_payments` anchor; coa_payments INSERT limited to `status='pending'` (migration `20260888`) |
| 2026-08-13 | Anon JWT embedded in cron SQL (`20260870`/`20260871`) | Files switched to `x-cron-secret`; live cron needs re-scheduling (§6) |
| 2026-08-13 | Android allowed cloud backup of session/KYC data | `allowBackup=false` + `dataExtractionRules` |
| 2026-08-13 | Web had no CSP, third-party script unverified | CSP meta + SRI on passkeys bundle |
| 2026-08-13 | `supabase/.temp` tracked in git | Added to `.gitignore`, removed from cache |
