-- Disposable identities and object metadata only; never touches real user data.
begin;
insert into auth.users(id) values
 ('5c38c601-f08a-42ee-a611-049886760001'),
 ('5c38c601-f08a-42ee-a611-049886760002'),
 ('5c38c601-f08a-42ee-a611-049886760003');
insert into public.friendships(requester_id,addressee_id,status) values
 ('5c38c601-f08a-42ee-a611-049886760001','5c38c601-f08a-42ee-a611-049886760002','accepted');
insert into public.mixtapes(id,owner,title,recipient_id) values
 ('5c38c601-f08a-42ee-a611-049886760011','5c38c601-f08a-42ee-a611-049886760001','Gift fixture','5c38c601-f08a-42ee-a611-049886760002');

set local role authenticated;
select set_config('request.jwt.claim.sub','5c38c601-f08a-42ee-a611-049886760001',true);
insert into storage.objects(bucket_id,name) values ('mixtape-gifts',
 '5c38c601-f08a-42ee-a611-049886760001/5c38c601-f08a-42ee-a611-049886760011/5c38c601-f08a-42ee-a611-049886760021.jpg');
do $$ begin
  begin
    perform public.send_mixtape_gift('5c38c601-f08a-42ee-a611-049886760001','5c38c601-f08a-42ee-a611-049886760011','5c38c601-f08a-42ee-a611-049886760002');
    raise exception 'Empty gift accepted';
  exception when invalid_parameter_value then null; end;
end $$;
insert into public.mixtape_tracks(mixtape_id,track_uri,track_name,note,note_image_url) values
 ('5c38c601-f08a-42ee-a611-049886760011','spotify:track:fixture','Fixture song','A personal note',
 'heartable-media://mixtape-gifts/5c38c601-f08a-42ee-a611-049886760001/5c38c601-f08a-42ee-a611-049886760011/5c38c601-f08a-42ee-a611-049886760021.jpg');

select set_config('request.jwt.claim.sub','5c38c601-f08a-42ee-a611-049886760002',true);
do $$ begin
  if exists(select 1 from public.mixtapes where id='5c38c601-f08a-42ee-a611-049886760011')
    or exists(select 1 from storage.objects where bucket_id='mixtape-gifts' and name like '5c38c601-f08a-42ee-a611-049886760001/%')
  then raise exception 'Recipient can see an unsent draft'; end if;
  begin
    perform public.send_mixtape_gift('5c38c601-f08a-42ee-a611-049886760001','5c38c601-f08a-42ee-a611-049886760011','5c38c601-f08a-42ee-a611-049886760002');
    raise exception 'Wrong-account send accepted';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','5c38c601-f08a-42ee-a611-049886760001',true);
select public.send_mixtape_gift('5c38c601-f08a-42ee-a611-049886760001','5c38c601-f08a-42ee-a611-049886760011','5c38c601-f08a-42ee-a611-049886760002');
select public.send_mixtape_gift('5c38c601-f08a-42ee-a611-049886760001','5c38c601-f08a-42ee-a611-049886760011','5c38c601-f08a-42ee-a611-049886760002');
do $$ begin
  if (select count(*) from public.mixtape_shares where mixtape_id='5c38c601-f08a-42ee-a611-049886760011') <> 1
  then raise exception 'Send is not idempotent'; end if;
end $$;

select set_config('request.jwt.claim.sub','5c38c601-f08a-42ee-a611-049886760002',true);
do $$ begin
  if not exists(select 1 from public.mixtapes where id='5c38c601-f08a-42ee-a611-049886760011' and sent_at is not null)
    or not exists(select 1 from public.mixtape_tracks where mixtape_id='5c38c601-f08a-42ee-a611-049886760011' and note='A personal note')
    or not exists(select 1 from storage.objects where bucket_id='mixtape-gifts' and name like '5c38c601-f08a-42ee-a611-049886760001/%')
  then raise exception 'Delivered gift content is missing'; end if;
  update public.mixtape_tracks set note='Tampered' where mixtape_id='5c38c601-f08a-42ee-a611-049886760011';
  if exists(select 1 from public.mixtape_tracks where note='Tampered') then raise exception 'Recipient edited gift'; end if;
end $$;
select set_config('request.jwt.claim.sub','5c38c601-f08a-42ee-a611-049886760003',true);
do $$ begin
  if exists(select 1 from public.mixtapes where id='5c38c601-f08a-42ee-a611-049886760011')
    or exists(select 1 from storage.objects where bucket_id='mixtape-gifts' and name like '5c38c601-f08a-42ee-a611-049886760001/%')
  then raise exception 'Unrelated account can see gift'; end if;
end $$;
reset role;
do $$ begin
  if (select public from storage.buckets where id='mixtape-gifts') then raise exception 'Gift media bucket is public'; end if;
  if has_function_privilege('anon','public.send_mixtape_gift(uuid,uuid,uuid)','EXECUTE') then raise exception 'Anonymous send is exposed'; end if;
end $$;
rollback;
