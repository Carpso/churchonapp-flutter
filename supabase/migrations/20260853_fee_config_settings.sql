-- Insert fee configuration keys into platform_settings
-- These are remote-configurable — COA team can update without app updates

INSERT INTO platform_settings (key, value) VALUES
  ('coa_fee_percent', '0.01'),
  ('momo_fee_percent', '0.015'),
  ('card_fee_percent', '0.025'),
  ('business_cut_percent', '0.10'),
  ('min_fee_kwacha', '3.0')
ON CONFLICT (key) DO NOTHING;
