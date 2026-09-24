# Spotify sign-in retry and onboarding lifetime

A native sign-in could remain pending after a user manually returned from
Spotify without a callback. Further Connect taps then failed with “sign-in is
already open” until the two-minute timeout expired.

The coordinator now releases an abandoned session when Heartable becomes active
again, allowing a one-second grace period for the authorization callback to
arrive. A recognized callback prevents premature cancellation while the SDK
finishes authentication. A new explicit Connect request also cancels and detaches
any older session. Delegate identity and request IDs keep old callbacks and
cancellation handlers from completing a replacement request. Cancellation returns
the Connect control without an error banner.

SDK session delegate methods now accept callbacks from any thread and send only
immutable credentials and manager identity to the main actor. They no longer
rely on a runtime main-actor assertion for an Objective-C delegate callback.
A regression test delivers a failure on a background queue, then signs in again.

Onboarding now owns and cancels its connection task when it disappears, prevents
overlapping connection requests, and disables Back/Done while connecting. It does
not complete onboarding in the middle of an outstanding provider authorization.

Three fresh reports were retrieved directly from the paired iPhone after testing:
September 20 at 19:08:33, 19:09:28, and 19:09:52, all Heartable 1.0.0 build 85.
All three have the same EXC_BREAKPOINT/SIGTRAP on com.apple.NSURLSession-delegate:
_dispatch_assert_queue_fail → dispatch_assert_queue → Swift executor isolation
check → Heartable offset 5544512 → SpotifyiOS offsets 110108 and 108776.
This confirms an SDK-to-Heartable callback thread-isolation failure. The matching
build's app dSYM was unavailable, so the app frame has not been line-symbolicated.
The session delegate bridge no longer requires the caller to be on the main actor;
its background-callback regression passes. Raw phone reports remain outside git.

Validation: all 304 simulator tests and the generic Simulator Release build passed.
Release identity and whitespace checks passed. The native app-switch behavior and
successful onboarding still require verification on the iPhone with the new build.
Device acceptance should cover cancelling native Spotify authorization, reconnecting
immediately, successful authorization during onboarding, and successful connection
from Music Services after onboarding.
