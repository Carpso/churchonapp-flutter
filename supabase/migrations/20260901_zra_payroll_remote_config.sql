-- Seed remote-configurable ZRA payroll & turnover tax keys into platform_settings
-- Read by RemoteConfig (lib/core/config/remote_config.dart) — COA can adjust any
-- rate here without shipping an app update.
-- Wired into: zambian_payroll_screen.dart + turnover_tax_ledger_screen.dart
-- (editable in Subscription Pricing > Feature Settings).

INSERT INTO platform_settings (key, value) VALUES
  -- ZRA turnover tax: 3% on services, 0.5% on goods (Zambia Turnover Tax Act)
  ('turnover_tax_percent', '3.0'),
  -- Statutory payroll deductions (Zambia)
  ('nhima_percent', '1.0'),
  ('napsa_percent', '5.0'),
  -- PAYE: tax-free threshold + flat rate above it (simplified simulation)
  ('paye_threshold_kwacha', '5100'),
  ('paye_rate_percent', '25.0'),
  -- Buy Coins packages (comma-separated, matching positions = one package).
  -- Wired into: CoinPurchaseService.packagesFrom() + buy_coins_screen.dart
  ('coin_package_coins', '100,250,500,1000,2500'),
  ('coin_package_prices_kwacha', '10,22,40,70,150')
ON CONFLICT (key) DO NOTHING;