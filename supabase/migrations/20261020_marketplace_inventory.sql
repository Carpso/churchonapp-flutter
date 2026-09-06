-- Marketplace inventory fixes: digital download + atomic stock decrement

-- 1. download_url for paid e-books (my_library_screen expects it)
alter table public.marketplace_items
  add column if not exists download_url text;

-- stock already added in 20260818_game_settings_and_bookshop_stock.sql, ensure check
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'marketplace_items_stock_nonnegative' and conrelid = 'public.marketplace_items'::regclass) then
    alter table public.marketplace_items
      add constraint marketplace_items_stock_nonnegative check (stock >= 0);
  end if;
end $$;

-- 2. Atomic stock decrement RPC (SECURITY DEFINER, prevents oversell race)
create or replace function public.decrement_marketplace_stock(p_item_id uuid, p_qty integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Invalid quantity';
  end if;

  update public.marketplace_items
    set stock = greatest(0, stock - p_qty)
    where id = p_item_id
    returning stock into v_stock;

  if not found then
    raise exception 'Item not found';
  end if;
end;
$$;

revoke execute on function public.decrement_marketplace_stock(uuid, integer) from public, anon;
grant execute on function public.decrement_marketplace_stock(uuid, integer) to authenticated, service_role;

-- 3. Backfill order_items.tenant_id (and church_id) — previously never written, so
-- bookshop sales queries filtered by tenant_id always returned 0.
update public.order_items oi
  set tenant_id = o.tenant_id::uuid,
      church_id = o.church_id
  from public.orders o
  where oi.order_id = o.id
    and oi.tenant_id is null
    and o.tenant_id is not null;

-- user_purchases backfill if column exists
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_purchases' and column_name='tenant_id') then
    execute 'update public.user_purchases up set tenant_id = o.tenant_id::uuid from public.orders o where up.order_id = o.id and up.tenant_id is null and o.tenant_id is not null';
  end if;
end $$;
