-- Heartable accounts exist independently of Spotify, so profile creation and
-- profile edits must never require a Spotify identity. Reassert this in a new
-- migration in case an older environment missed the original rollout.
alter table public.profiles
  alter column spotify_id drop not null;

-- Public profile curation is a small, versioned JSON document stored beside the
-- user's avatar. The original bucket allowed images only, which caused every
-- featured-playlist and profile-layout save to fail at the storage boundary.
update storage.buckets
set allowed_mime_types = array[
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/json'
]
where id = 'avatars';
