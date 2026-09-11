-- 20261105: Baptism registry hardening + member attendance tracking
-- Idempotent — all IF NOT EXISTS guards.

-- 1. Harden baptisms table
ALTER TABLE baptisms ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE baptisms ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE baptisms ADD COLUMN IF NOT EXISTS certificate_number TEXT;

-- 2. New table: per-member service attendance
CREATE TABLE IF NOT EXISTS member_attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  tenant_id TEXT NOT NULL,
  service_date DATE NOT NULL,
  service_type TEXT DEFAULT 'Sunday Service',
  checked_in_at TIMESTAMPTZ DEFAULT now(),
  checked_in_by UUID REFERENCES profiles(id),
  notes TEXT,
  UNIQUE(user_id, tenant_id, service_date, service_type)
);

ALTER TABLE member_attendance ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Members can view own attendance" ON member_attendance FOR SELECT USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Admins can view tenant attendance" ON member_attendance FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND tenant_id = member_attendance.tenant_id
      AND role IN ('admin','pastor','bishop','superadmin','coa_employee','leader','general_secretary'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Admins can insert attendance" ON member_attendance FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND tenant_id = member_attendance.tenant_id
      AND role IN ('admin','pastor','bishop','superadmin','coa_employee','leader','general_secretary'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_member_attendance_tenant_date ON member_attendance(tenant_id, service_date DESC);
CREATE INDEX IF NOT EXISTS idx_member_attendance_user ON member_attendance(user_id, service_date DESC);

-- 3. RPC: get_tenant_attendance_overview — dashboard summary
CREATE OR REPLACE FUNCTION get_tenant_attendance_overview(p_tenant_id TEXT)
RETURNS TABLE(total_members INT, avg_attendance_mtd NUMERIC, top_attendees JSONB, absent_members JSONB)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH mtd AS (
    SELECT user_id, COUNT(DISTINCT service_date) AS svc_count
    FROM member_attendance
    WHERE tenant_id = p_tenant_id AND service_date >= date_trunc('month', now())::date
    GROUP BY user_id
  ),
  total_m AS (
    SELECT COUNT(*) AS cnt FROM profiles WHERE tenant_id = p_tenant_id AND role = 'member'
  )
  SELECT
    (SELECT cnt FROM total_m)::INT,
    COALESCE(ROUND((SELECT AVG(svc_count) FROM mtd), 1), 0),
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('user_id', top_users.user_id, 'name', top_users.full_name, 'count', top_users.svc_count))
       FROM (
         SELECT m.user_id, p.full_name, m.svc_count
         FROM mtd m JOIN profiles p ON p.id = m.user_id
         ORDER BY m.svc_count DESC
         LIMIT 10
       ) top_users),
      '[]'::jsonb),
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('user_id', p.id, 'name', p.full_name))
       FROM profiles p WHERE p.tenant_id = p_tenant_id AND p.role = 'member'
         AND p.id NOT IN (SELECT user_id FROM mtd) LIMIT 20),
      '[]'::jsonb);
$$;
REVOKE EXECUTE ON FUNCTION get_tenant_attendance_overview(TEXT) FROM anon;

-- 4. RPC: record_member_attendance — check-in a member
CREATE OR REPLACE FUNCTION record_member_attendance(
  p_user_id UUID, p_tenant_id TEXT, p_service_date DATE, p_service_type TEXT DEFAULT 'Sunday Service'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO member_attendance (user_id, tenant_id, service_date, service_type, checked_in_by)
  VALUES (p_user_id, p_tenant_id, p_service_date, p_service_type, auth.uid())
  ON CONFLICT (user_id, tenant_id, service_date, service_type) DO NOTHING;
END;
$$;
REVOKE EXECUTE ON FUNCTION record_member_attendance(UUID, TEXT, DATE, TEXT) FROM anon;

-- 5. RPC: get_member_attendance_summary — per-member breakdown
CREATE OR REPLACE FUNCTION get_member_attendance_summary(
  p_tenant_id TEXT, p_user_id UUID, p_months INT DEFAULT 3
)
RETURNS TABLE(total_services INT, attended INT, attendance_rate NUMERIC, monthly_breakdown JSONB)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH period AS (
    SELECT (date_trunc('month', now()) - (p_months || ' months')::interval)::date AS start_date
  ),
  total_services AS (
    SELECT COUNT(DISTINCT service_date) AS cnt FROM member_attendance
    WHERE tenant_id = p_tenant_id AND service_date >= (SELECT start_date FROM period)
  ),
  member_attended AS (
    SELECT COUNT(DISTINCT service_date) AS cnt FROM member_attendance
    WHERE tenant_id = p_tenant_id AND user_id = p_user_id AND service_date >= (SELECT start_date FROM period)
  ),
  monthly AS (
    SELECT to_char(service_date, 'YYYY-MM') AS month, COUNT(DISTINCT service_date) AS attended
    FROM member_attendance
    WHERE tenant_id = p_tenant_id AND user_id = p_user_id AND service_date >= (SELECT start_date FROM period)
    GROUP BY to_char(service_date, 'YYYY-MM') ORDER BY month DESC
  )
  SELECT
    (SELECT cnt FROM total_services),
    (SELECT cnt FROM member_attended),
    CASE WHEN (SELECT cnt FROM total_services) > 0
      THEN ROUND((SELECT cnt FROM member_attended)::NUMERIC / (SELECT cnt FROM total_services) * 100, 1)
      ELSE 0 END,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('month', month, 'attended', attended)) FROM monthly), '[]'::jsonb);
$$;
REVOKE EXECUTE ON FUNCTION get_member_attendance_summary(TEXT, UUID, INT) FROM anon;
