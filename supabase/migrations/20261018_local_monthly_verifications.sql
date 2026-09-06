-- local_monthly_verifications — monthly sign-off path referenced in pastor_dashboard
-- was querying a non-existent table (42P01). Create it with UNIQUE(tenant_id,month_year)
-- and tenant-scoped RLS.

create table if not exists public.local_monthly_verifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.churches(id) on delete cascade,
  church_id uuid references public.churches(id) on delete cascade,
  month_year text not null, -- 'YYYY-MM-01' first of month
  verified_by uuid references auth.users(id),
  total_attendance bigint not null default 0,
  total_tithes numeric not null default 0,
  total_offerings numeric not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  constraint local_monthly_verifications_tenant_month_unique unique (tenant_id, month_year)
);

create index if not exists idx_local_monthly_verifications_tenant_month
  on public.local_monthly_verifications(tenant_id, month_year);

alter table public.local_monthly_verifications enable row level security;

drop policy if exists "Tenant members can view monthly verifications" on public.local_monthly_verifications;
create policy "Tenant members can view monthly verifications"
  on public.local_monthly_verifications for select
  using (
    tenant_id::text in (select tenant_id from public.profiles where id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('superadmin','super_admin','coa_employee','employee'))
  );

drop policy if exists "Tenant leaders can manage monthly verifications" on public.local_monthly_verifications;
create policy "Tenant leaders can manage monthly verifications"
  on public.local_monthly_verifications for all
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tenant_id::text = local_monthly_verifications.tenant_id::text and p.role in ('admin','pastor','bishop','prophet','general_secretary','apostle','treasurer','general_treasurer','superadmin','super_admin','coa_employee','employee'))
  )
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tenant_id::text = local_monthly_verifications.tenant_id::text and p.role in ('admin','pastor','bishop','prophet','general_secretary','apostle','treasurer','general_treasurer','superadmin','super_admin','coa_employee','employee'))
  );

grant select, insert, update, delete on public.local_monthly_verifications to authenticated;
