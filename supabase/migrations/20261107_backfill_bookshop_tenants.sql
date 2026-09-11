-- 20261107: Ensure every bookshop tenant has a child bookshops record.
-- This repairs tenants created before the bookshop child row was inserted.

INSERT INTO public.bookshops (tenant_id, name, is_verified)
SELECT t.id, t.name, true
FROM public.tenants t
WHERE t.type = 'bookshop'
  AND NOT EXISTS (
    SELECT 1 FROM public.bookshops b WHERE b.tenant_id = t.id
  );
