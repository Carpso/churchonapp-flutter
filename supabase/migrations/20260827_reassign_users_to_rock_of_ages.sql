-- =============================================================================
-- Migration: Reassign all users to Rock Of Ages Chapel & Remove Harvest Church
-- =============================================================================

DO $$
DECLARE
  _rock_tenant_id UUID;
BEGIN
  -- Check if Rock of Ages Chapel exists by slug or ID
  SELECT id INTO _rock_tenant_id
  FROM public.churches
  WHERE slug = 'rock-of-ages-kabulonga' OR name ILIKE '%Rock Of Ages%'
  LIMIT 1;

  IF _rock_tenant_id IS NULL THEN
    _rock_tenant_id := '00000000-0000-0000-0000-000000000036'::UUID;

    -- Insert parent tenant if missing
    INSERT INTO public.tenants (id, name, type)
    VALUES (_rock_tenant_id, 'Rock Of Ages Chapel Kabulonga', 'church')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

    -- Insert church row if missing
    INSERT INTO public.churches (
      id, tenant_id, name, slug, address, latitude, longitude, primary_color, country
    )
    VALUES (
      _rock_tenant_id, _rock_tenant_id,
      'Rock Of Ages Chapel Kabulonga', 'rock-of-ages-kabulonga',
      'Kabulonga Road next to Dill restaurant, Lusaka',
      -15.4190, 28.3490, '#DC2626', 'Zambia'
    )
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name;
  END IF;

  -- Update all profiles to belong to Rock Of Ages Chapel
  -- Handle both text and uuid tenant_id column types
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
    AND column_name = 'tenant_id' AND data_type IN ('text', 'character varying', 'character')
  ) THEN
    UPDATE public.profiles
    SET tenant_id = _rock_tenant_id::text
    WHERE tenant_id IS NULL OR tenant_id != _rock_tenant_id::text;
  ELSE
    UPDATE public.profiles
    SET tenant_id = _rock_tenant_id
    WHERE tenant_id IS NULL OR tenant_id IS DISTINCT FROM _rock_tenant_id;
  END IF;

  -- Also update church_id references where appropriate
  UPDATE public.profiles
  SET church_id = _rock_tenant_id
  WHERE church_id IS NULL OR church_id != _rock_tenant_id;
END $$;

-- Remove Harvest Church entries from churches and tenants
DELETE FROM public.churches
WHERE slug = 'harvest-lsk' OR name ILIKE '%Harvest House International Lusaka%' OR id = '00000000-0000-0000-0000-000000000031'::UUID;

DELETE FROM public.tenants
WHERE name ILIKE '%Harvest House International Lusaka%' OR id = '00000000-0000-0000-0000-000000000031'::UUID;
