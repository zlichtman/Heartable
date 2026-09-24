# Simple playback and Spotify return flow

Weighted shuffle has been removed from playback modes, song action sheets,
accessibility actions, and queue APIs. Playback preferences no longer read or
write per-song weights. Existing `weighted` preferences migrate to ordinary
Shuffle and persist that replacement; In order is unchanged. Historical backend
weight records are retained, with no database migration or deletion.

After the native Spotify SDK confirms the selected song started, Heartable
immediately clears the starting indicator and shows that confirmed playback.
It no longer retries a second Web API start while Connect discovers the phone.
Following songs use the existing SDK connection. Queue setup failure is reported
separately and does not replace a successful start with a paused/error player.
Cancellation still propagates, preventing feedback from superseded taps.

For up to ten seconds, a confirmed SDK start can supply now-playing state while
Connect catches up. Unconfirmed starts remain paused. The existing SDK fallback
limit of 50 following songs remains; the full selection is retained in Heartable.

Regression coverage includes old-preference migration, ordinary shuffle with
selected occurrences and duplicate songs, large liked-song libraries, native
start confirmation before queue setup, queue refusal after successful playback,
failed native starts, and cancellation.

A simulator cannot validate the physical Spotify app switch. Device acceptance:
with Spotify installed and no active Connect player, tap a Spotify song, confirm
Spotify opens and returns to Heartable with that song playing, then repeat with
a second song and an existing active player. Confirm no Weighted/boost/downvote
controls remain and ordinary Shuffle still starts the selected song.

Validation: all 301 simulator tests passed on September 20, 2026. Release identity
and whitespace checks passed. The existing Supabase preflight for this release
passed; this update does not modify backend schemas or stored records.
The generic Simulator Release build also passed. Physical iPhone acceptance and
TestFlight distribution remain unverified until Apple access is available.
