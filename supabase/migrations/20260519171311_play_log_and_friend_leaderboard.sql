create table if not exists public.play_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  track_uri text,
  track_name text,
  artist text,
  duration_ms integer not null default 0,
  played_at timestamptz not null default now()
);

alter table public.play_log enable row level security;

drop policy if exists play_log_insert_own on public.play_log;
create policy play_log_insert_own on public.play_log
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists play_log_select_own on public.play_log;
create policy play_log_select_own on public.play_log
  for select to authenticated using (user_id = auth.uid());

drop policy if exists play_log_delete_own on public.play_log;
create policy play_log_delete_own on public.play_log
  for delete to authenticated using (user_id = auth.uid());

create index if not exists play_log_user_time
  on public.play_log (user_id, played_at desc);

create or replace function public.friend_leaderboard(window_days integer default 7)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  tracks bigint,
  minutes numeric,
  is_me boolean
)
language sql
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  circle as (
    select uid from me
    union
    select case
             when f.requester_id = (select uid from me) then f.addressee_id
             else f.requester_id
           end
    from public.friendships f, me
    where f.status = 'accepted'
      and ((select uid from me) in (f.requester_id, f.addressee_id))
  )
  select p.user_id,
         p.display_name,
         p.avatar_url,
         count(pl.id) as tracks,
         round(coalesce(sum(pl.duration_ms), 0) / 60000.0, 1) as minutes,
         p.user_id = (select uid from me) as is_me
  from circle c
  join public.profiles p on p.user_id = c.uid
  left join public.play_log pl
         on pl.user_id = c.uid
        and pl.played_at > now() - (window_days || ' days')::interval
  group by p.user_id, p.display_name, p.avatar_url
  order by tracks desc, minutes desc;
$$;

revoke all on function public.friend_leaderboard(integer) from public, anon;
grant execute on function public.friend_leaderboard(integer) to authenticated;;
