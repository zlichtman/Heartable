drop function if exists find_profile(text);
create or replace function find_profile(p_query text)
returns table(user_id uuid, display_name text, spotify_id text, avatar_url text)
language sql security definer set search_path = public as $$
  select user_id, display_name, spotify_id, avatar_url
    from profiles
   where handle = lower(trim(p_query))
      or share_code = trim(p_query)
      or spotify_id ilike '%' || trim(p_query) || '%'
      or display_name ilike '%' || trim(p_query) || '%'
   order by (handle = lower(trim(p_query))) desc,
            (share_code = trim(p_query)) desc
   limit 12
$$;
revoke all on function find_profile(text) from public;
revoke execute on function find_profile(text) from anon;
grant execute on function find_profile(text) to authenticated;;
