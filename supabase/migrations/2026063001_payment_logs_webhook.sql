CREATE TABLE IF NOT EXISTS public.payment_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    amount DOUBLE PRECISION,
    currency TEXT DEFAULT 'ZMW',
    provider TEXT,
    status TEXT,
    tx_ref TEXT UNIQUE,
    disbursement_status TEXT,
    disbursement_tx_ref TEXT,
    platform_fee NUMERIC DEFAULT 0.0,
    net_payout NUMERIC DEFAULT 0.0,
    retry_attempts INT DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_logs_tx_ref ON public.payment_logs(tx_ref);
CREATE INDEX IF NOT EXISTS idx_payment_logs_disbursement_tx_ref ON public.payment_logs(disbursement_tx_ref);
CREATE INDEX IF NOT EXISTS idx_payment_logs_status ON public.payment_logs(status);

ALTER TABLE public.payment_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on payment_logs"
    ON public.payment_logs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Users can view own payment logs"
    ON public.payment_logs
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());
