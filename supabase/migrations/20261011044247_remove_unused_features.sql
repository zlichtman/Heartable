-- Direct messaging, contact discovery, invite codes, weighted shuffle, and
-- capture debugging are no longer part of the app.
drop table public.messages;

drop function public.match_contact_emails(text[]);
drop function heartable_private.match_contact_emails(text[]);
drop table heartable_private.contact_lookup_runs;

drop table public.track_weights;
drop table public.capture_debug;

-- People search matches a handle, Spotify ID, or display name.
create or replace function public.find_profile(p_query text)
returns table(
  user_id uuid,
  display_name text,
  spotify_id text,
  avatar_url text,
  matched_provider text,
  matched_handle text
)
language sql
security definer
set search_path to 'public'
as $$
  with q as (select trim(p_query) as raw, lower(trim(p_query)) as lower)
  select
    p.user_id,
    p.display_name,
    p.spotify_id,
    p.avatar_url,
    case
      when p.handle = q.lower then 'handle'
      when p.spotify_id ilike '%' || q.raw || '%' then 'spotify'
      else 'name'
    end as matched_provider,
    coalesce(p.handle, p.spotify_id, p.display_name) as matched_handle
  from profiles p, q
  where p.handle = q.lower
     or p.spotify_id ilike '%' || q.raw || '%'
     or p.display_name ilike '%' || q.raw || '%'
  order by matched_provider, matched_handle
  limit 24
$$;

drop table public.profile_links;
alter table public.profiles drop column share_code;
alter table public.library_snapshots drop column debug;
