create table if not exists public.profile_links (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_id text not null,
  handle text not null,
  display_name text,
  updated_at timestamptz not null default now(),
  primary key (user_id, provider_id)
);

alter table public.profile_links enable row level security;

drop policy if exists profile_links_self_write on public.profile_links;
create policy profile_links_self_write on public.profile_links
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists profile_links_authenticated_select on public.profile_links;
create policy profile_links_authenticated_select on public.profile_links
  for select
  to authenticated
  using (true);

create index if not exists profile_links_handle_idx
  on public.profile_links (lower(handle));

-- Drop and recreate to allow the return-type change.
drop function if exists public.find_profile(text);

create function public.find_profile(p_query text)
returns table (
  user_id uuid,
  display_name text,
  spotify_id text,
  avatar_url text,
  matched_provider text,
  matched_handle text
)
language sql
security definer
set search_path = public
as $$
  with q as (select trim(p_query) as raw, lower(trim(p_query)) as lower)
  select
    p.user_id,
    p.display_name,
    p.spotify_id,
    p.avatar_url,
    case
      when p.handle = q.lower then 'handle'
      when p.share_code = q.raw then 'invite_code'
      when p.spotify_id ilike '%' || q.raw || '%' then 'spotify'
      else 'name'
    end as matched_provider,
    coalesce(p.handle, p.spotify_id, p.display_name) as matched_handle
  from profiles p, q
  where p.handle = q.lower
     or p.share_code = q.raw
     or p.spotify_id ilike '%' || q.raw || '%'
     or p.display_name ilike '%' || q.raw || '%'
  union
  select
    pl.user_id,
    p.display_name,
    p.spotify_id,
    p.avatar_url,
    pl.provider_id as matched_provider,
    pl.handle as matched_handle
  from profile_links pl
  join profiles p on p.user_id = pl.user_id
  cross join q
  where lower(pl.handle) like '%' || q.lower || '%'
  order by matched_provider, matched_handle
  limit 24
$$;

grant execute on function public.find_profile(text) to authenticated;;
