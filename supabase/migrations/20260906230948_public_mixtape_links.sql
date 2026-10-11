-- Link rows are never exposed through table APIs. Owners publish explicitly;
-- the Edge Function alone reads a snapshot using a 256-bit bearer token.
create table heartable_private.mixtape_links (
  mixtape_id uuid primary key references public.mixtapes(id) on delete cascade,
  owner uuid not null references auth.users(id) on delete cascade,
  token text not null check (token ~ '^[0-9a-f]{64}$'),
  token_hash text generated always as (encode(extensions.digest(token, 'sha256'), 'hex')) stored unique,
  snapshot jsonb not null,
  published_at timestamptz not null default now()
);
create index mixtape_links_owner_idx on heartable_private.mixtape_links(owner);
alter table heartable_private.mixtape_links enable row level security;
revoke all on heartable_private.mixtape_links from public, anon, authenticated;
grant usage on schema heartable_private to service_role;
grant select on heartable_private.mixtape_links to service_role;

create function heartable_private.manage_mixtape_link(p_id uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); tape public.mixtapes; link heartable_private.mixtape_links;
  items jsonb; payload jsonb;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select * into tape from public.mixtapes where id = p_id and owner = caller for update;
  if not found then raise exception 'Mixtape unavailable'; end if;
  if p_action = 'revoke' then
    delete from heartable_private.mixtape_links where mixtape_id = p_id and owner = caller;
    return '{}'::jsonb;
  elsif p_action = 'publish' then
    if (select count(*) from public.mixtape_tracks where mixtape_id = p_id) not between 1 and 500 then
      raise exception 'A shared mixtape needs between 1 and 500 tracks';
    end if;
    -- Never publish server URLs, access tokens, private provider IDs, or account IDs.
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'track_name', left(t.track_name, 500), 'artist', left(t.artist, 500),
      'track_uri', case when t.track_uri ~ '^(spotify:track:[A-Za-z0-9]+|apple:song:[A-Za-z0-9.]+|deezer:track:[0-9]+|audius:track:[A-Za-z0-9]+)$' then t.track_uri else null end,
      'note', left(t.note, 10000),
      'note_image_url', case when t.note_image_url like 'heartable-media://mixtape-gifts/' || caller::text || '/' || p_id::text || '/%' then t.note_image_url else null end
    ) order by t.position nulls last, t.id) into items from public.mixtape_tracks t where t.mixtape_id = p_id;
    payload := jsonb_build_object('title', left(tape.title, 500), 'description', left(tape.description, 10000),
      'cover_url', case when tape.cover_url like 'heartable-media://mixtape-gifts/' || caller::text || '/' || p_id::text || '/%' then tape.cover_url else null end,
      'tracks', items);
    insert into heartable_private.mixtape_links(mixtape_id, owner, token, snapshot)
      values(p_id, caller, encode(extensions.gen_random_bytes(32), 'hex'), payload)
      on conflict (mixtape_id) do update set snapshot = excluded.snapshot, published_at = now();
  elsif p_action <> 'status' then raise exception 'Invalid action';
  end if;
  select * into link from heartable_private.mixtape_links where mixtape_id = p_id and owner = caller;
  if not found then return '{}'::jsonb; end if;
  return jsonb_build_object('token', link.token, 'published_at', link.published_at);
end $$;
revoke all on function heartable_private.manage_mixtape_link(uuid,text) from public, anon;
grant execute on function heartable_private.manage_mixtape_link(uuid,text) to authenticated;
create function public.manage_mixtape_link(p_id uuid, p_action text)
returns jsonb language sql security invoker set search_path = '' as $$
  select heartable_private.manage_mixtape_link(p_id, p_action);
$$;
revoke all on function public.manage_mixtape_link(uuid,text) from public, anon;
grant execute on function public.manage_mixtape_link(uuid,text) to authenticated;

-- Invoker privileges: only the server role can call this, never anon clients.
create function public.read_shared_mixtape(p_hash text)
returns jsonb language sql security invoker set search_path = '' as $$
  select snapshot from heartable_private.mixtape_links where token_hash = p_hash;
$$;
revoke all on function public.read_shared_mixtape(text) from public, anon, authenticated;
grant execute on function public.read_shared_mixtape(text) to service_role;
