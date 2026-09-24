create table if not exists mixtapes (
  id          uuid primary key default gen_random_uuid(),
  owner       uuid not null references auth.users(id) on delete cascade default auth.uid(),
  title       text not null default 'Untitled mixtape',
  description text default '',
  cover_url   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create table if not exists mixtape_tracks (
  id            uuid primary key default gen_random_uuid(),
  mixtape_id    uuid not null references mixtapes(id) on delete cascade,
  position      int not null default 0,
  track_uri     text not null,
  track_name    text,
  artist        text,
  album_art     text,
  duration_ms   int,
  skip_regions  jsonb not null default '[]'::jsonb,
  note          text default '',
  note_image_url text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_mt_tracks_mix on mixtape_tracks(mixtape_id, position);
create table if not exists mixtape_shares (
  id          uuid primary key default gen_random_uuid(),
  mixtape_id  uuid not null references mixtapes(id) on delete cascade,
  shared_with uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (mixtape_id, shared_with)
);
create index if not exists idx_mt_shares_with on mixtape_shares(shared_with);

alter table mixtapes enable row level security;
alter table mixtape_tracks enable row level security;
alter table mixtape_shares enable row level security;

create policy mx_sel on mixtapes for select using (
  owner = auth.uid()
  or exists (select 1 from mixtape_shares s where s.mixtape_id = mixtapes.id and s.shared_with = auth.uid())
);
create policy mx_ins on mixtapes for insert with check (owner = auth.uid());
create policy mx_upd on mixtapes for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy mx_del on mixtapes for delete using (owner = auth.uid());

create policy mxt_sel on mixtape_tracks for select using (
  exists (select 1 from mixtapes m where m.id = mixtape_tracks.mixtape_id
    and (m.owner = auth.uid()
      or exists (select 1 from mixtape_shares s where s.mixtape_id = m.id and s.shared_with = auth.uid())))
);
create policy mxt_wr on mixtape_tracks for all using (
  exists (select 1 from mixtapes m where m.id = mixtape_tracks.mixtape_id and m.owner = auth.uid())
) with check (
  exists (select 1 from mixtapes m where m.id = mixtape_tracks.mixtape_id and m.owner = auth.uid())
);

create policy mxs_sel on mixtape_shares for select using (
  shared_with = auth.uid()
  or exists (select 1 from mixtapes m where m.id = mixtape_shares.mixtape_id and m.owner = auth.uid())
);
create policy mxs_wr on mixtape_shares for all using (
  exists (select 1 from mixtapes m where m.id = mixtape_shares.mixtape_id and m.owner = auth.uid())
) with check (
  exists (select 1 from mixtapes m where m.id = mixtape_shares.mixtape_id and m.owner = auth.uid())
);;
