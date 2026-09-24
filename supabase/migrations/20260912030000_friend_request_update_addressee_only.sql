-- Only the addressee of a pending request may change its status. The previous
-- policy also let the requester update the row, so a direct API call could
-- accept one's own outgoing request and unlock friend-only messages, activity
-- and gifts without consent. Cancelling an outgoing request remains a delete.
drop policy if exists fr_upd on public.friendships;
create policy fr_upd on public.friendships for update to authenticated
  using (addressee_id = (select auth.uid()) and status = 'pending')
  with check (addressee_id = (select auth.uid()) and status in ('accepted', 'declined'));
