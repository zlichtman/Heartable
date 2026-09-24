# Large liked-songs opening regression

Aaron reports that opening Heartables with roughly 3,000 liked songs terminates
his app. His September 12 Supabase backup is not a copy of his current device
library and cannot establish its present size. The locally available Apple
reports cover older builds, not this incident; the exact termination remains
unconfirmed.

## Confirmed defect and change

The live provider-page callback mutated the observable liked-track array once
per track. A 3,000-song fixture in 60 pages produced 50 observation notifications
per page. It now builds the page update locally and publishes once per page.
The regression test failed on all 60 original pages and passes after this change.
Partial reads still preserve cached rows; complete successful reads remain the
only authority for removal, and account resets reject late pages.

Heartables initially presents 100 songs even when thousands are already cached.
A Show next 100 songs button progressively exposes the rest. Full-library counts
and playback queues continue using the complete library. This bounds the initial
list diff; it does not cap total metadata retained or promise constant memory
after expanding the entire list.

## Verification

The rendered 3,000-song fixture checks all six row layouts, local and unavailable songs,
and a refresh shrinking the list to three entries. The initial collection has
100 song rows, plus header and pagination controls. These tests do not reproduce
Aaron's device-specific termination, exercise real Spotify artwork requests, or
replace an on-device retest of the new TestFlight build.

Release checks: 294 tests passed; the final four focused tests also passed after
adding explicit local-file rows. The generic iOS Simulator Release build,
release-identity script, diff whitespace check, linked schema lint and migration
dry run passed. Local source build is 81; Xcode Cloud assigns the uploaded build
number. Apple API authentication is currently rejected, so expiration of older
builds and tester assignment require restored App Store Connect API access.
