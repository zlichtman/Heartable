-- Disposable fixture accounts; every write is rolled back.
begin;
insert into auth.users(id) values
 ('b9400000-0000-4000-8000-000000000001'), ('b9400000-0000-4000-8000-000000000002');
insert into public.profiles(user_id) values
 ('b9400000-0000-4000-8000-000000000001'), ('b9400000-0000-4000-8000-000000000002')
 on conflict (user_id) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','b9400000-0000-4000-8000-000000000001',true);
insert into public.provider_connections(user_id,provider_id,metadata) values
 (auth.uid(),'spotify','{"display_name":"First Person","avatar_url":"https://example.com/first.jpg"}');
insert into public.provider_connections(user_id,provider_id,metadata) values
 (auth.uid(),'jellyfin','{"display_name":"Second Person","avatar_url":"https://example.com/second.jpg"}');
update public.profiles set display_name=E' \t\n',avatar_url=null where user_id=auth.uid();
select public.seed_profile_from_first_connection(auth.uid());
do $$ begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and display_name='First Person' and avatar_url='https://example.com/first.jpg') then
  raise exception 'Missing fields must come from first linked account'; end if;
end $$;
-- Old clients rewrite connected_at; disconnected first pairings still own order.
update public.provider_connections set connected=false,connected_at=null,first_linked_at=now()+interval '1 year',metadata='{}' where user_id=auth.uid() and provider_id='spotify';
update public.profiles set display_name='Heartable user',avatar_url=null where user_id=auth.uid();
select public.seed_profile_from_first_connection(auth.uid());
do $$ begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and display_name='First Person') then
  raise exception 'Reconnect or empty metadata changed first identity'; end if;
end $$;
update public.profiles set display_name='Custom',avatar_url='https://example.com/custom.jpg' where user_id=auth.uid();
select public.seed_profile_from_first_connection(auth.uid());
do $$ begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and display_name='Custom' and avatar_url='https://example.com/custom.jpg') then
  raise exception 'User edits overwritten'; end if;
 begin
  perform public.seed_profile_from_first_connection('b9400000-0000-4000-8000-000000000002');
  raise exception 'Wrong owner allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','b9400000-0000-4000-8000-000000000002',true);
-- A service with no identity API must not silently take a later service's name.
insert into public.provider_connections(user_id,provider_id) values(auth.uid(),'apple');
insert into public.provider_connections(user_id,provider_id,metadata) values(auth.uid(),'spotify','{"display_name":"Later Person"}');
select public.seed_profile_from_first_connection(auth.uid());
do $$ begin
 if exists(select 1 from public.profiles where user_id=auth.uid() and display_name='Later Person') then
  raise exception 'Later service replaced first identity'; end if;
 if exists(select 1 from public.provider_connections where user_id='b9400000-0000-4000-8000-000000000001') then
  raise exception 'Pairing metadata crossed accounts'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.seed_profile_from_first_connection(uuid)','execute') then
  raise exception 'Anonymous execution allowed'; end if;
end $$;
select 'Profile default regressions passed' as result;
rollback;
