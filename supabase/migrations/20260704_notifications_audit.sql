ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.churches(id),
ADD COLUMN IF NOT EXISTS type TEXT,
ADD COLUMN IF NOT EXISTS reference_id TEXT;

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_id ON public.notifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON public.notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, is_read) WHERE is_read = false;
