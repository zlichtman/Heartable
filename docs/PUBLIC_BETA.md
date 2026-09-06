# Public beta acceptance checklist

This checklist is the release gate for an external Heartable TestFlight group.
It deliberately separates what CI can prove from configuration that must be
verified in Apple, Spotify, and Supabase dashboards.

## Automated repository gates

September 6 backend verification: gift-media migrations are applied, rollback-only
RLS/send tests passed, no fixture users remain, and schema lint reports no errors.
The new recipient foreign-key index is installed. Existing advisor warnings are
not a clean security sign-off: review [authenticated security-definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
and enable [leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
before a public cohort. The policy-free `capture_debug` table remains intentionally
deny-all; see [the RLS advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

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

- [ ] Spotify production access is approved before opening Spotify connection
      to a public cohort. As checked September 6, 2026, development mode allows
      five allowlisted users; the standard partner route requires an organization,
      a launched service and at least 250,000 MAUs. See [quota requirements](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
- [ ] Obtain a policy review/written Spotify guidance for cross-service content,
      derived listening metrics, synchronized lyrics and monetization. Extended
      quota is not permission for these features. See [Developer Policy](https://developer.spotify.com/policy)
      and [Compliance Tips](https://developer.spotify.com/compliance-tips).

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
- [ ] Deezer is a preview route, not full-song playback. Audius, WSUM, Plex and
      Jellyfin use the direct-stream engine; verify each
      connected service with real playable content, not only simulator fixtures.
- [ ] A provider outage leaves the last coherent cached library visible and
      gives actionable native notification feedback.
- [ ] Refresh Apple Music successfully while Spotify returns 429. Spotify's
      playlists, ordered track occurrences and artwork remain visible after
      navigation/relaunch; cached track URIs still reach the playback path.
      A subsequent successful empty response removes only verified-empty data.

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

- [ ] Rotate a playlist with the mini-player visible and without playback. The
      selected sleeve and side caption remain above the native bottom chrome;
      first/last songs center, scrolling tilts both sides smoothly, and rotating
      back preserves list position. Check a compact iPhone, Reduce Motion, long
      track names, and repeat rotations. Play opposite Back starts the selected
      vinyl song with the full ordered/shuffled/weighted playlist queue.
- [ ] On a fresh account, connecting the first usable library creates one
      automatic backup even with manual cadence. Empty/offline sources do not
      create empty backups; reconnect and confirm retry succeeds.
- [ ] Backup names are date/time only; Rename survives relaunch and rejects a
      blank name without dismissing the editor. Existing custom names remain.
- [ ] On a disposable test account, clear music data during an automatic backup
      and while a track is playing. Confirm snapshots/owned mixtapes/history
      disappear, provider pairings/profile/friends remain, and reopening does
      not recreate the first backup. Never run this test on a real library.
- [ ] Search defaults to connected libraries; multi-select WSUM and another
      public catalog, change the query, and confirm source choices stay selected.
      Verify the drawer uses the installed Heartable icon and stays fully themed.
- [ ] Search WSUM with WSUM selected; verify FM, Freeflow, and Sports stream
      on a physical device and do not manufacture song-play-count entries.
- [ ] Save a station, relaunch and sign out/in: it remains saved for that account
      on that device, but not for a different account. Show listings use Central
      time, survive feed failure, and only offer live listening during airtime.
- [ ] The player shows actual synced/plain lyrics in its themed card; expansion
      retains the current track. Rapid track changes cannot reveal old lyrics.
- [ ] On two disposable friend accounts, create a Mixtape from the profile plus,
      reopen the draft, add/reorder songs, notes, a cover and a note photo, then
      Send. Before Send, the recipient and an unrelated account cannot read the
      draft or private media. Afterwards only the recipient gains read access.
      Empty sends fail, retrying Send creates no duplicate share, and clear data
      or account deletion removes the owner's nested gift uploads.
- [ ] Fresh Spotify onboarding imports recent history without delaying entry.
      Reconnect grants `user-read-recently-played`; imported plays are labeled
      Spotify, do not inflate Heartable stats, and stay deleted after clear/reload.
- [ ] Start Spotify with native Shuffle/Repeat enabled on two different Connect
      devices; Heartable disables and verifies both on the targeted device.

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
- [ ] Mute routine confirmations: errors and enabled automatic backups still
      arrive. Master off and OS denial suppress everything. Routine updates are
      silent, Sounds off silences other categories, and rapid weekly-reminder
      toggles leave at most one correct pending schedule. No social-push switch
      appears until remote delivery is implemented.
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
