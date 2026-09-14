# Liked songs and Spotify startup review — September 14, 2026

Reviewed the recent library recovery, cache, playback fallback, and memory changes through `7c82804`.

## Findings addressed

- Artwork still used `UIImage(data:)`, so decoded dimensions were unbounded despite the compressed-byte check and NSCache budget. A compressed large cover can allocate a large bitmap before cache eviction helps. ImageIO now creates a thumbnail of at most 1024 pixels on its longest edge, with eager decoding off the main actor. A 4096×2048 fixture verifies the resulting 1024×512 bitmap and allocation size.
- Library status considered only playlist reads. A successful catalog followed by failed liked-song pages could show an empty list with no explanation and skip retry through the freshness window. The final notice now considers all three reads; the liked-song screen shows it and keeps the loading state while the pull is pending. Existing last-good-cache merge behavior is retained.
- App Remote verified its callback token through the library metadata read gate. A persisted library cooldown could therefore reject the callback before connecting. Playback verification now makes an independent, non-rate-limit-retrying `/me` request with the exact supplied token. It still fails on a real server refusal or account mismatch. It cannot silently reauthenticate an SDK token with Web API credentials.
- Device discovery that returned only restricted devices, and the final playback 404 after retries, became generic errors that bypassed the SDK wake path. Both now retain typed errors understood by PlayerStore.

## Device validation still required

These are code-level defects and mitigations, not a confirmed diagnosis of the tester's termination. Obtain the affected device's Heartable Diagnostics report (Profile/Account), exact installed build, and the action immediately before termination. Re-test a large liked library with cold and warm caches, scrolling artwork, and a simulated provider read failure.

Spotify's installed-app switch cannot be validated by simulator unit tests. On a phone, start a song with Spotify idle, confirm the switch to Spotify and return to Heartable, repeat during an existing metadata cooldown, verify a different Spotify account is rejected, and check subsequent queue playback. A fresh server 429 on account verification must still fail; the change does not bypass Spotify's server limits.

## Build 79 release verification

- Full iOS Simulator suite: 275 tests, zero failures.
- Release identity validation passed; no private key material is tracked.
- Supabase migration history matches production, public-schema lint found no errors, and the migration dry run reports production is up to date.
- Generic iOS Simulator Release build passed.
