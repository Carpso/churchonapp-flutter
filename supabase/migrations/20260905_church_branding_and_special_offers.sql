-- Church branding: hero banner image shown as the home hero-card background.
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS banner_url TEXT;

-- Special offers: platform-wide promotional content rendered in the home
-- screen carousel. Managed by the app owner / team (superadmin, coa_employee,
-- employee). Visible to all authenticated users when active.
CREATE TABLE IF NOT EXISTS public.special_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  subtitle TEXT,
  badge TEXT DEFAULT 'SPECIAL OFFER',
  image_url TEXT,
  link_type TEXT NOT NULL DEFAULT 'marketplace', -- marketplace | web | none
  link_target TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  promoted BOOLEAN NOT NULL DEFAULT false,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.special_offers ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can read active offers.
CREATE POLICY special_offers_read_active ON public.special_offers
  FOR SELECT TO authenticated
  USING (is_active = true);

-- Only the owner team (superadmin / coa_employee / employee) manages offers.
CREATE POLICY special_offers_manage ON public.special_offers
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'coa_employee', 'employee')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('superadmin', 'coa_employee', 'employee')
    )
  );

-- Seed the default offer so the home carousel is never empty on first launch.
INSERT INTO public.special_offers (title, subtitle, badge, link_type)
SELECT 'Ministry Books - 20% Off', 'Redeem with Church Coins', 'SPECIAL OFFER', 'marketplace'
WHERE NOT EXISTS (SELECT 1 FROM public.special_offers);
