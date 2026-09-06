-- RLS normalize (employee -> coa_employee) + deliveries buyer visibility + events is_inter_tenant + missing tables

-- 1. kingdom_news INSERT — add coa_employee / super_admin
drop policy if exists "Writers and admins can create news" on public.kingdom_news;
create policy "Writers and admins can create news"
  on public.kingdom_news for insert
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('writer','admin','superadmin','super_admin','coa_employee','employee')
    )
  );

-- writer_applications SELECT/UPDATE — normalize
drop policy if exists "Admins can view writer applications" on public.writer_applications;
create policy "Admins can view writer applications"
  on public.writer_applications for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('superadmin','super_admin','coa_employee','employee','admin')
    )
  );

drop policy if exists "Admins can update writer applications" on public.writer_applications;
create policy "Admins can update writer applications"
  on public.writer_applications for update
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('superadmin','super_admin','coa_employee','employee','admin')
    )
  );

-- 2. Deliveries buyer visibility — allow buyer to see own delivery via orders
drop policy if exists "Users can view own deliveries" on public.deliveries;
drop policy if exists "Drivers can view assigned deliveries" on public.deliveries;
create policy "Users can view own deliveries"
  on public.deliveries for select
  using (
    auth.uid() = driver_id
    or exists (select 1 from public.orders o where o.id = deliveries.order_id and o.user_id = auth.uid())
  );

-- 3. Events is_inter_tenant — global discover promise
drop policy if exists "Events select tenant scoped" on public.events;
create policy "Events select tenant scoped"
  on public.events for select
  using (
    is_inter_tenant = true
    or tenant_id::text in (select tenant_id from public.profiles where id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('superadmin','super_admin','coa_employee','employee'))
  );

-- 4. Missing tables for event details (queried with .catchError -> empty, but create for correctness)
create table if not exists public.event_participating_churches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  church_id uuid not null references public.churches(id) on delete cascade,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  unique(event_id, church_id)
);

create table if not exists public.event_resources (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  title text not null,
  url text not null,
  type text not null default 'link',
  created_at timestamptz not null default now()
);

alter table public.event_participating_churches enable row level security;
alter table public.event_resources enable row level security;

drop policy if exists "Anyone can view event churches" on public.event_participating_churches;
create policy "Anyone can view event churches"
  on public.event_participating_churches for select using (true);

drop policy if exists "Event hosts can manage participating churches" on public.event_participating_churches;
create policy "Event hosts can manage participating churches"
  on public.event_participating_churches for all
  using (
    exists (select 1 from public.events e where e.id = event_participating_churches.event_id and (e.hosted_by = auth.uid() or e.user_id = auth.uid()))
  )
  with check (
    exists (select 1 from public.events e where e.id = event_participating_churches.event_id and (e.hosted_by = auth.uid() or e.user_id = auth.uid()))
  );

drop policy if exists "Anyone can view event resources" on public.event_resources;
create policy "Anyone can view event resources"
  on public.event_resources for select using (true);

drop policy if exists "Event hosts can manage resources" on public.event_resources;
create policy "Event hosts can manage resources"
  on public.event_resources for all
  using (
    exists (select 1 from public.events e where e.id = event_resources.event_id and (e.hosted_by = auth.uid() or e.user_id = auth.uid()))
  )
  with check (
    exists (select 1 from public.events e where e.id = event_resources.event_id and (e.hosted_by = auth.uid() or e.user_id = auth.uid()))
  );

grant select on public.event_participating_churches, public.event_resources to anon, authenticated;
grant insert, update, delete on public.event_participating_churches, public.event_resources to authenticated;

-- 5. Bookshop tenant-wide orders read (managers/cashiers)
drop policy if exists "Bookshop staff can view tenant orders" on public.orders;
create policy "Bookshop staff can view tenant orders"
  on public.orders for select
  using (
    tenant_id::text in (
      select p.tenant_id from public.profiles p
      where p.id = auth.uid()
        and p.role in ('bookshop_owner','store_manager','assistant','cashier')
    )
  );

-- order_items tenant staff via orders join
drop policy if exists "Bookshop staff can view tenant order items" on public.order_items;
create policy "Bookshop staff can view tenant order items"
  on public.order_items for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.tenant_id::text in (
          select p.tenant_id from public.profiles p
          where p.id = auth.uid() and p.role in ('bookshop_owner','store_manager','assistant','cashier')
        )
    )
  );

-- 6. Fix is_admin_or_employee helper to include coa_employee if not already
-- (already fixed in 20260845, but ensure is_super_admin style not needed here)
