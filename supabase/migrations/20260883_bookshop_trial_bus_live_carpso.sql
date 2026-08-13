-- 20260883_bookshop_trial_bus_live_carpso.sql
-- 1) Bookshops join the trial/subscription system (parity with churches)
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'silver';
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS onboarding_fee_paid BOOLEAN DEFAULT false;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS onboarding_fee_paid_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS promotion_platinum_until TIMESTAMPTZ;

-- 2) Live bus tracking columns on church_buses
ALTER TABLE IF EXISTS public.church_buses ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION;
ALTER TABLE IF EXISTS public.church_buses ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION;
ALTER TABLE IF EXISTS public.church_buses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 3) Global Carpso feature toggle (only COA / superadmin can change this value)
INSERT INTO platform_settings (key, value) VALUES ('carpso_ride_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

-- 4) Onboarding fee amounts (K500 church/pastor, K1000 bishop)
INSERT INTO platform_settings (key, value) VALUES
  ('onboarding_fee_church_kwacha', '500'),
  ('onboarding_fee_bishop_kwacha', '1000')
ON CONFLICT (key) DO NOTHING;

-- 5) Installment support: track onboarding balance due on churches + bookshops
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS onboarding_balance_due DOUBLE PRECISION DEFAULT 0;
ALTER TABLE IF EXISTS public.bookshops ADD COLUMN IF NOT EXISTS onboarding_balance_due DOUBLE PRECISION DEFAULT 0;
