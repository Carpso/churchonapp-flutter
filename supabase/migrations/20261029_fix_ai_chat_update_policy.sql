-- Missing UPDATE policy on ai_chat_sessions caused auto-title to fail with 42501
-- and blocked any future session title edits.

drop policy if exists "Users can update own sessions" on public.ai_chat_sessions;
create policy "Users can update own sessions"
  on public.ai_chat_sessions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
