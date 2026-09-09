-- Friend-DM messaging. 1:1 direct messages between accepted friends, optionally
-- carrying a shared song / playlist / mixtape as a typed attachment payload.

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text,
  kind text not null default 'text' check (kind in ('text','song','playlist','mixtape')),
  payload jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint messages_not_self check (sender_id <> recipient_id),
  constraint messages_has_content check (body is not null or payload is not null)
);

create index if not exists messages_pair_created_idx
  on public.messages (least(sender_id, recipient_id), greatest(sender_id, recipient_id), created_at);
create index if not exists messages_recipient_unread_idx
  on public.messages (recipient_id) where read_at is null;

alter table public.messages enable row level security;

-- Either party in the conversation may read it.
create policy messages_select_participant on public.messages
  for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- Only the sender may send, and only to an accepted friend.
create policy messages_insert_sender_friend on public.messages
  for insert to authenticated
  with check (auth.uid() = sender_id and public.are_friends(sender_id, recipient_id));

-- Only the recipient may mark a message read (the only field they may change).
create policy messages_update_recipient on public.messages
  for update to authenticated
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- Senders can unsend their own messages.
create policy messages_delete_sender on public.messages
  for delete to authenticated
  using (auth.uid() = sender_id);

-- Live updates so an open conversation receives new messages without polling.
alter publication supabase_realtime add table public.messages;;
