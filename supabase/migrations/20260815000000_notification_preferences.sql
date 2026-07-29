-- Create notification_preferences table for per-user opt-in/opt-out
create table if not exists notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  channel_id text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, channel_id)
);

-- Enable RLS
alter table notification_preferences enable row level security;

-- RLS: users can read/write only their own preferences
drop policy if exists "Users manage their own notification preferences" on notification_preferences;
create policy "Users manage their own notification preferences"
  on notification_preferences for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- RLS: service role can read all (for Edge Function)
drop policy if exists "Service role reads all preferences" on notification_preferences;
create policy "Service role reads all preferences"
  on notification_preferences for select
  to service_role
  using (true);

-- Auto-create default preferences when a user registers
drop trigger if exists trg_auto_create_notification_preferences on profiles;
drop function if exists auto_create_notification_preferences();
create function auto_create_notification_preferences()
returns trigger as $$
begin
  insert into notification_preferences (user_id, channel_id, enabled) values
    (new.id, 'coa_chat', true),
    (new.id, 'coa_posts', true),
    (new.id, 'coa_payments', true),
    (new.id, 'coa_announcements', true),
    (new.id, 'coa_events', true),
    (new.id, 'coa_prayers', true),
    (new.id, 'coa_testimonies', true),
    (new.id, 'coa_klips', true),
    (new.id, 'coa_fasting', true);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_auto_create_notification_preferences
  after insert on profiles
  for each row
  execute function auto_create_notification_preferences();

-- Seed preferences for existing users
insert into notification_preferences (user_id, channel_id, enabled)
select p.id, c.channel, true
from profiles p
cross join (values
  ('coa_chat'),
  ('coa_posts'),
  ('coa_payments'),
  ('coa_announcements'),
  ('coa_events'),
  ('coa_prayers'),
  ('coa_testimonies'),
  ('coa_klips'),
  ('coa_fasting')
) as c(channel)
on conflict (user_id, channel_id) do nothing;
