-- Public buckets for profile avatars + mixtape covers. RLS policies on
-- storage.objects already scope writes to the user's own {uid}/ folder and
-- allow public read; the buckets themselves were missing, so uploads 400'd.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('mixtape-media', 'mixtape-media', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public;;
