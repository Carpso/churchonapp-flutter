-- 20261149_writer_books.sql
-- Verified writers can list BOOKS (physical or digital/eBook) on the same
-- marketplace path as every other item. This migration only adds the optional
-- bibliographic columns (physical/digital + the other fee/category handling is
-- reused from the existing marketplace_items columns), seeds the
-- remote-configurable COA book fee, and exposes a minimal read-only helper so
-- the client can badge the listings of approved writers without leaking any
-- writer PII (the raw writer_applications rows are owner/admin-only under RLS).

-- 1. Optional book metadata columns (idempotent).
ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS isbn text;
ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS author text;
ALTER TABLE public.marketplace_items ADD COLUMN IF NOT EXISTS pages int;

-- 2. Remote-configurable COA fee on marketplace book sales (default 10%).
--    Read by FeeConfig.marketplaceBookFeePercent via platform_settings.
INSERT INTO public.platform_settings (key, value)
VALUES ('marketplace_book_fee_percent', '0.10')
ON CONFLICT (key) DO NOTHING;

-- 3. Approved-writer ids only — safe public signal for the "VERIFIED WRITER"
--    badge. Returns just user_id (no email/phone/reason), so it cannot leak
--    writer contact details the way a broader SELECT policy would.
CREATE OR REPLACE FUNCTION public.verified_writer_ids()
RETURNS TABLE(user_id uuid)
SET search_path = public
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT wa.user_id
  FROM public.writer_applications wa
  WHERE wa.status = 'approved';
$$;

REVOKE EXECUTE ON FUNCTION public.verified_writer_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verified_writer_ids() TO authenticated;
