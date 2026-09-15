-- ============================================================================
-- 20261127_pvp_matchmaking_queue.sql
-- Real-time PvP matchmaking.
--
-- BEFORE: `_startP2P()` in bible_quiz_hub_screen.dart was cosmetic — it waited
-- 1.5 s ("Connecting...") and pushed the arena with NO opponent lookup at all.
-- Players were never actually matched against each other.
--
-- AFTER: a presence-backed queue. A player joins the queue (heartbeat while
-- waiting); the queue row is only eligible to be matched while the heartbeat is
-- fresh (< 15 s), so a ghost row from a closed app can never be matched. The
-- first player to arrive waits; the second player's join atomically claims the
-- waiting row inside one SECURITY DEFINER transaction (FOR UPDATE SKIP LOCKED,
-- so two simultaneous joiners can never both claim the same opponent) and
-- creates a real `pvp_matches` row in status 'accepted'.
--
-- Coins are NOT touched here: the client deducts its own wager before queueing
-- (existing `deduct_wager_coins` guard) and refunds it if the search is
-- cancelled, exactly like the legacy findOrCreateMatch flow.
-- ============================================================================

create table if not exists public.pvp_matchmaking_queue (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  tenant_id          text,
  elo                int  not null default 1000,
  wager_amount       int  not null default 0,
  question_count     int  not null default 10,
  time_per_question  int  not null default 15,
  mode               text not null default 'global',   -- 'church' | 'global'
  status             text not null default 'waiting',   -- waiting | matched | cancelled
  match_id           uuid,
  created_at         timestamptz not null default now(),
  last_seen          timestamptz not null default now()
);

create index if not exists idx_pvp_queue_matchable
  on public.pvp_matchmaking_queue (status, wager_amount, last_seen desc);

alter table public.pvp_matchmaking_queue enable row level security;

-- Everyone authenticated may SELECT the queue (needed for the realtime
-- "N players searching" counter). Writes are restricted to your own row, and
-- cross-row pairing happens only inside the SECURITY DEFINER RPC below.
drop policy if exists "pvp_queue_select_authenticated" on public.pvp_matchmaking_queue;
create policy "pvp_queue_select_authenticated"
  on public.pvp_matchmaking_queue for select to authenticated using (true);

drop policy if exists "pvp_queue_insert_own" on public.pvp_matchmaking_queue;
create policy "pvp_queue_insert_own"
  on public.pvp_matchmaking_queue for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "pvp_queue_update_own" on public.pvp_matchmaking_queue;
create policy "pvp_queue_update_own"
  on public.pvp_matchmaking_queue for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "pvp_queue_delete_own" on public.pvp_matchmaking_queue;
create policy "pvp_queue_delete_own"
  on public.pvp_matchmaking_queue for delete to authenticated
  using (auth.uid() = user_id);

-- Realtime so a waiting player is pushed into the arena the instant they match.
do $$
begin
  alter publication supabase_realtime add table public.pvp_matchmaking_queue;
exception when duplicate_object then null;
end $$;

alter table public.pvp_matchmaking_queue replica identity full;

-- ---------------------------------------------------------------------------
-- Join the queue (idempotent upsert) and try to claim a live opponent.
-- Returns {"matched": bool, "match_id": uuid|null, "waiting": int}
-- ---------------------------------------------------------------------------
create or replace function public.pvp_queue_join(
  p_elo              int,
  p_wager            int,
  p_question_count   int,
  p_time_per_question int,
  p_mode             text default 'global'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_tid      text;
  v_opp      public.pvp_matchmaking_queue%rowtype;
  v_match_id uuid;
  v_channel  text;
  v_waiting  int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select tenant_id into v_tid from public.profiles where id = v_uid;

  insert into public.pvp_matchmaking_queue as q
    (user_id, tenant_id, elo, wager_amount, question_count,
     time_per_question, mode, status, match_id, created_at, last_seen)
  values
    (v_uid, v_tid, coalesce(p_elo, 1000), greatest(coalesce(p_wager, 0), 0),
     coalesce(p_question_count, 10), coalesce(p_time_per_question, 15),
     coalesce(p_mode, 'global'), 'waiting', null, now(), now())
  on conflict (user_id) do update set
    elo                = excluded.elo,
    tenant_id          = excluded.tenant_id,
    wager_amount       = excluded.wager_amount,
    question_count     = excluded.question_count,
    time_per_question  = excluded.time_per_question,
    mode               = excluded.mode,
    status             = 'waiting',
    match_id           = null,
    last_seen          = now();

  -- Only rows heartbeating in the last 15 s count as "online".
  select * into v_opp
  from public.pvp_matchmaking_queue
  where user_id <> v_uid
    and status = 'waiting'
    and wager_amount = greatest(coalesce(p_wager, 0), 0)
    and last_seen > now() - interval '15 seconds'
    and (coalesce(p_mode, 'global') <> 'church'
         or tenant_id is not distinct from v_tid)
    and abs(elo - coalesce(p_elo, 1000)) <= 400
  order by last_seen desc
  limit 1
  for update skip locked;

  if v_opp.user_id is null then
    select count(*) into v_waiting
    from public.pvp_matchmaking_queue
    where status = 'waiting'
      and last_seen > now() - interval '15 seconds';
    return jsonb_build_object('matched', false, 'match_id', null,
                              'waiting', coalesce(v_waiting, 0));
  end if;

  v_match_id := gen_random_uuid();
  v_channel  := 'pvp_' || v_match_id;

  insert into public.pvp_matches
    (id, player1_id, player2_id, tenant_id, status, channel_name,
     question_count, time_per_question, wager_amount,
     player1_elo_at_match, player2_elo_at_match)
  values
    (v_match_id, v_opp.user_id, v_uid,
     coalesce(v_opp.tenant_id, v_tid), 'accepted', v_channel,
     least(v_opp.question_count,  coalesce(p_question_count, 10)),
     least(v_opp.time_per_question, coalesce(p_time_per_question, 15)),
     v_opp.wager_amount, v_opp.elo, coalesce(p_elo, 1000));

  update public.pvp_matchmaking_queue
     set status = 'matched', match_id = v_match_id, last_seen = now()
   where user_id in (v_opp.user_id, v_uid);

  return jsonb_build_object('matched', true, 'match_id', v_match_id);
end;
$$;

revoke execute on function public.pvp_queue_join(int, int, int, int, text) from anon;

-- ---------------------------------------------------------------------------
-- Heartbeat — keeps my row eligible while I keep waiting.
-- ---------------------------------------------------------------------------
create or replace function public.pvp_queue_heartbeat()
returns void
language sql
security definer
set search_path = public
as $$
  update public.pvp_matchmaking_queue
     set last_seen = now()
   where user_id = auth.uid()
     and status = 'waiting';
$$;

revoke execute on function public.pvp_queue_heartbeat() from anon;

-- ---------------------------------------------------------------------------
-- Leave the queue (cancel search / screen closed).
-- ---------------------------------------------------------------------------
create or replace function public.pvp_queue_leave()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.pvp_matchmaking_queue
   where user_id = auth.uid()
     and status <> 'matched';
$$;

revoke execute on function public.pvp_queue_leave() from anon;

-- ---------------------------------------------------------------------------
-- Housekeeping — drop rows whose owner stopped heartbeating.
-- ---------------------------------------------------------------------------
create or replace function public.pvp_queue_sweep()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  delete from public.pvp_matchmaking_queue
   where last_seen < now() - interval '60 seconds';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function public.pvp_queue_sweep() from anon;
