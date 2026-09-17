-- ============================================================================
-- 20261143_klips_user_avatar.sql
-- `create_klip_screen` inserts `user_avatar` into `klips`, but that column does
-- not exist on the live table → the whole INSERT failed with 42703, so NO klip
-- could ever be posted. Add the column (and keep the client unchanged).
-- ============================================================================

ALTER TABLE public.klips ADD COLUMN IF NOT EXISTS user_avatar text;

COMMENT ON COLUMN public.klips.user_avatar IS
  'Author avatar URL snapshot (shown in the Klips feed).';
