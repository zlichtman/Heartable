create table if not exists profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  spotify_id   text unique not null,
  display_name text,
  avatar_url   text,
  share_code   text unique not null default encode(gen_random_bytes(6),'hex'),
  handle       text unique,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table profiles enable row level security;
create policy prof_sel on profiles for select using (
  user_id = auth.uid()
  or exists (select 1 from friendships f where f.status='accepted'
     and ((f.requester_id=auth.uid() and f.addressee_id=profiles.user_id)
       or (f.addressee_id=auth.uid() and f.requester_id=profiles.user_id)))
);
create policy prof_ins on profiles for insert with check (user_id = auth.uid());
create policy prof_upd on profiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create or replace function find_profile(p_query text)
returns table(user_id uuid, display_name text, spotify_id text, avatar_url text)
language sql security definer set search_path = public as $$
  select user_id, display_name, spotify_id, avatar_url from profiles
   where handle = lower(p_query) or share_code = p_query limit 1
$$;
revoke all on function find_profile(text) from public;
grant execute on function find_profile(text) to authenticated;;
