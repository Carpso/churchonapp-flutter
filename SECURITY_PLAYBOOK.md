# 🔒 Reusable Security Playbook — copy into any project

A project-agnostic checklist + runbook. Copy this into each new project's
`AGENTS.md` (or keep as `SECURITY.md`) and adapt the specifics.

---

## A. Baseline: never ship secrets in the client

| Rule | Why |
|------|-----|
| Server-only secrets (DB/service keys, tokens, API keys) live in the **backend environment only**, read via `env.get()`. | Anything in a mobile/web bundle can be extracted by unzipping the app. |
| If a `.env` is bundled as an app asset, it must contain **only public values** (endpoint URL, anon key). | Anon keys are public by design; admin keys are not. |
| Never commit `.env`, keystores, `key.properties`, `google-services.json`. | One bad `git add -f` leaks everything. |
| Rotate any key that was ever in a shipped build or a plaintext doc. | "Might have leaked" == "leaked". |
| Prefer backend proxies for anything that needs a secret (signed URLs, AI, SMS). | The client asks the server; the server holds the key. |

## B. Auth & authorization (defense in depth)

- **Assume the client is untrusted.** Re-validate every amount, role, and owner check server-side.
- **RLS is the floor, not the ceiling:** enable RLS on every table; policies use `auth.uid()` + tenant/owner scoping; never `USING (true)` on INSERT/UPDATE.
- **Every admin/privileged edge function** verifies the JWT (`auth.getUser`) AND checks the caller's role from `profiles`. Admin-only = superadmin/employee equivalent.
- **Webhooks** verify a shared-secret HMAC/Signature header. Never accept a Bearer-token bypass.
- **Money movement:** amounts re-derived server-side from a server-created record; payouts anchored to a webhook-confirmed payment. Never trust a client-inserted "completed" row.
- **RPCs that mutate money/coins:** require `auth.uid() = target`, cap amounts, revoke `anon` (and `authenticated` for admin RPCs).
- **SECURITY DEFINER functions** always `SET search_path = public` to stop search-path hijacking.

## C. Client hardening

- Store sessions/tokens in secure storage (Keychain/Keystore), not plaintext prefs.
- Disable Android cloud backup (`allowBackup=false` + `dataExtractionRules`) for anything holding sessions or documents.
- Add a CSP + SRI for third-party scripts on web.
- Guard every admin route with a router-level role check (not just hidden buttons).
- Validate deep-link params (UUID formats, length caps, allowlists).
- Don't log tokens/PII; strip logs in release builds.

## D. Incident response (when a hack happens)

1. **Contain first** (0–15 min): disable the affected capability (invalidate the API key, pause the cron, revoke sessions). Never "fix then panic".
2. **Preserve evidence:** DB dump, audit logs, function logs, timestamps.
3. **Triage severity** (critical = money/keys/data, high = mass accounts, medium = single, low = hygiene).
4. **Investigate** what was accessed/written and with which key.
5. **Eradicate:** apply the fix + rotate *all* possibly-exposed keys + reset affected users.
6. **Recover & verify:** re-enable disabled features, test core flows, roll back web if needed.
7. **Post-mortem** within a week; log it; update the playbook if it failed you.

## E. Backup & recovery

- Backups are worthless until you've **tested a restore**. Do it monthly.
- For managed Postgres (Supabase/Firestore): PITR + daily backups; know the retention window.
- Object storage: enable versioning + lifecycle; test a version restore quarterly.
- Keep an on-demand backup endpoint behind an admin-only role gate.
- Document the restore procedure for: schema regression (bad migration), row deletion, media loss, web rollback.

## F. Monitoring (detect before it's a headline)

- Alerts on: failed-auth spikes, CPU/memory, admin action log, payout volume anomalies.
- Weekly: review admin audit log, unusual logins, 401/403 storms in function logs.
- Key sign of compromise: a sudden increase in payouts/transfers/SMS from a single user or to a single phone.

## G. Release checklist (every deploy)

- [ ] `flutter analyze` / `tsc` → 0 errors, 0 warnings.
- [ ] No secrets in build artifacts (search the bundle for key prefixes).
- [ ] Migrations idempotent + applied.
- [ ] Functions deployed with correct env.
- [ ] Routes guarded, endpoints role-gated.
- [ ] Web deployed; old deployments still roll-back-able.
- [ ] `.env.example` updated, real `.env` untouched by git.
