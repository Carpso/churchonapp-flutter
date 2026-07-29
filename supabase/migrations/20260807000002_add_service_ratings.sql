-- Service ratings for drivers, riders, sellers (2026-08-07)

-- 1. Universal ratings table
create table if not exists public.service_ratings (
  id uuid primary key default gen_random_uuid(),
  rater_id uuid not null references auth.users(id) on delete cascade,
  rated_id uuid not null references auth.users(id) on delete cascade,
  rating int not null check (rating >= 1 and rating <= 5),
  review text,
  context text not null, -- 'ride', 'delivery', 'marketplace'
  context_id uuid,       -- ride_request_id, delivery_request_id, order_id
  created_at timestamptz not null default now(),
  unique (rater_id, context, context_id)  -- one rating per user per transaction
);

-- 2. Indexes
create index if not exists idx_ratings_rated on public.service_ratings(rated_id);
create index if not exists idx_ratings_rater on public.service_ratings(rater_id);
create index if not exists idx_ratings_context on public.service_ratings(context, context_id);

-- 3. RLS
alter table public.service_ratings enable row level security;

drop policy if exists "ratings_insert_own" on public.service_ratings;
create policy "ratings_insert_own" on public.service_ratings
  for insert to authenticated
  with check (auth.uid() = rater_id);

drop policy if exists "ratings_read_public" on public.service_ratings;
create policy "ratings_read_public" on public.service_ratings
  for select to authenticated
  using (true);

-- 4. RPC to get average rating for a user
create or replace function public.get_user_avg_rating(target_user_id uuid)
returns table(avg_rating numeric, total_ratings bigint)
language sql stable
as $$
  select coalesce(round(avg(rating), 1), 0) as avg_rating,
         count(*) as total_ratings
  from public.service_ratings
  where rated_id = target_user_id;
$$;
