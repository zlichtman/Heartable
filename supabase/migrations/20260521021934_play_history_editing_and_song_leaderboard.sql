-- Make `play_log` user-editable: existing RLS lets the owner write, but we
-- want to be explicit and also allow safe DELETE by id (the client already
-- has owner-scoped SELECT; without a delete policy, "remove embarrassing
-- play" silently no-ops).
alter table public.play_log enable row level security;

drop policy if exists play_log_owner_all on public.play_log;
create policy play_log_owner_all on public.play_log
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Index for "my recent plays" and the leaderboard join.
create index if not exists play_log_user_played_idx
  on public.play_log (user_id, played_at desc);

-- Song-level friend leaderboard: instead of ranking *users* by plays, this
-- ranks *songs* by how many times the caller + their accepted friends
-- collectively played them in a window. Each row also returns the list of
-- contributors so the UI can show "5 plays · Zach + Alex + 1".
--
-- SECURITY DEFINER so we can join play_log + friendships without leaking,
-- guarded by an explicit check that every returned row only includes plays
-- by the caller or their accepted friends.
create or replace function public.song_leaderboard(window_days integer)
returns table (
  track_uri text,
  track_name text,
  artist text,
  plays integer,
  contributors jsonb
)
language sql
security definer
set search_path = public, auth
as $$
  with my_friends as (
    select case when requester_id = auth.uid() then addressee_id
                else requester_id end as friend_id
    from public.friendships
    where status = 'accepted'
      and (requester_id = auth.uid() or addressee_id = auth.uid())
  ),
  allowed_users as (
    select auth.uid() as user_id
    union all
    select friend_id from my_friends
  ),
  windowed as (
    select pl.user_id, pl.track_uri, pl.track_name, pl.artist
    from public.play_log pl
    join allowed_users au on au.user_id = pl.user_id
    where pl.played_at >= now() - make_interval(days => window_days)
      and pl.track_uri is not null
  )
  select
    w.track_uri,
    -- pick a single canonical name/artist per track_uri (any one is fine)
    max(w.track_name) filter (where w.track_name is not null) as track_name,
    max(w.artist) filter (where w.artist is not null) as artist,
    count(*)::int as plays,
    jsonb_agg(distinct jsonb_build_object(
      'userId', w.user_id,
      'displayName', p.display_name,
      'avatarUrl', p.avatar_url
    )) as contributors
  from windowed w
  left join public.profiles p on p.user_id = w.user_id
  group by w.track_uri
  order by plays desc, w.track_uri
  limit 50;
$$;

grant execute on function public.song_leaderboard(integer) to authenticated;;
