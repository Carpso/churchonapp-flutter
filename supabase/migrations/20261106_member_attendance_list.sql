-- 20261106: Per-member attendance list for pastor/bishop dashboards

CREATE OR REPLACE FUNCTION get_tenant_member_attendance(
  p_tenant_id TEXT,
  p_months INT DEFAULT 3
)
RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  attended INT,
  total_services INT,
  attendance_rate NUMERIC
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH period AS (
    SELECT (date_trunc('month', now()) - (p_months || ' months')::interval)::date AS start_date
  ),
  services AS (
    SELECT COUNT(DISTINCT service_date)::INT AS total
    FROM member_attendance
    WHERE tenant_id = p_tenant_id
      AND service_date >= (SELECT start_date FROM period)
  ),
  attendance AS (
    SELECT user_id, COUNT(DISTINCT service_date)::INT AS attended
    FROM member_attendance
    WHERE tenant_id = p_tenant_id
      AND service_date >= (SELECT start_date FROM period)
    GROUP BY user_id
  )
  SELECT
    p.id,
    COALESCE(p.full_name, 'Unnamed member'),
    COALESCE(a.attended, 0),
    s.total,
    CASE WHEN s.total > 0
      THEN ROUND(COALESCE(a.attended, 0)::NUMERIC / s.total * 100, 1)
      ELSE 0
    END
  FROM profiles p
  CROSS JOIN services s
  LEFT JOIN attendance a ON a.user_id = p.id
  WHERE p.tenant_id = p_tenant_id
    AND p.role = 'member'
  ORDER BY COALESCE(a.attended, 0) DESC, p.full_name;
$$;

REVOKE EXECUTE ON FUNCTION get_tenant_member_attendance(TEXT, INT) FROM anon;
