-- Spotify-style playlist folders. Folders are a Heartable-local construct (no
-- music provider exposes folders via API), so we own them. A folder groups
-- unified playlists keyed by `${providerId}:${playlistId}`. We snapshot the
-- playlist name/image/owner on the item so the folder renders without a live
-- provider fetch.

create table if not exists public.playlist_folders (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.playlist_folder_items (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid not null references public.playlist_folders (id) on delete cascade,
  playlist_key text not null,
  provider_id text not null,
  playlist_id text not null,
  name text not null default '',
  image text,
  owner_name text,
  track_count int not null default 0,
  added_at timestamptz not null default now(),
  unique (folder_id, playlist_key)
);

create index if not exists playlist_folders_owner_idx on public.playlist_folders (owner);
create index if not exists playlist_folder_items_folder_idx on public.playlist_folder_items (folder_id);

alter table public.playlist_folders enable row level security;
alter table public.playlist_folder_items enable row level security;

-- Folders: owner-scoped CRUD.
create policy "folders_select_own" on public.playlist_folders
  for select using (owner = auth.uid());
create policy "folders_insert_own" on public.playlist_folders
  for insert with check (owner = auth.uid());
create policy "folders_update_own" on public.playlist_folders
  for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "folders_delete_own" on public.playlist_folders
  for delete using (owner = auth.uid());

-- Items: scoped through the parent folder's owner.
create policy "folder_items_select_own" on public.playlist_folder_items
  for select using (
    exists (
      select 1 from public.playlist_folders f
      where f.id = folder_id and f.owner = auth.uid()
    )
  );
create policy "folder_items_insert_own" on public.playlist_folder_items
  for insert with check (
    exists (
      select 1 from public.playlist_folders f
      where f.id = folder_id and f.owner = auth.uid()
    )
  );
create policy "folder_items_delete_own" on public.playlist_folder_items
  for delete using (
    exists (
      select 1 from public.playlist_folders f
      where f.id = folder_id and f.owner = auth.uid()
    )
  );;
