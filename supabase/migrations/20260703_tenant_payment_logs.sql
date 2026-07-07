ALTER TABLE public.payment_logs ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id);

CREATE INDEX IF NOT EXISTS idx_payment_logs_tenant_id ON public.payment_logs(tenant_id);
