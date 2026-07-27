-- Friend activity is a read model over the existing durable play_log ledger.
-- This migration adds reactions and a friend-scoped RPC; it does not copy or
-- backfill listening events into a second activity table.

create table if not exists public.friend_activity_reactions (
    activity_id uuid not null
        references public.play_log(id) on delete cascade,
    user_id uuid not null
        references auth.users(id) on delete cascade,
    reaction text not null,
    created_at timestamptz not null default now(),
    constraint friend_activity_reactions_pkey
        primary key (activity_id, user_id),
    constraint friend_activity_reactions_reaction_check
        check (reaction in ('heart', 'fire', 'headphones', 'on_repeat'))
);

comment on table public.friend_activity_reactions is
    'One fixed reaction per account per durable play_log activity.';
comment on column public.friend_activity_reactions.activity_id is
    'The play_log row being reacted to; no duplicate activity ledger is stored.';

-- Feed reads are newest-first within accepted friend ids. These partial indexes
-- support that keyset scan and both directional friendship predicates.
create index if not exists play_log_user_played_at_id_idx
on public.play_log (user_id, played_at desc, id desc)
where played_at is not null and track_name is not null;

create index if not exists friendships_accepted_requester_addressee_idx
on public.friendships (requester_id, addressee_id)
where status = 'accepted';

create index if not exists friendships_accepted_addressee_requester_idx
on public.friendships (addressee_id, requester_id)
where status = 'accepted';

alter table public.friend_activity_reactions enable row level security;

-- SECURITY DEFINER is intentional: play_log remains owner-scoped under its own
-- RLS, while this predicate performs the narrow accepted-friend authorization
-- needed by reaction policies. The caller identity always comes from auth.uid().
create or replace function public.can_react_to_friend_activity(
    p_activity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select auth.uid() is not null
       and exists (
            select 1
            from public.play_log as activity
            where activity.id = p_activity_id
              and activity.user_id <> auth.uid()
              and exists (
                    select 1
                    from public.friendships as friendship
                    where friendship.status = 'accepted'
                      and (
                            (
                                friendship.requester_id = auth.uid()
                                and friendship.addressee_id = activity.user_id
                            )
                            or (
                                friendship.addressee_id = auth.uid()
                                and friendship.requester_id = activity.user_id
                            )
                      )
              )
       );
$function$;

revoke all on function public.can_react_to_friend_activity(uuid) from public;
revoke all on function public.can_react_to_friend_activity(uuid) from anon;
grant execute on function public.can_react_to_friend_activity(uuid) to authenticated;

-- Drop first so a recovery run after a partial/manual application converges.
-- Raw table reads expose only the caller's own row. Aggregate counts for every
-- reaction are returned by the friend-scoped SECURITY DEFINER feed below.
drop policy if exists "accepted friends can read activity reactions"
on public.friend_activity_reactions;
drop policy if exists "accounts can read their own activity reaction"
on public.friend_activity_reactions;
drop policy if exists "accepted friends can add their reaction"
on public.friend_activity_reactions;
drop policy if exists "accepted friends can replace their reaction"
on public.friend_activity_reactions;
drop policy if exists "accounts can remove their own activity reaction"
on public.friend_activity_reactions;
drop function if exists public.can_view_friend_activity(uuid);

create policy "accounts can read their own activity reaction"
on public.friend_activity_reactions
for select
to authenticated
using (user_id = auth.uid());

create policy "accepted friends can add their reaction"
on public.friend_activity_reactions
for insert
to authenticated
with check (
    user_id = auth.uid()
    and public.can_react_to_friend_activity(activity_id)
);

create policy "accepted friends can replace their reaction"
on public.friend_activity_reactions
for update
to authenticated
using (
    user_id = auth.uid()
    and public.can_react_to_friend_activity(activity_id)
)
with check (
    user_id = auth.uid()
    and public.can_react_to_friend_activity(activity_id)
);

-- A user may remove their own reaction after a friendship changes. Inserts and
-- replacements still require an accepted friendship at mutation time.
create policy "accounts can remove their own activity reaction"
on public.friend_activity_reactions
for delete
to authenticated
using (user_id = auth.uid());

revoke all on table public.friend_activity_reactions from anon;
grant select, insert, update, delete
on table public.friend_activity_reactions
to authenticated;

-- Keyset pagination uses played_at plus id, avoiding offset drift when new plays
-- arrive between requests. The RPC returns only qualified plays from currently
-- accepted friends and never exposes another account's full play_log table.
create or replace function public.friend_activity_feed(
    p_limit integer default 50,
    p_before_played_at timestamptz default null,
    p_before_id uuid default null
)
returns table (
    activity_id uuid,
    user_id uuid,
    display_name text,
    handle text,
    avatar_url text,
    track_uri text,
    track_name text,
    artist text,
    duration_ms bigint,
    album_art text,
    played_at timestamptz,
    reaction_counts jsonb,
    viewer_reaction text
)
language sql
stable
security definer
set search_path = ''
as $function$
    select
        activity.id as activity_id,
        activity.user_id as user_id,
        profile.display_name::text as display_name,
        profile.handle::text as handle,
        profile.avatar_url::text as avatar_url,
        activity.track_uri::text as track_uri,
        activity.track_name::text as track_name,
        activity.artist::text as artist,
        activity.duration_ms::bigint as duration_ms,
        activity.album_art::text as album_art,
        activity.played_at as played_at,
        coalesce(reactions.counts, '{}'::jsonb) as reaction_counts,
        viewer.reaction::text as viewer_reaction
    from public.play_log as activity
    left join public.profiles as profile
        on profile.user_id = activity.user_id
    left join lateral (
        select jsonb_object_agg(grouped.reaction, grouped.total) as counts
        from (
            select
                aggregate_reaction.reaction,
                count(*)::integer as total
            from public.friend_activity_reactions as aggregate_reaction
            where aggregate_reaction.activity_id = activity.id
            group by aggregate_reaction.reaction
        ) as grouped
    ) as reactions on true
    left join lateral (
        select current_reaction.reaction
        from public.friend_activity_reactions as current_reaction
        where current_reaction.activity_id = activity.id
          and current_reaction.user_id = auth.uid()
        limit 1
    ) as viewer on true
    where auth.uid() is not null
      and activity.user_id <> auth.uid()
      and activity.played_at is not null
      and nullif(btrim(activity.track_name::text), '') is not null
      and exists (
            select 1
            from public.friendships as friendship
            where friendship.status = 'accepted'
              and (
                    (
                        friendship.requester_id = auth.uid()
                        and friendship.addressee_id = activity.user_id
                    )
                    or (
                        friendship.addressee_id = auth.uid()
                        and friendship.requester_id = activity.user_id
                    )
              )
      )
      and (
            p_before_played_at is null
            or (
                p_before_id is null
                and activity.played_at < p_before_played_at
            )
            or (
                p_before_id is not null
                and (activity.played_at, activity.id)
                    < (p_before_played_at, p_before_id)
            )
      )
    order by activity.played_at desc, activity.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;

comment on function public.friend_activity_feed(integer, timestamptz, uuid) is
    'Accepted-friends historical activity from play_log with reaction aggregates.';

revoke all
on function public.friend_activity_feed(integer, timestamptz, uuid)
from public;
revoke all
on function public.friend_activity_feed(integer, timestamptz, uuid)
from anon;
grant execute
on function public.friend_activity_feed(integer, timestamptz, uuid)
to authenticated;
