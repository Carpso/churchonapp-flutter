-- 20260918: Prophetic Heatmap — real expansion data.
-- Replaces manual growth_heatmap_data points with real church + membership
-- aggregation so the surveillance map shows actual growth intensity.

CREATE OR REPLACE FUNCTION public.get_prophetic_heatmap_data()
RETURNS TABLE (
  lat double precision,
  lng double precision,
  weight numeric,
  region_name text,
  member_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ch.latitude AS lat,
    ch.longitude AS lng,
    GREATEST(1, (SELECT COUNT(*)::numeric FROM profiles p WHERE p.tenant_id = ch.tenant_id::text)) AS weight,
    ch.name AS region_name,
    (SELECT COUNT(*) FROM profiles p WHERE p.tenant_id = ch.tenant_id::text) AS member_count
  FROM churches ch
  WHERE ch.latitude IS NOT NULL AND ch.longitude IS NOT NULL
  ORDER BY member_count DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_data() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_data() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_prophetic_heatmap_data() TO authenticated;

-- Keep legacy manual data points flowing in as extra markers (weight scaled
-- down so real churches dominate).
CREATE OR REPLACE FUNCTION public.get_prophetic_heatmap_legacy()
RETURNS TABLE (
  lat double precision,
  lng double precision,
  weight numeric,
  region_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g.lat, g.lng, GREATEST(0.5, g.weight) AS weight, g.region_name
  FROM growth_heatmap_data g;
$$;

REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_legacy() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_prophetic_heatmap_legacy() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_prophetic_heatmap_legacy() TO authenticated;