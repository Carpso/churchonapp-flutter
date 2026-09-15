-- ============================================================================
-- 20261129_webview_opens.sql
-- In-app browser analytics.
--
-- External links (global news, partner sites, shared articles) are opened in
-- the platform in-app browser (Chrome Custom Tabs / SFSafariViewController) so
-- the user never leaves Church On App. This records each open so COA can see
-- what members actually read.
-- ============================================================================

create table if not exists public.webview_opens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete set null,
  tenant_id   text,
  url         text not null,
  source      text,
  created_at  timestamptz not null default now()
);

create index if not exists idx_webview_opens_created
  on public.webview_opens (created_at desc);
create index if not exists idx_webview_opens_url
  on public.webview_opens (url);

alter table public.webview_opens enable row level security;

-- Anyone signed in may record an open (their own).
drop policy if exists "webview_opens_insert_own" on public.webview_opens;
create policy "webview_opens_insert_own"
  on public.webview_opens for insert to authenticated
  with check (auth.uid() = user_id);

-- Only platform staff may read the analytics.
drop policy if exists "webview_opens_staff_read" on public.webview_opens;
create policy "webview_opens_staff_read"
  on public.webview_opens for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('superadmin', 'super_admin', 'coa_employee', 'employee')
    )
  );

-- Aggregated view for the COA dashboard.
create or replace function public.get_webview_analytics(p_days int default 30, p_limit int default 25)
returns table (url text, source text, opens bigint, unique_users bigint, last_open timestamptz)
language sql
security definer
set search_path = public
as $$
  select url,
         max(source)                     as source,
         count(*)                        as opens,
         count(distinct user_id)         as unique_users,
         max(created_at)                 as last_open
  from public.webview_opens
  where created_at > now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
  group by url
  order by opens desc
  limit greatest(coalesce(p_limit, 25), 1);
$$;

-- Admin-only: never expose to anonymous callers.
revoke execute on function public.get_webview_analytics(int, int) from anon;
revoke execute on function public.get_webview_analytics(int, int) from public;
grant execute on function public.get_webview_analytics(int, int) to authenticated;
