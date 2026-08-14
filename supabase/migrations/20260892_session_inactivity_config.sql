-- Session inactivity lockout config (minutes before the app signs the user out)
INSERT INTO platform_settings (key, value) VALUES
  ('session_inactivity_minutes', '5')
ON CONFLICT (key) DO NOTHING;
