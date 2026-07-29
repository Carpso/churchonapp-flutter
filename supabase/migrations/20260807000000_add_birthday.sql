-- ============================================================
-- Birthday support + wish tracking (2026-08-07)
-- ============================================================

-- 1. Add birthday column to profiles
alter table public.profiles
  add column if not exists birthday date;

-- 2. Birthday wishes tracking (avoid repeating modal on same day)
create table if not exists public.birthday_wishes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  wish_date date not null,
  age int,
  created_at timestamptz not null default now(),
  unique (user_id, wish_date)
);

-- 3. Row Level Security
alter table public.birthday_wishes enable row level security;

drop policy if exists "birthday_wishes_self" on public.birthday_wishes;
create policy "birthday_wishes_self" on public.birthday_wishes
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
