-- ============================================================================
-- 20261128_emergency_contacts_user.sql
-- Personal emergency contacts.
--
-- The `emergency_contacts` table was tenant/global only, so the Emergency
-- Contacts screen could never show the user's OWN numbers — it was fully
-- hardcoded in the widget (Police 911 etc.) and ignored the service entirely.
--
-- This adds an owner column so a user's personal contacts (next of kin, doctor,
-- neighbour…) live in the DB, are private to them, and can be dialled from the
-- emergency screen.
-- ============================================================================

alter table public.emergency_contacts
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

create index if not exists idx_emergency_contacts_user
  on public.emergency_contacts (user_id, sort_order);

-- Personal contacts are private to their owner; shared/tenant contacts
-- (user_id is null) stay readable by everyone as before.
drop policy if exists "emergency_contacts_personal_owner" on public.emergency_contacts;
create policy "emergency_contacts_personal_owner"
  on public.emergency_contacts
  for all to authenticated
  using (user_id is not null and user_id = auth.uid())
  with check (user_id is not null and user_id = auth.uid());
