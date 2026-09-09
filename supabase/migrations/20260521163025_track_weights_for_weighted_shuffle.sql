-- Per-user per-track shuffle weight. Positive = boost, negative = downvote.
-- The client computes a final weight at shuffle time:
--   base 1 + (user_weight / 10) + min(play_count, 50) / 20
-- so a +10 boost roughly doubles the song's odds, a -10 downvote nearly
-- silences it without removing it.
create table if not exists public.track_weights (
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Provider-native URI. Same shape as play_log.track_uri so they join.
  track_uri text not null,
  weight integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, track_uri),
  check (weight between -100 and 100)
);

alter table public.track_weights enable row level security;

drop policy if exists track_weights_owner_all on public.track_weights;
create policy track_weights_owner_all on public.track_weights
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists track_weights_user_idx
  on public.track_weights (user_id);;
