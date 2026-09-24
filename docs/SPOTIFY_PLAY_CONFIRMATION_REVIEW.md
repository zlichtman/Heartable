# Confirm playback before playlist settings

On build 87 the reported symptom was a changed song in Heartable's player,
no audible playback, and a notification about playlist/shuffle order. No new
crash report was present on the paired iPhone.

The Connect path previously treated a successful Play HTTP response as a
successful song start and then verified shuffle/repeat. A paused or idle player
could therefore end in the playlist-order warning without entering native wake.

After Connect accepts Play, Heartable now polls up to three times for the selected
URI to be playing on the requested device. Idle, paused, or wrong-song responses
lead to the existing native Spotify handoff. A denied/unavailable readback also
allows native confirmation; an explicit rate limit remains a rate-limit error.
Only confirmed song playback proceeds to playlist settings, and its first state
is reused instead of immediately requesting the same state again. The old
“order isn't in charge” / “reapply mode” warning has been replaced with a direct
playlist-settings warning that is only reached after actual playback confirmation.

Tests cover accepted-but-idle commands, a paused selected song, a different song,
confirmed playback with shuffle still enabled, and rate limits. This reproduces
the faulty decision path with controlled responses; it does not prove the current
phone's exact Spotify response without a device retest.

Validation: all 308 simulator tests passed on September 20, 2026 after correcting
a missing `is_active` field in the new device fixture. The initial failed run
finished its tests but its report collector hung and was stopped before the clean
rerun. Release identity and whitespace checks passed. No backend schema changes.
The generic Simulator Release build passed. Playback on the physical iPhone
remains a required retest after the new build reaches TestFlight.
