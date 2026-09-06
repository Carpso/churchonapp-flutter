-- Allow event tickets to be settled to the organizer (with fallback to church chain).
-- Previously all event payments were enqueued as p_source='giving' and routed to the
-- treasurer; now finance_service uses p_source='event' with organizer_momo_phone.

-- 1. payout_tasks source check (drop/recreate)
alter table public.payout_tasks drop constraint if exists payout_tasks_source_check;
alter table public.payout_tasks
  add constraint payout_tasks_source_check
  check (source in ('giving','event','order','ride','delivery','escrow','manual','church_payout','ride_cut','delivery_cut'));

-- 2. enqueue_payout_task — allow 'event'
create or replace function public.enqueue_payout_task(
  p_source text,
  p_source_ref text,
  p_payment_ref text,
  p_recipient_user_id uuid,
  p_recipient_phone text,
  p_gross_amount numeric,
  p_recipient_role text default null
) returns public.payout_tasks
language plpgsql security definer set search_path = public
as $$
declare
  v_task public.payout_tasks;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_source not in ('giving','event','order','ride','delivery','escrow','ride_cut','delivery_cut') then
    raise exception 'Invalid settlement source';
  end if;
  if p_gross_amount is null or p_gross_amount <= 0 or p_gross_amount > 100000 then
    raise exception 'Invalid gross amount';
  end if;
  if p_recipient_user_id is not null and p_recipient_user_id = auth.uid() then
    raise exception 'Cannot settle a payout to yourself';
  end if;
  if p_recipient_phone is not null then
    p_recipient_phone := regexp_replace(p_recipient_phone, '\D', '', 'g');
    if length(p_recipient_phone) = 9 then p_recipient_phone := '260' || p_recipient_phone;
    elsif length(p_recipient_phone) = 10 and p_recipient_phone like '0%' then p_recipient_phone := '260' || substring(p_recipient_phone from 2);
    end if;
    if p_recipient_phone = '' then p_recipient_phone := null; end if;
  end if;
  if p_payment_ref is null and p_source_ref is null then
    raise exception 'A payment reference or source reference is required';
  end if;
  if p_recipient_role is not null and lower(p_recipient_role) not in ('pastor','bishop','treasurer','general_secretary','general_treasurer','apostle','prophet','admin') then
    p_recipient_role := null;
  end if;
  if p_recipient_role is not null then p_recipient_role := lower(p_recipient_role); end if;

  insert into public.payout_tasks (user_id, source, source_ref, payment_ref, recipient_user_id, recipient_phone, recipient_role, gross_amount)
  values (auth.uid(), p_source, p_source_ref, p_payment_ref, p_recipient_user_id, p_recipient_phone, p_recipient_role, p_gross_amount)
  on conflict (payment_ref, source, source_ref) do nothing;

  select * into v_task from public.payout_tasks
  where user_id = auth.uid()
    and source = p_source
    and coalesce(source_ref,'') = coalesce(p_source_ref,'')
    and coalesce(payment_ref,'') = coalesce(p_payment_ref,'')
  order by created_at desc limit 1;

  if v_task is null then raise exception 'Could not enqueue settlement task'; end if;
  return v_task;
end;
$$;

grant execute on function public.enqueue_payout_task(text,text,text,uuid,text,numeric,text) to authenticated, service_role;
revoke execute on function public.enqueue_payout_task(text,text,text,uuid,text,numeric,text) from anon, public;
