create table if not exists track_skip_versions (
  id                uuid primary key default gen_random_uuid(),
  owner             uuid not null references auth.users(id) on delete cascade default auth.uid(),
  spotify_track_uri text not null,
  label             text not null default 'Version',
  skip_regions      jsonb not null default '[]'::jsonb,
  fade_in_ms        int not null default 0,
  fade_out_ms       int not null default 0,
  is_active         boolean not null default false,
  created_at        timestamptz not null default now()
);
create index if not exists idx_tsv_owner_uri on track_skip_versions(owner, spotify_track_uri);
create unique index if not exists uq_tsv_active on track_skip_versions(owner, spotify_track_uri) where is_active;
alter table track_skip_versions enable row level security;
create policy tsv_sel on track_skip_versions for select using (owner = auth.uid());
create policy tsv_ins on track_skip_versions for insert with check (owner = auth.uid());
create policy tsv_upd on track_skip_versions for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy tsv_del on track_skip_versions for delete using (owner = auth.uid());;
