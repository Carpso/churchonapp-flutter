-- ============================================================
-- Bible Quiz Enhancements (2026-08-06)
-- New question types, hints/explanations, age tiers, daily streak
-- ============================================================

-- 1. Extend quiz_questions with richer types -------------------
alter table public.quiz_questions
  add column if not exists type text not null default 'choice',
  add column if not exists correct_answers jsonb,
  add column if not exists answer text,
  add column if not exists hint text,
  add column if not exists explanation text,
  add column if not exists age_tier text not null default 'all',
  add column if not exists ordering_items jsonb;

-- 2. Daily streak tracking (cross-day retention) --------------
create table if not exists public.quiz_streaks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  current_streak int not null default 0,
  longest_streak int not null default 0,
  total_days int not null default 0,
  last_played date,
  updated_at timestamptz not null default now(),
  unique (user_id)
);

-- 3. Row Level Security -----------------------------------------
alter table public.quiz_streaks enable row level security;

drop policy if exists "quiz_streaks_self" on public.quiz_streaks;
create policy "quiz_streaks_self" on public.quiz_streaks
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- quiz_questions remains publicly readable (existing policy);
-- new columns are readable under the same policy.
-- Achievements/leaderboards already use the existing
-- achievements + user_achievements tables (see achievement_service.dart).
