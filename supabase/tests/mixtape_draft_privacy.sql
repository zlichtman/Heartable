begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-9000-000000000591','heartable-test-mx-owner@example.invalid',now()),
('00000000-0000-4000-9000-000000000592','heartable-test-mx-stranger@example.invalid',now());
insert into public.profiles(user_id,display_name) values
('00000000-0000-4000-9000-000000000591','Owner'),
('00000000-0000-4000-9000-000000000592','Stranger') on conflict(user_id) do nothing;
insert into public.mixtapes(id,owner,title) values
('00000000-0000-4000-9000-0000000006f1','00000000-0000-4000-9000-000000000591','Private draft');
insert into public.mixtape_tracks(mixtape_id,position,track_uri,track_name,artist) values
('00000000-0000-4000-9000-0000000006f1',0,'spotify:track:draft','Draft song','Draft artist');
-- A stranger sees nothing and cannot write.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000592',true);
set local role authenticated;
do $test$ begin
if exists(select 1 from public.mixtapes where id='00000000-0000-4000-9000-0000000006f1')
then raise exception 'Unsent draft readable by a stranger'; end if;
if exists(select 1 from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-0000000006f1')
then raise exception 'Draft tracks readable by a stranger'; end if;
end $test$;
update public.mixtapes set title='Hijacked' where id='00000000-0000-4000-9000-0000000006f1';
delete from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-0000000006f1';
reset role;
do $test$ begin
if (select title from public.mixtapes where id='00000000-0000-4000-9000-0000000006f1') <> 'Private draft'
then raise exception 'Stranger updated a draft'; end if;
if not exists(select 1 from public.mixtape_tracks where mixtape_id='00000000-0000-4000-9000-0000000006f1')
then raise exception 'Stranger deleted draft tracks'; end if;
end $test$;
-- The owner still has full access.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000591',true);
set local role authenticated;
do $test$ begin
if not exists(select 1 from public.mixtapes where id='00000000-0000-4000-9000-0000000006f1')
then raise exception 'Owner lost access to their draft'; end if;
end $test$;
reset role;
rollback;
