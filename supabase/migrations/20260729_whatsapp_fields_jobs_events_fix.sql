CREATE TABLE IF NOT EXISTS public.whatsapp_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled BOOLEAN DEFAULT false,
  phone_number_id TEXT,
  access_token TEXT,
  business_account_id TEXT,
  verify_token TEXT,
  webhook_url TEXT,
  app_id TEXT,
  whatsapp_number TEXT,
  description TEXT,
  last_updated TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.whatsapp_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_config_all ON public.whatsapp_config FOR ALL USING (auth.uid() IS NOT NULL);

INSERT INTO public.whatsapp_config (is_enabled) VALUES (false) ON CONFLICT DO NOTHING;

ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS featured_until TIMESTAMPTZ;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS organizer_momo_phone TEXT;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS organizer_momo_name TEXT;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS speakers TEXT;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'General';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS attendee_count INT DEFAULT 0;
