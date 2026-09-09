do $$ begin
  create type friend_status as enum ('pending','accepted','declined','blocked');
exception when duplicate_object then null; end $$;
create table if not exists friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status       friend_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (requester_id <> addressee_id),
  unique (requester_id, addressee_id)
);
create index if not exists idx_friend_addressee on friendships(addressee_id, status);
create index if not exists idx_friend_requester on friendships(requester_id, status);
alter table friendships enable row level security;
create policy fr_sel on friendships for select using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy fr_ins on friendships for insert with check (requester_id = auth.uid());
create policy fr_upd on friendships for update using (addressee_id = auth.uid() or requester_id = auth.uid()) with check (addressee_id = auth.uid() or requester_id = auth.uid());
create policy fr_del on friendships for delete using (requester_id = auth.uid() or addressee_id = auth.uid());;
