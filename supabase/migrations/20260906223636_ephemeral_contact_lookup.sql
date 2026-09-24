create schema if not exists heartable_private;
revoke all on schema heartable_private from public, anon;
grant usage on schema heartable_private to authenticated;

-- Stores only a per-account throttle timestamp, never contact data or matches.
create table if not exists heartable_private.contact_lookup_runs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_run timestamptz not null
);
alter table heartable_private.contact_lookup_runs enable row level security;
revoke all on heartable_private.contact_lookup_runs from public, anon, authenticated;

create or replace function heartable_private.match_contact_emails(p_hashes text[])
returns table(user_id uuid, display_name text, spotify_id text, avatar_url text)
language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if coalesce(cardinality(p_hashes), 0) > 5000
     or exists(select 1 from unnest(p_hashes) h where h is null or h !~ '^[0-9a-f]{64}$')
  then raise exception 'Invalid contact lookup'; end if;
  if coalesce(cardinality(p_hashes), 0) = 0 then return; end if;
  insert into heartable_private.contact_lookup_runs as r(user_id, last_run)
  values(caller, clock_timestamp())
  on conflict on constraint contact_lookup_runs_pkey do update set last_run = excluded.last_run
  where r.last_run < clock_timestamp() - interval '1 minute';
  if not found then raise exception 'Please wait one minute before searching again'; end if;
  return query
  select p.user_id, p.display_name, p.spotify_id, p.avatar_url
  from auth.users u join public.profiles p on p.user_id = u.id
  where u.id <> caller and u.deleted_at is null and u.email_confirmed_at is not null
    and encode(extensions.digest(lower(btrim(u.email)), 'sha256'), 'hex') = any(p_hashes)
    and not exists (
      select 1 from public.friendships f where f.status = 'blocked'
      and ((f.requester_id = caller and f.addressee_id = u.id)
        or (f.addressee_id = caller and f.requester_id = u.id))
    )
  order by p.display_name nulls last, p.user_id;
end $$;
revoke all on function heartable_private.match_contact_emails(text[]) from public, anon;
grant execute on function heartable_private.match_contact_emails(text[]) to authenticated;

create or replace function public.match_contact_emails(p_hashes text[])
returns table(user_id uuid, display_name text, spotify_id text, avatar_url text)
language sql security invoker set search_path = '' as $$
  select * from heartable_private.match_contact_emails(p_hashes);
$$;
revoke all on function public.match_contact_emails(text[]) from public, anon;
grant execute on function public.match_contact_emails(text[]) to authenticated;
