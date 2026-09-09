-- Cover art so history rows render properly. Stays nullable so existing
-- rows aren't broken; clients backfill it on future plays.
alter table public.play_log
  add column if not exists album_art text;;
