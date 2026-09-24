insert into storage.buckets (id, name, public)
values ('mixtape-media', 'mixtape-media', true)
on conflict (id) do update set public = true;

drop policy if exists mxmedia_read on storage.objects;
drop policy if exists mxmedia_write on storage.objects;
drop policy if exists mxmedia_update on storage.objects;
drop policy if exists mxmedia_delete on storage.objects;

create policy mxmedia_read on storage.objects for select
  using (bucket_id = 'mixtape-media');
create policy mxmedia_write on storage.objects for insert to authenticated
  with check (bucket_id = 'mixtape-media'
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy mxmedia_update on storage.objects for update to authenticated
  using (bucket_id = 'mixtape-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy mxmedia_delete on storage.objects for delete to authenticated
  using (bucket_id = 'mixtape-media' and (storage.foldername(name))[1] = auth.uid()::text);;
