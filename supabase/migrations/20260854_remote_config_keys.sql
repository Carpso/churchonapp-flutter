-- Seed remote-configurable keys into platform_settings
-- These are read by RemoteConfig (lib/core/config/remote_config.dart) —
-- COA can change any value here without shipping an app update.

INSERT INTO platform_settings (key, value) VALUES
  -- Coin rewards (CoinsService)
  ('coins_daily_open_reward', '25'),
  ('coins_streak_bonus_per_day', '50'),
  ('coins_attendance_reward', '50'),
  ('coins_referral_reward', '100'),
  ('coins_daily_collect_cooldown_sec', '72000'),
  ('coins_open_streak_1d', '5'),
  ('coins_open_streak_6d', '10'),
  ('coins_open_streak_13d', '20'),
  ('coins_open_streak_14d', '30'),
  -- Carpso ride pricing (ride_pricing_provider + vehicle_selection_sheet)
  ('ride_per_km_kwacha', '5'),
  ('ride_min_total_fare_kwacha', '15'),
  ('ride_delivery_min_fare_kwacha', '20'),
  ('ride_medium_weight_surcharge_kwacha', '5'),
  ('ride_heavy_weight_surcharge_kwacha', '10'),
  ('ride_avg_city_speed_kmh', '25'),
  -- Bible quiz (bible_quiz_hub_screen)
  ('quiz_prize_1st_kwacha', '500'),
  ('quiz_prize_2nd_kwacha', '300'),
  ('quiz_prize_3rd_kwacha', '150'),
  ('quiz_season_weeks', '12'),
  ('quiz_lease_fee_kwacha', '1500'),
  ('quiz_lease_fee_usd', '50'),
  -- Subscription terms
  ('subscription_trial_days', '30'),
  ('subscription_renewal_days', '365'),
  ('platinum_promo_days', '30'),
  ('subscription_manual_payment_days', '30'),
  -- Marketplace & events
  ('event_commission_percent', '0.10'),
  ('marketplace_delivery_fee_kwacha', '15'),
  -- Platform theme (superadmin override; hex without '#', e.g. FFDA03 = sunflower yellow)
  ('platform_theme_color', 'FFDA03')
ON CONFLICT (key) DO NOTHING;
