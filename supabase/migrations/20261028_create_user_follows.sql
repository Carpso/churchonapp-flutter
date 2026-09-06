-- Follow graph for Instagram-style following

create table if not exists public.user_follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint user_follows_unique unique (follower_id, following_id),
  constraint user_follows_self_check check (follower_id != following_id)
);

create index if not exists idx_user_follows_follower on public.user_follows(follower_id);
create index if not exists idx_user_follows_following on public.user_follows(following_id);

alter table public.user_follows enable row level security;

drop policy if exists "Users can manage own follows" on public.user_follows;
create policy "Users can manage own follows"
  on public.user_follows for all
  using (auth.uid() = follower_id)
  with check (auth.uid() = follower_id);

drop policy if exists "Anyone can view follows" on public.user_follows;
create policy "Anyone can view follows"
  on public.user_follows for select
  using (true);

grant select, insert, delete on public.user_follows to authenticated;
