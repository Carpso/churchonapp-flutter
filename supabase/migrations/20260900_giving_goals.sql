-- 20260900: Giving tab goals — church-wide monthly giving overview RPC + config keys
-- Powers the Give tab: monthly goal ring (personal), church-wide goal bar, recent givers.

-- 1. Church-wide giving overview (safe for members: aggregate + top 5, no per-user leakage)
CREATE OR REPLACE FUNCTION public.get_church_giving_overview(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_month_start TIMESTAMPTZ := date_trunc('month', now());
    v_total NUMERIC;
    v_givers JSONB;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM public.coa_payments
    WHERE metadata->>'tenant_id' = p_tenant_id::text
      AND status IN ('approved', 'completed', 'confirmed', 'settled')
      AND created_at >= v_month_start;

    SELECT COALESCE(jsonb_agg(row_to_json(g) ORDER BY g.amount DESC), '[]'::jsonb) INTO v_givers
    FROM (
        SELECT p.full_name AS name, c.amount, c.created_at
        FROM public.coa_payments c
        JOIN public.profiles p ON p.id = c.user_id
        WHERE c.metadata->>'tenant_id' = p_tenant_id::text
          AND c.status IN ('approved', 'completed', 'confirmed', 'settled')
          AND c.created_at >= v_month_start
        ORDER BY c.amount DESC
        LIMIT 5
    ) g;

    RETURN jsonb_build_object('monthly_total', v_total, 'recent_givers', v_givers);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_church_giving_overview(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_church_giving_overview(UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.get_church_giving_overview(UUID) TO authenticated;

-- 2. Giving goal config keys (editable in Subscription Pricing admin screen)
INSERT INTO platform_settings (key, value) VALUES
  ('giving_monthly_goal_kwacha', '500'),
  ('church_monthly_goal_kwacha', '10000')
ON CONFLICT (key) DO NOTHING;