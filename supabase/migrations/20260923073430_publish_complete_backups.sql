-- Existing snapshots and older clients keep their current behavior. New clients
-- explicitly insert false and publish true only after all playlist/song batches
-- have landed. A killed upload remains pending rather than becoming a baseline.
alter table public.library_snapshots
  add column capture_complete boolean not null default true;

comment on column public.library_snapshots.capture_complete is
  'New captures remain false until every child insert succeeds; only complete captures appear in history or count as an initial backup.';
