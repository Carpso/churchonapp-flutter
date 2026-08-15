-- bookshops was missing subscription columns that both the create-bookshop
-- Edge Function and the tenant listing (tenant_service.dart) expect.
-- Without these, bookshop creation failed with a 500 (column does not exist)
-- and bookshops never appeared in the select-tenant screen.

ALTER TABLE public.bookshops
  ADD COLUMN IF NOT EXISTS subscription_ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS plan text DEFAULT 'silver',
  ADD COLUMN IF NOT EXISTS onboarding_fee_paid boolean DEFAULT false;