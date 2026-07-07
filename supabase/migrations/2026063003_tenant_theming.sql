ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS surface_color TEXT DEFAULT '#FFFAEB',
  ADD COLUMN IF NOT EXISTS font_family TEXT DEFAULT 'Plus Jakarta Sans',
  ADD COLUMN IF NOT EXISTS dark_mode TEXT DEFAULT 'light';

COMMENT ON COLUMN public.churches.surface_color IS 'Scaffold/surface background color hex';
COMMENT ON COLUMN public.churches.font_family IS 'Google Fonts family name for the church theme';
COMMENT ON COLUMN public.churches.dark_mode IS 'Theme mode: light, dark, or system';
