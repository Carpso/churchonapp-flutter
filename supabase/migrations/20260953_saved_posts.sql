-- 20260953 — saved_posts table
--
-- The bookmark action on social posts only flipped a local bool in
-- social_post_card.dart — nothing was persisted, so "saved" posts vanished on
-- scroll/reload. Own-row RLS keeps it user-private.

create table if not exists public.saved_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.social_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, post_id)
);

alter table public.saved_posts enable row level security;

drop policy if exists "saved_posts_select_own" on public.saved_posts;
create policy "saved_posts_select_own"
  on public.saved_posts for select
  using (auth.uid() = user_id);

drop policy if exists "saved_posts_insert_own" on public.saved_posts;
create policy "saved_posts_insert_own"
  on public.saved_posts for insert
  with check (auth.uid() = user_id);

drop policy if exists "saved_posts_delete_own" on public.saved_posts;
create policy "saved_posts_delete_own"
  on public.saved_posts for delete
  using (auth.uid() = user_id);