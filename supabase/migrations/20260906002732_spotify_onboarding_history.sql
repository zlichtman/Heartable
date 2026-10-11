-- Provider-reported history is private provenance, not a new Heartable-observed
-- play. It must not trigger friend activity or inflate the Heartable leaderboard.
create table public.provider_play_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_id text not null default 'spotify' check (provider_id = 'spotify'),
  track_uri text not null check (track_uri like 'spotify:track:%'),
  track_name text not null,
  artist text,
  duration_ms integer not null check (duration_ms >= 0),
  played_at timestamptz not null,
  album_art text,
  unique (user_id, provider_id, track_uri, played_at)
);
create index provider_play_history_recent_idx on public.provider_play_history(user_id, played_at desc);
alter table public.provider_play_history enable row level security;
revoke all on public.provider_play_history from public, anon;
grant select, insert, delete on public.provider_play_history to authenticated;
create policy provider_history_read on public.provider_play_history for select to authenticated
  using (user_id = (select auth.uid()));
create policy provider_history_insert on public.provider_play_history for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy provider_history_delete on public.provider_play_history for delete to authenticated
  using (user_id = (select auth.uid()));

alter table public.profiles add column spotify_history_imported_at timestamptz;

create function public.import_spotify_history(expected_owner uuid, plays jsonb)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  caller uuid := auth.uid();
  imported_at timestamptz;
  inserted integer;
begin
  if caller is null or caller is distinct from expected_owner then
    raise exception 'Account changed.' using errcode = '42501';
  end if;
  if jsonb_typeof(plays) <> 'array' or jsonb_array_length(plays) > 50 then
    raise exception 'Expected at most 50 recent plays.' using errcode = '22023';
  end if;
  -- Serialize import/clear across devices. A successful empty import is still
  -- complete, while a network failure never calls this function.
  select spotify_history_imported_at into imported_at from public.profiles
    where user_id = caller for update;
  if not found then raise exception 'Profile not ready.'; end if;
  if imported_at is not null then return 0; end if;
  insert into public.provider_play_history
    (user_id, provider_id, track_uri, track_name, artist, duration_ms, played_at, album_art)
  select caller, 'spotify', p.track_uri, p.track_name, p.artist,
    greatest(0, p.duration_ms), p.played_at, p.album_art
  from jsonb_to_recordset(plays) as p(track_uri text, track_name text, artist text,
    duration_ms integer, played_at timestamptz, album_art text)
  where p.track_uri like 'spotify:track:%' and p.track_name is not null
    and p.played_at <= now() + interval '5 minutes'
  on conflict (user_id, provider_id, track_uri, played_at) do nothing;
  get diagnostics inserted = row_count;
  update public.profiles set spotify_history_imported_at = now() where user_id = caller;
  return inserted;
end;
$$;
revoke all on function public.import_spotify_history(uuid,jsonb) from public, anon;
grant execute on function public.import_spotify_history(uuid,jsonb) to authenticated;

create function public.clear_my_listening_history(expected_owner uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or caller is distinct from expected_owner then
    raise exception 'Account changed.' using errcode = '42501';
  end if;
  -- Acquire the same profile-row lock before either deletion; a late onboarding
  -- response cannot put deliberately cleared history back.
  update public.profiles set spotify_history_imported_at = coalesce(spotify_history_imported_at, now())
    where user_id = caller;
  delete from public.provider_play_history where user_id = caller;
  delete from public.play_log where user_id = caller;
end;
$$;
revoke all on function public.clear_my_listening_history(uuid) from public, anon;
grant execute on function public.clear_my_listening_history(uuid) to authenticated;

create or replace function public.clear_my_music_data(expected_owner uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or caller is distinct from expected_owner then
    raise exception 'Account changed. Sign in again before clearing data.' using errcode = '42501';
  end if;
  perform public.clear_my_listening_history(caller);
  delete from public.library_snapshots where owner = caller;
  delete from public.mixtapes where owner = caller;
  delete from public.track_skip_versions where owner = caller;
  delete from public.now_playing where user_id = caller;
  update public.profiles set initial_backup_at = coalesce(initial_backup_at, now()) where user_id = caller;
end;
$$;
