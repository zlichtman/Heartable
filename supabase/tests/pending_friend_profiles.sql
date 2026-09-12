begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-9000-000000000571','heartable-test-requester@example.invalid',now()),
('00000000-0000-4000-9000-000000000572','heartable-test-addressee@example.invalid',now()),
('00000000-0000-4000-9000-000000000573','heartable-test-stranger@example.invalid',now()),
('00000000-0000-4000-9000-000000000574','heartable-test-declined@example.invalid',now());
insert into public.profiles(user_id,display_name) values
('00000000-0000-4000-9000-000000000571','Test Requester'),
('00000000-0000-4000-9000-000000000572','Test Addressee'),
('00000000-0000-4000-9000-000000000573','Test Stranger'),
('00000000-0000-4000-9000-000000000574','Test Declined') on conflict(user_id) do nothing;
insert into public.friendships(requester_id,addressee_id,status) values
('00000000-0000-4000-9000-000000000571','00000000-0000-4000-9000-000000000572','pending'),
('00000000-0000-4000-9000-000000000571','00000000-0000-4000-9000-000000000574','declined');
-- The requester sees the person they asked, not strangers or declined rows.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000571',true);
set local role authenticated;
do $test$ begin
if not exists(select 1 from public.profiles where user_id='00000000-0000-4000-9000-000000000572')
then raise exception 'Requester cannot read the pending addressee profile'; end if;
if exists(select 1 from public.profiles where user_id='00000000-0000-4000-9000-000000000573')
then raise exception 'Stranger profile exposed to requester'; end if;
if exists(select 1 from public.profiles where user_id='00000000-0000-4000-9000-000000000574')
then raise exception 'Declined profile exposed to requester'; end if;
end $test$;
reset role;
-- The addressee sees who asked them.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000572',true);
set local role authenticated;
do $test$ begin
if not exists(select 1 from public.profiles where user_id='00000000-0000-4000-9000-000000000571')
then raise exception 'Addressee cannot read the pending requester profile'; end if;
if exists(select 1 from public.profiles where user_id='00000000-0000-4000-9000-000000000573')
then raise exception 'Stranger profile exposed to addressee'; end if;
end $test$;
reset role;
-- A stranger still sees neither party.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000573',true);
set local role authenticated;
do $test$ begin
if exists(select 1 from public.profiles where user_id in
('00000000-0000-4000-9000-000000000571','00000000-0000-4000-9000-000000000572'))
then raise exception 'Pending friendship exposed profiles to a stranger'; end if;
end $test$;
reset role;
rollback;
