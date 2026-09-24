-- Account-owned provider pairings are durable independently of any one app
-- installation. Only non-secret restoration metadata lives here; OAuth and
-- server tokens remain in the user's Keychain.
create table if not exists public.provider_connections (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_id text not null,
  connected boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  connected_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, provider_id),
  constraint provider_connections_provider_id_not_blank
    check (length(trim(provider_id)) > 0),
  constraint provider_connections_metadata_is_object
    check (jsonb_typeof(metadata) = 'object')
);

alter table public.provider_connections enable row level security;
revoke all on public.provider_connections from anon;

drop policy if exists provider_connections_self_select
  on public.provider_connections;
create policy provider_connections_self_select
  on public.provider_connections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists provider_connections_self_insert
  on public.provider_connections;
create policy provider_connections_self_insert
  on public.provider_connections
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists provider_connections_self_update
  on public.provider_connections;
create policy provider_connections_self_update
  on public.provider_connections
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update on public.provider_connections to authenticated;

-- Existing accounts have already passed onboarding in shipped builds. New
-- accounts begin NULL and set the timestamp when the wizard completes.
alter table public.profiles
  add column if not exists onboarding_completed_at timestamptz;

-- Some legacy Heartable auth accounts never received a profile row when the old
-- profile trigger failed. Treat every account that predates this migration as an
-- established user and repair the missing row at the same time. Accounts created
-- after this migration still start with a NULL completion timestamp.
insert into public.profiles (
  user_id,
  onboarding_completed_at,
  created_at,
  updated_at
)
select
  users.id,
  coalesce(users.last_sign_in_at, users.created_at, now()),
  coalesce(users.created_at, now()),
  now()
from auth.users as users
on conflict (user_id) do update
set onboarding_completed_at = coalesce(
  public.profiles.onboarding_completed_at,
  excluded.onboarding_completed_at
);
