-- Preserve first pairing order even when older clients rewrite connected_at.
alter table public.provider_connections add column first_linked_at timestamptz;
update public.provider_connections set first_linked_at = coalesce(connected_at, updated_at, now());
alter table public.provider_connections alter column first_linked_at set default now();
alter table public.provider_connections alter column first_linked_at set not null;

create or replace function public.preserve_first_provider_link()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if TG_OP = 'UPDATE' then
    NEW.first_linked_at := OLD.first_linked_at;
    NEW.metadata := OLD.metadata || NEW.metadata;
  else
    NEW.first_linked_at := clock_timestamp();
  end if;
  return NEW;
end;
$$;
revoke all on function public.preserve_first_provider_link() from public, anon, authenticated;
create trigger preserve_first_provider_link before insert or update on public.provider_connections
for each row execute function public.preserve_first_provider_link();

-- Atomic conditional updates never overwrite a concurrent user edit. No client
-- may nominate another account or bypass the existing profile/connection RLS.
create or replace function public.seed_profile_from_first_connection(expected_owner uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  first_connection public.provider_connections;
  suggested_name text;
  suggested_avatar text;
begin
  if auth.uid() is null or auth.uid() is distinct from expected_owner then
    raise exception 'Account changed' using errcode = '42501';
  end if;
  perform 1 from public.profiles where user_id = expected_owner for update;
  select * into first_connection from public.provider_connections
    where user_id = expected_owner and provider_id in ('spotify','apple','plex','jellyfin')
    order by first_linked_at, provider_id limit 1;
  if not found then return; end if;
  suggested_name := nullif(btrim(first_connection.metadata->>'display_name', E' \t\n\r'), '');
  suggested_avatar := nullif(btrim(first_connection.metadata->>'avatar_url'), '');
  if suggested_avatar !~ '^https://[^/[:space:]]+/' then suggested_avatar := null; end if;
  update public.profiles set
    display_name = case when nullif(btrim(display_name, E' \t\n\r'), '') is null
      or lower(btrim(display_name)) = 'heartable user'
      then coalesce(left(suggested_name, 120), display_name) else display_name end,
    avatar_url = case when nullif(btrim(avatar_url), '') is null
      then coalesce(suggested_avatar, avatar_url) else avatar_url end
    where user_id = expected_owner;
end;
$$;
revoke all on function public.seed_profile_from_first_connection(uuid) from public, anon;
grant execute on function public.seed_profile_from_first_connection(uuid) to authenticated;
