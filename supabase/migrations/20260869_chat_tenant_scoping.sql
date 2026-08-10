-- Calls table tenant scoping for same-church call routing.
ALTER TABLE public.calls
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_calls_tenant ON public.calls(tenant_id);
CREATE INDEX IF NOT EXISTS idx_calls_recipient ON public.calls(recipient_id, status);
