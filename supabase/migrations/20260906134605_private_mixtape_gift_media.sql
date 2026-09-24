-- A gift starts as an owner-only draft. Recipient access is granted only by Send.
alter table public.mixtapes add column recipient_id uuid references auth.users(id) on delete set null;
alter table public.mixtapes add column sent_at timestamptz;
create index mixtapes_owner_recipient_idx on public.mixtapes(owner, recipient_id);

create function public.send_mixtape_gift(expected_owner uuid, target_mixtape uuid, target_friend uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare tape public.mixtapes;
begin
  if auth.uid() is null or auth.uid() <> expected_owner then
    raise exception 'Account changed. Sign in again.' using errcode = '42501';
  end if;
  select * into tape from public.mixtapes m
    where m.id = target_mixtape and m.owner = expected_owner for update;
  if not found or target_friend = expected_owner or target_friend is null then
    raise exception 'Mixtape unavailable.' using errcode = '42501';
  end if;
  if tape.recipient_id is not null and tape.recipient_id <> target_friend then
    raise exception 'This draft is for another friend.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.friendships f where f.status = 'accepted'
    and ((f.requester_id = expected_owner and f.addressee_id = target_friend)
      or (f.addressee_id = expected_owner and f.requester_id = target_friend))) then
    raise exception 'Add this person as a friend first.' using errcode = '42501';
  end if;
  if nullif(btrim(tape.title), '') is null
    or not exists (select 1 from public.mixtape_tracks t where t.mixtape_id = target_mixtape) then
    raise exception 'Add a title and at least one song before sending.' using errcode = '22023';
  end if;
  insert into public.mixtape_shares(mixtape_id, shared_with, owner)
    values(target_mixtape, target_friend, expected_owner)
    on conflict (mixtape_id, shared_with) do nothing;
  update public.mixtapes set recipient_id = target_friend,
    sent_at = coalesce(sent_at, now()), updated_at = now() where id = target_mixtape;
end $$;
revoke all on function public.send_mixtape_gift(uuid,uuid,uuid) from public, anon;
grant execute on function public.send_mixtape_gift(uuid,uuid,uuid) to authenticated;

-- Existing legacy cover URLs remain intact. All new covers/note photos use a
-- private bucket with short-lived signed display URLs, never public URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mixtape-gifts','mixtape-gifts',false,5242880,array['image/jpeg'])
on conflict (id) do update set public=false, file_size_limit=5242880, allowed_mime_types=array['image/jpeg'];

create policy gift_media_read on storage.objects for select to authenticated using (
  bucket_id = 'mixtape-gifts' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.mixtapes m
      where m.id::text = (storage.foldername(name))[2]
        and m.owner::text = (storage.foldername(name))[1])
  )
);
create policy gift_media_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'mixtape-gifts'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (select 1 from public.mixtapes m where m.owner = (select auth.uid())
    and m.id::text = (storage.foldername(name))[2])
);
create policy gift_media_delete on storage.objects for delete to authenticated using (
  bucket_id = 'mixtape-gifts' and (storage.foldername(name))[1] = (select auth.uid())::text
);
