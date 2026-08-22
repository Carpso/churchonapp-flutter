-- 20261001: Allow 'invited' + 'expired' statuses on pvp_matches.
--
-- Root cause of "violates check constraint" crash on PvP Invite-a-Friend:
-- migration 20260897 introduced the friend-invite lifecycle
--   create_pvp_invite  → INSERT status = 'invited'
--   expire_stale_pvp_invites → UPDATE status = 'expired'
-- but never widened pvp_matches_status_check, which only permitted
-- ('pending','accepted','playing','completed','cancelled','declined').
-- Every invite INSERT therefore failed with 23514 check_violation.

ALTER TABLE public.pvp_matches DROP CONSTRAINT IF EXISTS pvp_matches_status_check;

ALTER TABLE public.pvp_matches ADD CONSTRAINT pvp_matches_status_check
  CHECK (status IN (
    'pending', 'invited', 'accepted', 'playing',
    'completed', 'cancelled', 'declined', 'expired'
  ));
