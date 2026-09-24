# Spotify handoff and first-load Artists

## Changes

- Connecting Spotify tries the pinned SDK's `SPTSessionManager` with the existing
  Web API scopes and native-app preference. Callback URLs reach the active
  session manager. The coordinator has cancellation, a timeout, and account
  ownership checks. Connecting does not request playback. Only a nonempty,
  unexpired, refreshable session is persisted; an access-only session falls back
  to the existing browser PKCE flow. App Remote's playback-only credentials remain
  separate and in memory.
- Playback previously discarded transfer error types into a Boolean. A stale
  device's 404 became a generic error, bypassing the existing app wake path.
  Checked transfers now preserve missing-device and Connect-refusal errors.
  Connect 403 responses consistently allow the supported App Remote fallback;
  authentication, rate-limit and server errors retain their failure behavior.
- App Remote waits for Heartable to be active before connecting its socket after
  the callback. The existing scene-phase handler reconnects it on return.
- Playlist catalog publication no longer waits for the independent mixtape read.
  Artists renders its own loading state rather than the playlist spinner. On a
  fresh library it gets an off-main projection from the first liked-song page,
  updated at intervals of 500 new songs. Existing cached artist projections stay
  usable. Artist details include newly arriving songs, and completed liked reads
  no longer erase the index while the playlist walk runs. Verified removals are
  filtered from the interim projection.
- Optional artist-photo requests no longer keep the scanning spinner active.

## Validation and limits

Tests cover stale/restricted transfer signals versus authentication/rate-limit
errors, rejecting nonrefreshable native credentials, artists and their tracks
being available before the liked read completes, and removal from interim indexes.
The native app-switch and redirect require a physical iPhone with Spotify and
correct dashboard iOS SDK registration; simulator tests cannot prove that flow.

Validation on September 20, 2026: the full simulator suite passed 297 tests.
After tightening interim-index removal filtering, all 10 focused Spotify and
liked-page tests passed again. The final generic Simulator Release build, release identity, and whitespace checks passed.
Backend preflight found aligned migrations, no public-schema lint errors, and
no pending migrations. Native Spotify handoff still requires device validation.
