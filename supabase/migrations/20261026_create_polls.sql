-- Poll Creator was in-memory only (PollStore). Real table for persistence.

create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.churches(id) on delete cascade,
  church_id uuid references public.churches(id) on delete cascade,
  question text not null,
  options jsonb not null, -- [{text, votes}]
  duration text, -- e.g. '1 day', '1 week'
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_polls_tenant on public.polls(tenant_id);
create index if not exists idx_polls_church on public.polls(church_id);
create index if not exists idx_polls_created_at on public.polls(created_at desc);

alter table public.polls enable row level security;

drop policy if exists "Tenant can view polls" on public.polls;
create policy "Tenant can view polls"
  on public.polls for select
  using (
    tenant_id::text in (select tenant_id from public.profiles where id = auth.uid())
    or church_id::text in (select tenant_id from public.profiles where id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('superadmin','super_admin','coa_employee','employee'))
  );

drop policy if exists "Auth can create polls" on public.polls;
create policy "Auth can create polls"
  on public.polls for insert
  with check (auth.uid() = created_by);

drop policy if exists "Creators can manage polls" on public.polls;
create policy "Creators can manage polls"
  on public.polls for all
  using (auth.uid() = created_by)
  with check (auth.uid() = created_by);

grant select, insert, update, delete on public.polls to authenticated;
