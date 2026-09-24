-- A pending friend request must show who it is with. Both parties of a pending
-- friendship can read each other's profile row (name, handle, avatar), exactly as
-- accepted friends already can. Declined and blocked rows grant nothing.
drop policy if exists prof_sel on public.profiles;
create policy prof_sel on public.profiles for select using (
  user_id = auth.uid()
  or exists (
    select 1 from public.friendships f
     where f.status in ('accepted', 'pending')
       and ((f.requester_id = auth.uid() and f.addressee_id = profiles.user_id)
         or (f.addressee_id = auth.uid() and f.requester_id = profiles.user_id))
  )
);
