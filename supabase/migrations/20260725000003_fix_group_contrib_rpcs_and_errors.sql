-- Missing RPC functions for group contributions + error handling fixes

-- ── RPC: increment group collected amount ──────────────────────────────────────
CREATE OR REPLACE FUNCTION increment_group_collected(
  p_group_id UUID,
  p_amount INT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE group_contributions
  SET collected = COALESCE(collected, 0) + p_amount,
      updated_at = now()
  WHERE id = p_group_id;
END;
$$;

-- ── RPC: increment member paid amount ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION increment_member_paid(
  p_member_id UUID,
  p_amount INT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE group_contribution_members
  SET paid = COALESCE(paid, 0) + p_amount,
      updated_at = now()
  WHERE id = p_member_id;
END;
$$;

-- Ensure group_contributions has collected column
ALTER TABLE group_contributions ADD COLUMN IF NOT EXISTS collected INT DEFAULT 0;
ALTER TABLE group_contributions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Ensure group_contribution_members has paid column
ALTER TABLE group_contribution_members ADD COLUMN IF NOT EXISTS paid INT DEFAULT 0;
ALTER TABLE group_contribution_members ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- ── RPC: get active quiz lease for a church ───────────────────────────────────
CREATE OR REPLACE FUNCTION get_active_quiz_lease(p_church_id UUID)
RETURNS SETOF church_quiz_leases
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT * FROM church_quiz_leases
  WHERE church_id = p_church_id AND status = 'active'
    AND lease_start <= now() AND lease_end >= now()
  ORDER BY created_at DESC
  LIMIT 1;
$$;
