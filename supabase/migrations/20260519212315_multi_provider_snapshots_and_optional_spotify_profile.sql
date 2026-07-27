-- Tag every snapshot row with the music service it came from.
-- Existing rows are Spotify-only, so the default 'spotify' preserves them.
alter table public.snapshot_playlists
  add column if not exists provider_id text not null default 'spotify';

alter table public.snapshot_tracks
  add column if not exists provider_id text not null default 'spotify';

alter table public.snapshot_liked_tracks
  add column if not exists provider_id text not null default 'spotify';

-- Record which providers contributed to a snapshot, so the UI can show badges
-- without having to scan child rows.
alter table public.library_snapshots
  add column if not exists providers text[] not null default array['spotify']::text[];

create index if not exists snapshot_playlists_provider_idx
  on public.snapshot_playlists (snapshot_id, provider_id);
create index if not exists snapshot_liked_tracks_provider_idx
  on public.snapshot_liked_tracks (snapshot_id, provider_id);
create index if not exists snapshot_tracks_provider_idx
  on public.snapshot_tracks (snapshot_playlist_id, provider_id);

-- Allow profiles without a Spotify account (email-only signups).
-- The UNIQUE constraint stays; Postgres treats multiple NULLs as distinct.
alter table public.profiles
  alter column spotify_id drop not null;;
