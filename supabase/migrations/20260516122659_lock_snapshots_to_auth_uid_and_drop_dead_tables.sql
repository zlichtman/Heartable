-- 1. Remove dead tables (mixtapes feature removed; caches were mixtape/visualizer only).
drop table if exists public.mixtape_notes cascade;
drop table if exists public.mixtape_images cascade;
drop table if exists public.mixtape_tracks cascade;
drop table if exists public.mixtapes cascade;
drop table if exists public.track_versions cascade;
drop table if exists public.cached_tracks cascade;
drop table if exists public.cached_audio_features cascade;

-- 2. Tie snapshots to the authenticated Supabase user.
alter table public.library_snapshots
  add column if not exists owner uuid references auth.users(id) on delete cascade;
create index if not exists library_snapshots_owner_idx on public.library_snapshots(owner);

-- 3. Drop the wide-open "anyone" policies.
drop policy if exists "Anyone can read snapshots"   on public.library_snapshots;
drop policy if exists "Anyone can insert snapshots" on public.library_snapshots;
drop policy if exists "Anyone can update snapshots" on public.library_snapshots;
drop policy if exists "Anyone can delete snapshots" on public.library_snapshots;
drop policy if exists "Anyone can read snap playlists"   on public.snapshot_playlists;
drop policy if exists "Anyone can insert snap playlists" on public.snapshot_playlists;
drop policy if exists "Anyone can update snap playlists" on public.snapshot_playlists;
drop policy if exists "Anyone can delete snap playlists" on public.snapshot_playlists;
drop policy if exists "Anyone can read snap tracks"   on public.snapshot_tracks;
drop policy if exists "Anyone can insert snap tracks" on public.snapshot_tracks;
drop policy if exists "Anyone can update snap tracks" on public.snapshot_tracks;
drop policy if exists "Anyone can delete snap tracks" on public.snapshot_tracks;
drop policy if exists "Anyone can read snap liked"   on public.snapshot_liked_tracks;
drop policy if exists "Anyone can insert snap liked" on public.snapshot_liked_tracks;
drop policy if exists "Anyone can update snap liked" on public.snapshot_liked_tracks;
drop policy if exists "Anyone can delete snap liked" on public.snapshot_liked_tracks;

-- 4. Per-user policies. Edge functions use the service role and bypass RLS,
--    so writes from snapshot-library/restore-snapshot keep working; these
--    policies govern the anon-key client (the app).
create policy snap_owner_all on public.library_snapshots
  for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

create policy snap_pl_owner_all on public.snapshot_playlists
  for all to authenticated
  using (exists (select 1 from public.library_snapshots s
                 where s.id = snapshot_playlists.snapshot_id and s.owner = auth.uid()))
  with check (exists (select 1 from public.library_snapshots s
                 where s.id = snapshot_playlists.snapshot_id and s.owner = auth.uid()));

create policy snap_tr_owner_all on public.snapshot_tracks
  for all to authenticated
  using (exists (select 1 from public.snapshot_playlists p
                 join public.library_snapshots s on s.id = p.snapshot_id
                 where p.id = snapshot_tracks.snapshot_playlist_id and s.owner = auth.uid()))
  with check (exists (select 1 from public.snapshot_playlists p
                 join public.library_snapshots s on s.id = p.snapshot_id
                 where p.id = snapshot_tracks.snapshot_playlist_id and s.owner = auth.uid()));

create policy snap_liked_owner_all on public.snapshot_liked_tracks
  for all to authenticated
  using (exists (select 1 from public.library_snapshots s
                 where s.id = snapshot_liked_tracks.snapshot_id and s.owner = auth.uid()))
  with check (exists (select 1 from public.library_snapshots s
                 where s.id = snapshot_liked_tracks.snapshot_id and s.owner = auth.uid()));;
