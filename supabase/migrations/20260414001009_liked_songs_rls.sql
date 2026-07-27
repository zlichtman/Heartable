alter table snapshot_liked_tracks enable row level security;

create policy "Anyone can insert snap liked"
  on snapshot_liked_tracks for insert with check (true);

create policy "Anyone can read snap liked"
  on snapshot_liked_tracks for select using (true);

create policy "Anyone can update snap liked"
  on snapshot_liked_tracks for update using (true);

create policy "Anyone can delete snap liked"
  on snapshot_liked_tracks for delete using (true);;
