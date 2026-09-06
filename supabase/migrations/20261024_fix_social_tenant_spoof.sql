-- Fix tenant spoof on social_posts INSERT — must validate tenant_id matches author's profile tenant
drop policy if exists "social_posts_insert_auth" on public.social_posts;
drop policy if exists "Users can create own posts" on public.social_posts;

create policy "Users can create own posts"
  on public.social_posts for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and (
      tenant_id is null
      or tenant_id::text = (select tenant_id from public.profiles where id = auth.uid())::text
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('superadmin','super_admin','coa_employee','employee'))
    )
  );

-- Also tighten UPDATE/DELETE to tenant
drop policy if exists "Users can update own social posts" on public.social_posts;
create policy "Users can update own social posts"
  on public.social_posts for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and (tenant_id::text = (select tenant_id from public.profiles where id = auth.uid())::text or tenant_id is null));

drop policy if exists "Users can delete own posts" on public.social_posts;
create policy "Users can delete own posts"
  on public.social_posts for delete
  to authenticated
  using (auth.uid() = user_id);
