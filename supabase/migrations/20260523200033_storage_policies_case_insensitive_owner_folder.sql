-- Swift's UUID.uuidString is UPPERCASE; Postgres auth.uid()::text is lowercase.
-- The owner-folder check compared them directly, so writes to {UID}/... failed
-- RLS. Recreate avatars + mixtape-media write policies with a case-insensitive
-- folder comparison and proper WITH CHECK on UPDATE (upsert hits update).

-- avatars
drop policy if exists avatars_owner_insert on storage.objects;
drop policy if exists avatars_owner_update on storage.objects;
drop policy if exists avatars_owner_delete on storage.objects;

create policy avatars_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));
create policy avatars_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text))
  with check (bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));
create policy avatars_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

-- mixtape-media
drop policy if exists mxmedia_write on storage.objects;
drop policy if exists mxmedia_update on storage.objects;
drop policy if exists mxmedia_delete on storage.objects;
drop policy if exists "Anyone can upload mixtape images" on storage.objects;

create policy mxmedia_write on storage.objects for insert to authenticated
  with check (bucket_id = 'mixtape-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));
create policy mxmedia_update on storage.objects for update to authenticated
  using (bucket_id = 'mixtape-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text))
  with check (bucket_id = 'mixtape-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));
create policy mxmedia_delete on storage.objects for delete to authenticated
  using (bucket_id = 'mixtape-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));;
