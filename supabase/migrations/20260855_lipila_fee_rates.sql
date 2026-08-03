-- Align fee config with the REAL Lipila merchant rates (wallet 68907, Carpso Solutions):
--   MoMo Collection 2.5% | MoMo Disbursement 1.5%
--
-- 1. momo_fee_percent was 0.015 (1.5%) — undercounted the real 2.5% collection fee,
--    so customers paid 2.5% total and Lipila took ALL of it (COA kept 0%).
--    Now 2.5%: customers pay 1% COA + 2.5% Lipila = 3.5% on MoMo, COA keeps 1%.
--
-- 2. lipila_disbursement_fee_percent is NEW — Lipila charges 1.5% on every payout
--    (drivers, vendors, church settlements). The app now deducts it from payout
--    amounts before calling lipila-payout and discloses it in admin dashboards.

INSERT INTO platform_settings (key, value) VALUES
  ('momo_fee_percent', '0.025'),
  ('lipila_disbursement_fee_percent', '0.015')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
