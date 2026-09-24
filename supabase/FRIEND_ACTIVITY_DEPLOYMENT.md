# Friend activity deployment

Migration: `migrations/20260727003000_friend_activity_foundation.sql`

## Before deployment

1. Pull or verify the remote migration history before introducing this repository's
   first tracked migration. Do not apply the SQL manually in Dashboard and then
   run `db push`; migration history must remain authoritative.
2. Confirm the reused schema still has:
   - `play_log.id` and `play_log.user_id` as UUIDs;
   - `play_log.played_at`, `track_name`, `track_uri`, `artist`, `duration_ms`,
     and `album_art`;
   - directional `friendships.requester_id` / `addressee_id` UUIDs and the
     `accepted` status;
   - profile identity fields used by the RPC.
3. Apply the migration before releasing a client that calls
   `friend_activity_feed` or writes `friend_activity_reactions`.

The migration is additive. It creates one reaction table, two narrow authorization
helpers, one feed RPC, and supporting indexes. It does not copy, rewrite, backfill,
or delete `play_log` or friendship data.

## Apply

After authenticating and linking the Supabase CLI to the intended environment:

```sh
supabase migration list
supabase db push --dry-run
supabase db push
```

Coordinate so only one operator pushes migrations at a time. Repeat the same
ordered migration through staging before production.

## Validate

Run the following catalog checks after applying:

```sql
select to_regclass('public.friend_activity_reactions');

select indexname
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'play_log_user_played_at_id_idx',
    'friendships_accepted_requester_addressee_idx',
    'friendships_accepted_addressee_requester_idx'
  );

select proname
from pg_proc
where proname in (
  'can_react_to_friend_activity',
  'friend_activity_feed'
);

select policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename = 'friend_activity_reactions'
order by policyname;
```

Then validate with authenticated test accounts:

1. An accepted friend sees qualified historical plays, newest first.
2. A pending, declined, blocked, unrelated, or signed-out account sees no feed.
3. The feed never includes the viewer's own plays.
4. A reaction insert/replacement succeeds only for an accepted friend's play.
5. Tapping the selected reaction removes it.
6. Counts and `viewer_reaction` update on the next RPC read, while direct table
   reads reveal only the caller's own reaction row.
7. Removing a friendship immediately removes that account's feed visibility and
   prevents new or replacement reactions; the reactor may still delete their own
   old reaction.
8. Deleting a `play_log` row cascades its reactions.

Do not remove the reaction table in an emergency rollback without first accepting
that reaction data will be lost. Old app versions are unaffected if the new RPC
is simply left unused.
