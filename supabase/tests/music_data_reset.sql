-- Synthetic fixtures only. Every insert/delete and assertion is rolled back.
begin;
insert into auth.users(id) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696601'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696602');
insert into public.profiles(user_id, display_name) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696601','Reset fixture A'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696602','Reset fixture B') on conflict (user_id) do nothing;
insert into public.mixtapes(id,owner,title) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696611','b70a9401-d6f5-49ae-90c8-5499e5696601','A'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696612','b70a9401-d6f5-49ae-90c8-5499e5696602','B');
insert into public.mixtape_tracks(mixtape_id,track_uri) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696611','spotify:track:fixture'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696612','spotify:track:fixture');
insert into public.library_snapshots(id,owner,user_id) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696621','b70a9401-d6f5-49ae-90c8-5499e5696601','fixture-a'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696622','b70a9401-d6f5-49ae-90c8-5499e5696602','fixture-b');
insert into public.now_playing(user_id) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696601'), ('b70a9401-d6f5-49ae-90c8-5499e5696602');
insert into public.play_log(user_id,track_uri) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696601','spotify:fixture'),
 ('b70a9401-d6f5-49ae-90c8-5499e5696602','spotify:fixture');

set local role authenticated;
select set_config('request.jwt.claim.sub','b70a9401-d6f5-49ae-90c8-5499e5696601',true);
-- Owner can read and share without recursive policies.
insert into public.mixtape_shares(mixtape_id,shared_with) values
 ('b70a9401-d6f5-49ae-90c8-5499e5696611','b70a9401-d6f5-49ae-90c8-5499e5696602');
do $$ begin
 if (select count(*) from public.mixtapes) <> 1 then raise exception 'Owner isolation failed'; end if;
 update public.library_snapshots set name = 'Road trip' where id = 'b70a9401-d6f5-49ae-90c8-5499e5696621';
 if not exists(select 1 from public.library_snapshots where name = 'Road trip')
 then raise exception 'Owned backup rename failed'; end if;
 update public.library_snapshots set name = 'Forbidden rename' where id = 'b70a9401-d6f5-49ae-90c8-5499e5696622';
 begin
   insert into public.mixtape_shares(mixtape_id,shared_with) values
    ('b70a9401-d6f5-49ae-90c8-5499e5696612','b70a9401-d6f5-49ae-90c8-5499e5696601');
   raise exception 'Forged share owner accepted';
 exception when foreign_key_violation then null; end;
 begin
   perform public.clear_my_music_data('b70a9401-d6f5-49ae-90c8-5499e5696602');
   raise exception 'Wrong-account reset accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','b70a9401-d6f5-49ae-90c8-5499e5696602',true);
do $$ begin
 if (select count(*) from public.mixtapes) <> 2 then raise exception 'Recipient access failed'; end if;
 if (select count(*) from public.mixtape_tracks) <> 2 then raise exception 'Recipient track access failed'; end if;
 delete from public.mixtapes where id = 'b70a9401-d6f5-49ae-90c8-5499e5696611';
 if not exists(select 1 from public.mixtapes where id = 'b70a9401-d6f5-49ae-90c8-5499e5696611') then
   raise exception 'Recipient deleted owner mixtape'; end if;
end $$;
select set_config('request.jwt.claim.sub','b70a9401-d6f5-49ae-90c8-5499e5696601',true);
select public.clear_my_music_data('b70a9401-d6f5-49ae-90c8-5499e5696601');
select public.clear_my_music_data('b70a9401-d6f5-49ae-90c8-5499e5696601'); -- idempotent
do $$ begin
 if exists(select 1 from public.mixtapes) or exists(select 1 from public.library_snapshots)
 or exists(select 1 from public.now_playing) or exists(select 1 from public.play_log)
 then raise exception 'Owner data survived reset'; end if;
 if not exists(select 1 from public.profiles where user_id = auth.uid() and initial_backup_at is not null)
 then raise exception 'Profile/baseline marker lost'; end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.library_snapshots where name = 'Forbidden rename')
 then raise exception 'Other account backup was renamed'; end if;
 if not exists(select 1 from public.mixtapes where owner = 'b70a9401-d6f5-49ae-90c8-5499e5696602')
 or not exists(select 1 from public.library_snapshots where owner = 'b70a9401-d6f5-49ae-90c8-5499e5696602')
 or not exists(select 1 from public.play_log where user_id = 'b70a9401-d6f5-49ae-90c8-5499e5696602')
 then raise exception 'Other account data was touched'; end if;
 if exists(select 1 from public.mixtape_tracks where mixtape_id = 'b70a9401-d6f5-49ae-90c8-5499e5696611')
 then raise exception 'Child cascade failed'; end if;
 if has_function_privilege('anon','public.clear_my_music_data(uuid)','EXECUTE')
 then raise exception 'Anonymous reset is exposed'; end if;
end $$;
rollback;
