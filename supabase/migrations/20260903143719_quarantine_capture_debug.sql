-- This untracked diagnostic table is not used by any Heartable client or
-- migration, but existed in production with RLS disabled and broad default
-- Data API grants. Preserve its three rows for owner review while removing all
-- public/client access. It can be exported and dropped in a later, explicitly
-- destructive maintenance migration.
revoke all privileges on table public.capture_debug from anon, authenticated;
alter table public.capture_debug enable row level security;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC unless it is explicitly
-- revoked. These RPC/helper functions were intended for signed-in Heartable
-- accounts, but later CREATE OR REPLACE migrations reintroduced the inherited
-- anonymous grant. Keep the authenticated app contract and close the public path.
revoke execute on function public.are_friends(uuid, uuid) from public, anon;
revoke execute on function public.find_profile(text) from public, anon;
revoke execute on function public.song_leaderboard(integer) from public, anon;

grant execute on function public.are_friends(uuid, uuid) to authenticated;
grant execute on function public.find_profile(text) to authenticated;
grant execute on function public.song_leaderboard(integer) to authenticated;
