create table if not exists now_playing (
  user_id     uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  track_name  text, artist text, album text,
  album_art   text, track_uri text,
  is_playing  boolean not null default false,
  progress_ms int, duration_ms int,
  updated_at  timestamptz not null default now()
);
alter table now_playing enable row level security;
create policy np_sel on now_playing for select using (
  user_id = auth.uid()
  or exists (select 1 from friendships f where f.status='accepted'
     and ((f.requester_id=auth.uid() and f.addressee_id=now_playing.user_id)
       or (f.addressee_id=auth.uid() and f.requester_id=now_playing.user_id)))
);
create policy np_ins on now_playing for insert with check (user_id = auth.uid());
create policy np_upd on now_playing for update using (user_id = auth.uid()) with check (user_id = auth.uid());;
