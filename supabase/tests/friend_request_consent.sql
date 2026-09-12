begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-9000-000000000581','heartable-test-fr-requester@example.invalid',now()),
('00000000-0000-4000-9000-000000000582','heartable-test-fr-addressee@example.invalid',now());
insert into public.profiles(user_id,display_name) values
('00000000-0000-4000-9000-000000000581','Requester'),
('00000000-0000-4000-9000-000000000582','Addressee') on conflict(user_id) do nothing;
insert into public.friendships(id,requester_id,addressee_id,status) values
('00000000-0000-4000-9000-0000000005f1','00000000-0000-4000-9000-000000000581','00000000-0000-4000-9000-000000000582','pending');
-- The requester cannot accept their own request.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000581',true);
set local role authenticated;
update public.friendships set status='accepted' where id='00000000-0000-4000-9000-0000000005f1';
reset role;
do $test$ begin
if (select status from public.friendships where id='00000000-0000-4000-9000-0000000005f1') <> 'pending'
then raise exception 'Requester accepted their own friend request'; end if;
end $test$;
-- The addressee can.
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000582',true);
set local role authenticated;
update public.friendships set status='accepted' where id='00000000-0000-4000-9000-0000000005f1';
reset role;
do $test$ begin
if (select status from public.friendships where id='00000000-0000-4000-9000-0000000005f1') <> 'accepted'
then raise exception 'Addressee could not accept the request'; end if;
end $test$;
rollback;
