begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-9000-000000000561','heartable-test-caller@example.invalid',now()),
('00000000-0000-4000-9000-000000000562','heartable-test-match@example.invalid',now()),
('00000000-0000-4000-9000-000000000563','heartable-test-unverified@example.invalid',null);
insert into public.profiles(user_id,display_name) values
('00000000-0000-4000-9000-000000000561','Test Caller'),
('00000000-0000-4000-9000-000000000562','Test Match'),
('00000000-0000-4000-9000-000000000563','Test Unverified') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000561',true);
set local role authenticated;
do $test$
declare matches integer;
begin
select count(*) into matches from public.match_contact_emails(array[
encode(extensions.digest('heartable-test-match@example.invalid','sha256'),'hex'),
encode(extensions.digest('heartable-test-caller@example.invalid','sha256'),'hex'),
encode(extensions.digest('heartable-test-unverified@example.invalid','sha256'),'hex')]);
if matches <> 1 then raise exception 'Expected one verified non-self match, got %', matches; end if;
begin
perform * from public.match_contact_emails(array[repeat('a',64)]);
raise exception 'Throttle failed';
exception when raise_exception then
if sqlerrm <> 'Please wait one minute before searching again' then raise; end if;
end;
end $test$;
reset role;
delete from heartable_private.contact_lookup_runs where user_id='00000000-0000-4000-9000-000000000561';
insert into public.friendships(requester_id,addressee_id,status) values
('00000000-0000-4000-9000-000000000562','00000000-0000-4000-9000-000000000561','blocked');
set local role authenticated;
do $test$ begin
if exists(select 1 from public.match_contact_emails(array[
encode(extensions.digest('heartable-test-match@example.invalid','sha256'),'hex')]))
then raise exception 'Blocked account exposed'; end if;
end $test$;
reset role;
do $test$ begin
if has_function_privilege('anon','public.match_contact_emails(text[])','execute')
then raise exception 'Anonymous access is not blocked'; end if;
if has_table_privilege('authenticated','heartable_private.contact_lookup_runs','select')
then raise exception 'Private throttle exposed'; end if;
end $test$;
rollback;
