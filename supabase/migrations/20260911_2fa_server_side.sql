-- 20260911 — 2FA migrated to Supabase Auth native MFA (server-side)
-- (audit follow-up, 2026-08-17)
--
-- PROBLEM: 2FA was broken-by-design:
--   1. The TOTP secret was encrypted CLIENT-side with a key derived from the
--      user id (sha256('$userId-coa-totp-v2')) and stored in
--      profiles.totp_secret — readable by ANY authenticated user in the same
--      tenant via the profiles_select_same_tenant RLS policy. Anyone could
--      decrypt it and log in.
--   2. Nothing was ever enrolled server-side: complete2FA() listed Supabase
--      Auth MFA factors which were always empty, so verification could never
--      succeed.
--
-- FIX: 2FA now uses Supabase Auth native MFA (auth.mfa.enroll/challengeAndVerify/
-- unenroll). The secret exists ONLY in GoTrue — never in the Postgres DB —
-- and verification happens server-side. These columns are no longer needed.

ALTER TABLE profiles
  DROP COLUMN IF EXISTS totp_secret,
  DROP COLUMN IF EXISTS totp_enabled;