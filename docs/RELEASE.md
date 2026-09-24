# Heartable release contract

This is the authoritative release path for Heartable.

User preference: ship deliberate, completed app releases, not a build on every
push. Keep the marketing version at **1.0.0** unless the user explicitly requests
a version change. Consolidate each completed app change into one release commit
and start the existing Xcode Cloud workflow manually after validation.

Demo screenshots, website imagery, Demos/ assets, and documentation-only changes
must not increment the app build number or start a TestFlight build. Prepare
each future release as one reviewed commit before pushing. For an actual app
release, verify App Store Connect processing and availability to existing testers
and report the actual version/build; never claim delivery before confirming it.

## Canonical identity

| Item | Value |
|---|---|
| GitHub | `zlichtman/Heartable` |
| Branch | `main` |
| Xcode project | `Heartable.xcodeproj` |
| Scheme | `Heartable` |
| Apple team | `28LJG7MXT3` |
| App Store Connect ID | `6775338227` |
| App bundle | `com.zlichtman.heartable` |
| Widget bundle | `com.zlichtman.heartable.widget` |
| App Group | `group.com.zlichtman.heartable` |
| Supabase | `ghmuafydukliccwamkrq` |

Do not create another Heartable repository, App Store record, bundle ID, or
Xcode Cloud workflow. TestFlight builds remain on this record; expire obsolete
builds instead of replacing the record.

## 1. Source preflight

1. Confirm `main` is clean.
2. Increment `CURRENT_PROJECT_VERSION` in `project.yml`.
   First check App Store Connect's latest uploaded build and Xcode Cloud's
   latest run: Cloud assigns its own build number. Choose the next unused number
   and verify the processed artifact, not just the number in the commit message.
3. Run `xcodegen generate`.
4. Run `ci_scripts/validate_release_identity.sh`; it lints plist,
   entitlement, and privacy-manifest contracts and rejects private material.
5. Run the full unit-test suite.
6. Build a generic Simulator Release configuration.
7. Review `git diff --check`.
8. Confirm no secret, `.p8`, `.env`, local build output, or account cache is
   tracked.

## 2. Backend preflight

```sh
supabase migration list
supabase db lint --linked --schema public --level error --fail-on error
supabase db push --dry-run
```

Apply required migrations before the client upload. Verify the local/remote
migration versions align afterward.

## 3. Apple configuration

The app and widget must both have App Groups enabled and assigned to
`group.com.zlichtman.heartable`. The main app also retains Sign in with Apple.
Enable MusicKit for `com.zlichtman.heartable` under the App ID's **App Services**
tab; current MusicKit for Swift does not add a code-signing entitlement.
Use automatic signing.

For Spotify's native cold-start handoff, the existing Spotify developer app must
enable the **iOS SDK**, register bundle ID `com.zlichtman.heartable`, and retain
redirect URI `heartable://callback`. Do not create another Spotify app or rotate
the Web API credentials. Verify on a physical iPhone with Spotify installed:
no active Connect player → tap a song → Spotify authorization/handoff → the
requested song plays → return to Heartable. The SDK must reject an account that
differs from the Spotify account paired with Heartable.

Xcode-managed certificates are team-wide. Do not revoke a certificate merely
because it was created by an older workflow; first prove that no unrelated app
or active workflow uses it. Obsolete app-specific provisioning profiles may be
removed after the replacement workflow signs successfully.

## 4. Xcode Cloud

Maintain the existing active Heartable Xcode Cloud workflow:

- repository: `https://github.com/zlichtman/Heartable.git`
- project: `Heartable.xcodeproj`
- automatic branch, pull-request, tag, and schedule start conditions: none
- start manually from the reviewed release commit on `main`
- Xcode/macOS: latest release
- archive platform: iOS
- scheme: `Heartable`
- distribution preparation: App Store Connect
- auto-cancel superseded branch builds: on

Required secret environment variables:

- `SUPABASE_HOST`
- `SUPABASE_ANON_KEY`
- `SPOTIFY_CLIENT_ID`

Optional:

- `LASTFM_API_KEY`
- `LASTFM_USER`

The post-clone script creates `Secrets.xcconfig` and fails if a required value
is absent.

## 5. TestFlight

