-- KPI aggregation RPC for the Lipila Wallet Command Centre.
-- Returns summary counts and totals grouped by status + network.
CREATE OR REPLACE FUNCTION public.get_coa_payment_stats(p_today TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pending_count BIGINT;
    v_pending_amount NUMERIC;
    v_settled_today_count BIGINT;
    v_settled_today_amount NUMERIC;
    v_failed_count BIGINT;
    v_failed_amount NUMERIC;
    v_mtn_amount NUMERIC;
    v_airtel_amount NUMERIC;
    v_zamtel_amount NUMERIC;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_pending_count, v_pending_amount
    FROM public.coa_payments WHERE status = 'pending';

    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_settled_today_count, v_settled_today_amount
    FROM public.coa_payments WHERE status = 'settled' AND settled_at::text >= p_today;

    SELECT COUNT(*), COALESCE(SUM(amount), 0) INTO v_failed_count, v_failed_amount
    FROM public.coa_payments WHERE status = 'failed';

    SELECT COALESCE(SUM(amount), 0) INTO v_mtn_amount
    FROM public.coa_payments WHERE network = 'MTN' AND status = 'settled';

    SELECT COALESCE(SUM(amount), 0) INTO v_airtel_amount
    FROM public.coa_payments WHERE network = 'Airtel' AND status = 'settled';

    SELECT COALESCE(SUM(amount), 0) INTO v_zamtel_amount
    FROM public.coa_payments WHERE network = 'Zamtel' AND status = 'settled';

    RETURN jsonb_build_object(
        'pending_count', v_pending_count,
        'pending_amount', v_pending_amount,
        'settled_today_count', v_settled_today_count,
        'settled_today_amount', v_settled_today_amount,
        'failed_count', v_failed_count,
        'failed_amount', v_failed_amount,
        'mtn_settled', v_mtn_amount,
        'airtel_settled', v_airtel_amount,
        'zamtel_settled', v_zamtel_amount
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_coa_payment_stats(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_coa_payment_stats(TEXT) TO authenticated;
