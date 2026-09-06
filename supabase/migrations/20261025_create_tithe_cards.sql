-- tithe_cards was 0-byte empty placeholder (20260714000005_tithe_cards.sql)
-- Real table for Tithe Card feature (tithe_service.dart:18)

create table if not exists public.tithe_cards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.churches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_id text not null, -- COA-... from CodeGeneratorService
  member_name text,
  member_email text,
  member_phone text,
  total_tithe_amount numeric not null default 0,
  tithe_count integer not null default 0,
  frequency text not null default 'irregular',
  last_tithe_date timestamptz,
  qr_data text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tithe_cards_tenant_user_unique unique (tenant_id, user_id)
);

create index if not exists idx_tithe_cards_tenant_user on public.tithe_cards(tenant_id, user_id);
create index if not exists idx_tithe_cards_user on public.tithe_cards(user_id);

alter table public.tithe_cards enable row level security;

drop policy if exists "Users can view own tithe card" on public.tithe_cards;
create policy "Users can view own tithe card"
  on public.tithe_cards for select
  using (auth.uid() = user_id);

drop policy if exists "Users can manage own tithe card" on public.tithe_cards;
create policy "Users can manage own tithe card"
  on public.tithe_cards for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Tenant leaders can view tithe cards" on public.tithe_cards;
create policy "Tenant leaders can view tithe cards"
  on public.tithe_cards for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.tenant_id::text = tithe_cards.tenant_id::text
        and p.role in ('admin','pastor','bishop','prophet','general_secretary','apostle','treasurer','general_treasurer','superadmin','super_admin','coa_employee','employee')
    )
  );

grant select, insert, update, delete on public.tithe_cards to authenticated;