After the archive succeeds:

1. Wait for App Store Connect processing to finish.
2. Complete export-compliance questions.
3. Verify the build launches, signs in, connects providers, plays supported
   sources, restores cached library content, opens the player, and updates the
   public profile.
4. Assign the build to the internal group first.
5. Add external-test information and a reviewer account.
6. Submit the build for Beta App Review.
7. Enable the public TestFlight link only after approval.

Complete the public-beta acceptance checklist below before enabling an
external link. A passing build alone does not clear its device and service gates.

Never call an internal-only build “public.”

## 6. App Store launch gates

Before App Review submission, App Store Connect must contain:

- subtitle, category, description, keywords
- support URL and privacy-policy URL
- current iPhone screenshots
- app privacy disclosures
- age-rating questionnaire
- content-rights declaration
- verified EU trader-status choice
- contact information and a working reviewer account
- review notes explaining provider sign-in and playback limitations
- selected processed build

The first public App Store release should use manual release after approval
until production login, migrations, analytics, and support paths have been
verified against the approved binary.

## 7. Public beta acceptance

Run these checks against the exact processed TestFlight binary on physical
devices. Record the tested build and outcome before opening an external cohort.

### Repository and service gates

- [ ] The app and widget contain their privacy manifests; release identity,
      tests, archive, migration alignment, database lint/advisors, and secret
      checks in sections 1–2 pass for the release commit.
- [ ] Spotify access permits the intended testers. Review Spotify's current
      developer policy and quota terms before offering public connection or
      cross-service features; test approval status in its dashboard.
- [ ] Review the remaining authenticated security-definer functions and enable
      leaked-password protection before unrestricted email registration.
      Keep the unused `capture_debug` table deny-all; export and review its
      existing rows before any separately approved removal.
- [ ] Publish durable HTTPS privacy-policy and support URLs. Verify App Privacy
      answers against the archive privacy report and complete the App Store
      metadata, reviewer access, and disclosures listed above.

### Accounts and providers

- [ ] Fresh email and Sign in with Apple accounts complete onboarding and
      restore the same account after relaunch. A returning account restores
      provider intent without another account's cache.
- [ ] Sign-out, provider disconnect, password recovery, and account deletion
      work end to end. Deletion removes owned backend and storage data.
- [ ] Apple Music works on a subscribed device with MusicKit enabled. Spotify
      connects, refreshes tokens, and starts the tapped song from cold and warm
      states; cancellation and mismatched accounts fail clearly.
- [ ] Plex and Jellyfin work over supported local and HTTPS paths. Missing
      capabilities do not present active controls. A provider outage leaves
      coherent cached library content visible.
- [ ] Queue order, shuffle, next/previous, and provider transitions preserve
      the selected occurrence. Test rapid taps, pause during startup, network
      failure, audio interruption, and active/background limits on device.

### Library, sharing, and backups

- [ ] A large library opens without a hang or memory termination. Cached lists,
      artists, search, full playback queues, and playlist portrait/landscape
      views remain coherent while sync and artwork loads run.
- [ ] Backups create one baseline for the first usable library, preserve custom
      names, show complete details and changes, and never treat a partial read
      as removal. Test data clearing only on disposable accounts.
- [ ] Friend requests, chats, private mixtape drafts/media, recipient access
      after Send, shared links, and revoke behavior pass with two disposable
      accounts and an unrelated account.
- [ ] Music search includes only connected sources; radio and provider play
      history do not inflate Heartable's observed listening totals.

### Device presentation and rollout

- [ ] Landscape shelf and full player controls fit on compact iPhones, with
      long text and Reduce Motion. Repeated rotations preserve list position,
      playback, lyrics, and the native bottom chrome.
- [ ] Notification category controls, mute, sounds, reminder reconciliation,
      and all supported alternate icons work in foreground and background.
      Do not advertise social push until remote delivery exists.
- [ ] Widgets show the selected palette and clear private account data on
      sign-out. Review launch/hang diagnostics and backend logs for the
      processed build.
- [ ] Install from the external TestFlight link on a clean device, start with
      a small cohort, and widen only after feedback and support/deletion paths
      are verified.

Historical incident details and old build-specific test counts are available
in Git history rather than maintained as release instructions.
