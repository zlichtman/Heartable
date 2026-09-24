-- Disposable users only; every write is rolled back. Never use a live account.
begin;
insert into auth.users(id) values
 ('f70a9401-d6f5-49ae-90c8-5499e5696601'), ('f70a9401-d6f5-49ae-90c8-5499e5696602');
insert into public.profiles(user_id, display_name) values
 ('f70a9401-d6f5-49ae-90c8-5499e5696601','History fixture A'),
 ('f70a9401-d6f5-49ae-90c8-5499e5696602','History fixture B') on conflict (user_id) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','f70a9401-d6f5-49ae-90c8-5499e5696601',true);
do $$ declare n integer; begin
  select public.import_spotify_history(auth.uid(), '[
    {"track_uri":"spotify:track:test","track_name":"Test","artist":"Fixture","duration_ms":180000,"played_at":"2026-09-01T12:00:00Z"},
    {"track_uri":"spotify:track:test","track_name":"Test","artist":"Fixture","duration_ms":180000,"played_at":"2026-09-01T12:00:00Z"},
    {"track_uri":"spotify:track:test","track_name":"Test","artist":"Fixture","duration_ms":180000,"played_at":"2026-09-01T12:04:00Z"}
  ]'::jsonb) into n;
  if n <> 2 then raise exception 'Import must deduplicate exact events but keep repeated listens'; end if;
  if exists(select 1 from public.play_log) then raise exception 'Import polluted Heartable stats'; end if;
  select public.import_spotify_history(auth.uid(), '[]'::jsonb) into n;
  if n <> 0 then raise exception 'Import was not idempotent'; end if;
  if (select count(*) from public.provider_play_history) <> 2 then raise exception 'History missing'; end if;
  begin
    perform public.import_spotify_history('f70a9401-d6f5-49ae-90c8-5499e5696602','[]'::jsonb);
    raise exception 'Wrong owner import accepted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f70a9401-d6f5-49ae-90c8-5499e5696602',true);
do $$ begin
  if exists(select 1 from public.provider_play_history) then raise exception 'RLS leaked history'; end if;
  begin
    insert into public.provider_play_history(user_id,track_uri,track_name,duration_ms,played_at)
      values('f70a9401-d6f5-49ae-90c8-5499e5696601','spotify:track:forged','Forged',1,now());
    raise exception 'RLS allowed forged owner';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f70a9401-d6f5-49ae-90c8-5499e5696601',true);
select public.clear_my_listening_history(auth.uid());
do $$ begin
  if exists(select 1 from public.provider_play_history) then raise exception 'History survived clear'; end if;
  if public.import_spotify_history(auth.uid(), '[{"track_uri":"spotify:track:late","track_name":"Late","duration_ms":1,"played_at":"2026-09-01T12:00:00Z"}]'::jsonb) <> 0
  then raise exception 'Late onboarding response undid deliberate clear'; end if;
end $$;
reset role;
do $$ begin
  if has_table_privilege('anon','public.provider_play_history','SELECT')
  or has_function_privilege('anon','public.import_spotify_history(uuid,jsonb)','EXECUTE')
  then raise exception 'Anonymous history access is exposed'; end if;
end $$;
rollback;
