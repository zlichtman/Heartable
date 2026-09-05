# Public beta acceptance checklist

This checklist is the release gate for an external Heartable TestFlight group.
It deliberately separates what CI can prove from configuration that must be
verified in Apple, Spotify, and Supabase dashboards.

## Automated repository gates

- [ ] `ci_scripts/validate_release_identity.sh` passes.
- [ ] `xcodegen generate` produces no unexpected project diff.
- [ ] The full unit-test suite passes with Swift 6 strict concurrency.
- [ ] A generic-device Release archive succeeds with automatic signing.
- [ ] The built app and widget each contain `PrivacyInfo.xcprivacy`.
- [ ] Supabase local and remote migration versions align and database advisors
      contain no unresolved security errors.
- [ ] No `.p8`, `.p12`, provisioning profile, private key, `.env`, provider
      token, or Supabase secret/service-role key is tracked.

## Fresh-install and account matrix

Test on a physical iPhone using the exact processed TestFlight binary:

- [ ] New email account: sign up, confirm email, finish onboarding, terminate,
      and reopen into the same profile.
- [ ] Sign in with Apple: create and returning-user paths both restore the same
      Heartable account.
- [ ] Existing account on a fresh install restores its profile and provider
      pairing intent without presenting another account's cache.
- [ ] Sign out and back in preserves pairings; explicit provider disconnect does
      not return after relaunch.
- [ ] Password recovery lands on a working page that accepts and confirms a new
      password, then the new password signs in. This remains a blocker until the
      Supabase recovery redirect is verified end to end.
- [ ] Delete Account removes the Auth user and owned backend/storage data, then
      returns to a clean sign-in screen.

## Provider and playback matrix

- [ ] The Apple App ID has the MusicKit App Service enabled; Apple Music
      authorization, library, catalog search, artwork, and playback work on a
      subscribed physical device.
- [ ] Spotify has `heartable://callback` registered exactly; connect, token
      refresh, device selection, cold-start playback, and reconnect work.
- [ ] The same Spotify developer app has iOS SDK enabled and bundle ID
      `com.zlichtman.heartable`. A no-player start plays the tapped song after the
      SDK handoff; cancellation, missing Spotify, and mismatched accounts fail
      clearly without substituting another provider.
- [ ] Order, shuffle, and weighted playback queue every occurrence; next/previous
      work across playlist, artist, Heartables, and mixtape entry points. Mode
      changes keep the current position, and paused mode changes stay silent.
- [ ] Spotify device transfer preserves playing/paused state. Same-service queues
      continue while backgrounded; cross-provider boundaries are tested with the
      app active and documented without an unsupported background guarantee.
- [ ] Plex and Jellyfin local-network prompts are contextual and both HTTP LAN
      and HTTPS server paths have been tested.
- [ ] Unsupported provider capabilities never present active controls.
- [ ] Switch Apple Music → Spotify → Apple Music and each connected direct-stream
      service, from both idle and playing. Repeat rapid taps and Pause during a
      start; only the final requested song may play. Test a failed Spotify pause,
      expired direct-stream URL, network outage, and audio interruption/recovery.
- [ ] Deezer is a preview route, not full-song playback. Audius, Internet Archive,
      Radio Browser, Plex and Jellyfin use the direct-stream engine; verify each
      connected service with real playable content, not only simulator fixtures.
- [ ] A provider outage leaves the last coherent cached library visible and
      gives actionable native notification feedback.

## Privacy and App Store Connect

- [ ] Publish a durable HTTPS privacy-policy URL and support URL. Do not use a
      repository settings page or temporary document.
- [ ] App Privacy answers match `Heartable/Resources/PrivacyInfo.xcprivacy`:
      linked account identity, profile media/user content, and music listening
      interaction; no tracking. Contacts remain on-device.
- [ ] Generate and review Xcode's archive privacy report, including the Supabase
      dependency manifest, before answering App Privacy questions.
- [ ] Complete age rating, content rights, encryption, EU trader status,
      reviewer contact, beta description, feedback email, and review notes.
- [ ] Review notes explain separate Heartable/provider accounts, Apple Music
      subscription requirements, Spotify Connect device limitations, local
      network access for self-hosted services, and how the reviewer can reach
      each gated screen.

## Backend quarantine gate

Applied and verified on 2026-09-03: `quarantine_capture_debug` preserves all three
rows in the unused diagnostic table, revokes client access, and enables RLS with
no policies (an intentional deny-all quarantine). It also removes inherited
anonymous `PUBLIC` execution from `are_friends`, `find_profile`, and
`song_leaderboard` while retaining authenticated execution. Database lint passes,
and local/remote migrations are synchronized. After an owner exports and reviews the debug payloads,
remove the table in a separate explicitly approved maintenance change.

The advisor will continue to report authenticated execution of several
security-definer functions that deliberately cross owner-only RLS to build a
friend-scoped feed or leaderboard. Before App Store launch, review each body and
keep only the narrow functions whose caller identity is derived from `auth.uid()`.
Enable Supabase Auth leaked-password protection before opening email/password
registration to an unrestricted public cohort.

## External beta smoke test

- [ ] On a fresh account, connecting the first usable library creates one
      automatic backup even with manual cadence. Empty/offline sources do not
      create empty backups; reconnect and confirm retry succeeds.
- [ ] Backup names are date/time only; Rename survives relaunch and rejects a
      blank name without dismissing the editor. Existing custom names remain.
- [ ] On a disposable test account, clear music data during an automatic backup
      and while a track is playing. Confirm snapshots/owned mixtapes/history
      disappear, provider pairings/profile/friends remain, and reopening does
      not recreate the first backup. Never run this test on a real library.
- [ ] Search WSUM with Radio included; verify FM, Freeflow, and Sports stream
      on a physical device and do not manufacture song-play-count entries.

- [ ] Install from the public TestFlight link on a device that has never run a
      development build.
- [ ] Exercise authentication, profile photo, every live provider, search,
      library navigation, playback/Now Playing, friends, chat, backups and diff
      history, notifications, appearance, cache clearing, and account deletion.
- [ ] Change each of the eight app icons and trigger a new native notification
      after Apple's icon-change confirmation, in foreground and background.
      Check Home Screen and notification artwork separately. iOS owns the
      notification header and may retain artwork on older delivered notices;
      Heartable must not delete notification history or spoof sender icons.
- [ ] Add all three widgets in small/medium sizes. Switch light/dark presets,
      edit the active custom theme, then delete it; existing widgets should
      receive the current semantic palette without removal/re-adding. Allow
      WidgetKit's refresh scheduling. Verify tinted/clear Home Screen modes
      and supported Lock Screen slots remain legible, including empty states.
- [ ] Sign out with widgets installed: private recap/friend data disappears,
      but the device's selected widget palette remains.
- [ ] Verify launch/hang diagnostics and Supabase Auth/API/Storage logs for the
      processed build, with no repeated crash, RLS, or authorization failures.
- [ ] Start with a small external cohort and manual rollout; widen only after
      feedback and deletion/support paths are proven.
