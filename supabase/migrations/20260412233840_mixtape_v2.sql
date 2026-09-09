-- Drop old
drop table if exists mixtape_notes cascade;
drop table if exists mixtape_tracks cascade;
drop table if exists track_segments cascade;
drop table if exists track_versions cascade;
drop table if exists mixtape_images cascade;
drop table if exists mixtapes cascade;
drop table if exists cached_tracks cascade;
drop table if exists cached_audio_features cascade;

-- Cache layer
create table cached_tracks (
  uri           text primary key,
  name          text not null,
  artists       text not null,
  album_name    text,
  album_art_url text,
  duration_ms   int  not null,
  preview_url   text,
  fetched_at    timestamptz not null default now()
);

create table cached_audio_features (
  uri              text primary key,
  tempo            real,
  energy           real,
  valence          real,
  danceability     real,
  acousticness     real,
  instrumentalness real,
  loudness         real,
  fetched_at       timestamptz not null default now()
);

alter table cached_tracks         enable row level security;
alter table cached_audio_features enable row level security;
create policy "cache_tracks_read"   on cached_tracks          for select using (true);
create policy "cache_tracks_write"  on cached_tracks          for insert with check (true);
create policy "cache_tracks_update" on cached_tracks          for update using (true);
create policy "cache_af_read"       on cached_audio_features  for select using (true);
create policy "cache_af_write"      on cached_audio_features  for insert with check (true);
create policy "cache_af_update"     on cached_audio_features  for update using (true);

-- Mixtapes
create table mixtapes (
  id                   uuid primary key default gen_random_uuid(),
  user_id              text not null,
  name                 text not null default '',
  theme                text not null default 'rose',
  message              text not null default '',
  recipient_name       text,
  cover_image_url      text,
  background_image_url text,
  share_token          text not null unique default encode(gen_random_bytes(16), 'hex'),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index mixtapes_user_idx on mixtapes(user_id);
create index mixtapes_share_idx on mixtapes(share_token);

create table track_versions (
  id            uuid primary key default gen_random_uuid(),
  user_id       text not null,
  track_uri     text not null,
  label         text not null default 'Custom',
  trim_start_ms int  not null default 0,
  trim_end_ms   int,
  skip_regions  jsonb not null default '[]'::jsonb,
  fade_in_ms    int  not null default 0,
  fade_out_ms   int  not null default 0,
  created_at    timestamptz not null default now()
);

create index track_versions_user_track_idx on track_versions(user_id, track_uri);

create table mixtape_tracks (
  id             uuid primary key default gen_random_uuid(),
  mixtape_id     uuid not null references mixtapes(id) on delete cascade,
  position       int  not null,
  track_uri      text not null,
  version_id     uuid references track_versions(id) on delete set null,
  trim_start_ms  int,
  trim_end_ms    int,
  skip_regions   jsonb,
  fade_in_ms     int,
  fade_out_ms    int
);

create index mixtape_tracks_mixtape_idx on mixtape_tracks(mixtape_id, position);

create table mixtape_notes (
  id           uuid primary key default gen_random_uuid(),
  mixtape_id   uuid not null references mixtapes(id) on delete cascade,
  track_uri    text not null,
  timestamp_ms int  not null,
  duration_ms  int  not null default 5000,
  text         text not null default '',
  color        text not null default 'rose',
  emoji        text,
  image_url    text,
  visual_type  text
);

create index mixtape_notes_mixtape_idx on mixtape_notes(mixtape_id);

create table mixtape_images (
  id         uuid primary key default gen_random_uuid(),
  mixtape_id uuid not null references mixtapes(id) on delete cascade,
  position   int  not null default 0,
  image_url  text not null,
  caption    text
);

create index mixtape_images_mixtape_idx on mixtape_images(mixtape_id);

alter table mixtapes        enable row level security;
alter table mixtape_tracks  enable row level security;
alter table mixtape_notes   enable row level security;
alter table mixtape_images  enable row level security;
alter table track_versions  enable row level security;

create policy "mx_all"  on mixtapes        for all using (true) with check (true);
create policy "mxt_all" on mixtape_tracks  for all using (true) with check (true);
create policy "mxn_all" on mixtape_notes   for all using (true) with check (true);
create policy "mxi_all" on mixtape_images  for all using (true) with check (true);
create policy "tv_all"  on track_versions  for all using (true) with check (true);;
