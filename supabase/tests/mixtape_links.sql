begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-9000-000000000571','mixtape-owner@example.invalid',now()),
('00000000-0000-4000-9000-000000000572','mixtape-stranger@example.invalid',now());
insert into public.mixtapes(id,owner,title) values
('00000000-0000-4000-9000-000000000573','00000000-0000-4000-9000-000000000571','Private draft');
insert into public.mixtape_tracks(mixtape_id,track_uri,track_name,position,note) values
('00000000-0000-4000-9000-000000000573','spotify:track:123','A song',0,'A personal note');
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000571',true);
set local role authenticated;
do $test$
declare result jsonb; existing_track uuid;
begin
  select id into existing_track from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-000000000573';
  insert into public.mixtape_tracks(id,mixtape_id,track_uri,position,note)
    values(existing_track,'00000000-0000-4000-9000-000000000573','spotify:track:123',99,'Overwrite attempt')
    on conflict (id) do nothing;
  if (select count(*) from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-000000000573') <> 1
     or (select note from public.mixtape_tracks where id=existing_track) <> 'A personal note'
  then raise exception 'Retry duplicated or overwrote a song'; end if;
  result := public.manage_mixtape_link('00000000-0000-4000-9000-000000000573','status');
  if result <> '{}'::jsonb then raise exception 'Draft leaked'; end if;
  result := public.manage_mixtape_link('00000000-0000-4000-9000-000000000573','publish');
  if length(result->>'token') <> 64 then raise exception 'Invalid token'; end if;
end $test$;
reset role;
update public.mixtapes set title='Later private edit' where id='00000000-0000-4000-9000-000000000573';
do $test$ begin
  if (select snapshot->>'title' from heartable_private.mixtape_links where mixtape_id='00000000-0000-4000-9000-000000000573') <> 'Private draft'
  then raise exception 'Unpublished edit exposed'; end if;
  if has_table_privilege('anon','heartable_private.mixtape_links','select') or has_table_privilege('authenticated','heartable_private.mixtape_links','select')
  then raise exception 'Private link table exposed'; end if;
  if has_function_privilege('anon','public.read_shared_mixtape(text)','execute') or has_function_privilege('authenticated','public.read_shared_mixtape(text)','execute')
  then raise exception 'Bearer endpoint can be bypassed'; end if;
end $test$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000572',true);
set local role authenticated;
do $test$ begin
  delete from public.mixtapes where id='00000000-0000-4000-9000-000000000573';
  if found then raise exception 'Stranger deleted a mixtape'; end if;
  begin
    perform public.manage_mixtape_link('00000000-0000-4000-9000-000000000573','publish');
    raise exception 'Stranger changed sharing';
  exception when raise_exception then
    if sqlerrm <> 'Mixtape unavailable' then raise; end if;
  end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000571',true);
set local role authenticated;
select public.manage_mixtape_link('00000000-0000-4000-9000-000000000573','revoke');
reset role;
do $test$ begin
  if exists(select 1 from heartable_private.mixtape_links where mixtape_id='00000000-0000-4000-9000-000000000573') then raise exception 'Revoke failed'; end if;
end $test$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000571',true);
set local role authenticated;
do $test$ begin
  perform public.manage_mixtape_link('00000000-0000-4000-9000-000000000573','publish');
  delete from public.mixtapes where id='00000000-0000-4000-9000-000000000573'
    and owner='00000000-0000-4000-9000-000000000571';
  if not found then raise exception 'Owner delete failed'; end if;
end $test$;
reset role;
do $test$ begin
  if exists(select 1 from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-000000000573')
     or exists(select 1 from heartable_private.mixtape_links where mixtape_id='00000000-0000-4000-9000-000000000573')
  then raise exception 'Delete did not remove tracks and shared link'; end if;
end $test$;
rollback;
