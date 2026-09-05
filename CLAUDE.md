# Heartable engineering guide

Read this file before changing the app. It records the product constraints and
engineering contracts that must survive future work.

## Non-negotiable product decisions

- The public product name is **Heartable**.
- The first tab is titled **Heartable**, not Discover or For You.
- **Backups remains one of five permanent tabs.** Do not move it into Profile.
- The permanent tabs, left to right, are Heartable, Chats, Library, Backups,
  and Profile.
- Tab titles are hidden by default. Appearance can enable them without
  rebuilding the tab hierarchy.
- The visual center is the warm Heartable palette: brown, pink, and paper.
  Terminal-inspired palettes are optional expressions of the same design
  system, not a separate product mode.
- The canonical launch, TestFlight, and App Store icon is the dark Heartable
  mark. Alternate icons must remain balanced and use real Heartable artwork.
- Provider sign-in is separate from Heartable account creation. Connecting or
  disconnecting Spotify, Apple Music, or another service must not create,
  replace, or delete a Heartable account.

## Repository and release identity

- Canonical GitHub repository: `zlichtman/Heartable`
- Default branch: `main`
- Xcode project and scheme: `Heartable`
- Apple team: `28LJG7MXT3`
- App Store Connect Apple ID: `6775338227`
- App bundle ID: `com.zlichtman.heartable`
- Widget bundle ID: `com.zlichtman.heartable.widget`
- App Group: `group.com.zlichtman.heartable`
- Supabase project: `ghmuafydukliccwamkrq`

`project.yml` is the target/build-setting source of truth. Regenerate
`Heartable.xcodeproj` after source or project changes and commit both.

## Toolchain

- SwiftUI and Observation
- Swift 6 with complete strict concurrency
- iOS 26 minimum
- Swift Package Manager only
- XcodeGen for project generation
- Supabase Swift and the official Spotify iOS SDK as pinned SPM dependencies
- Apple system frameworks for authentication, playback, storage, and UI

Do not introduce CocoaPods, React Native, Expo, checked-in secrets, or a second
project-generation path.

## Runtime architecture

The app injects long-lived `@Observable` stores from `HeartableApp` and keeps
screen-specific state in feature modules.

- `Heartable/App`: lifecycle, auth/onboarding gate, tab shell
- `Heartable/Design`: semantic palette, typography, shared components
- `Heartable/Features`: feature-owned views and presentation state
- `Heartable/Services/Auth`: Heartable session
- `Heartable/Services/Backend`: typed Supabase API and DTOs
- `Heartable/Services/Library`: normalization, identity, caching, search
- `Heartable/Services/Player`: player state and transport routing
- `Heartable/Services/Providers`: adapters and provider truth
- `Heartable/Services/Recap`: qualified listening aggregation
- `Heartable/Services/Social`: durable activity and friend sync
- `HeartableWidget`: app-group snapshots only

Widgets read secret-free snapshots, never provider credentials or backend clients.
Keep recap/friend data privacy-sensitive and clear it on account transitions.
Weekly labels must expire at the week boundary. Widget deep links use the
allow-listed `HeartableWidgetRoute` contract and wait for authentication before
navigating. Do not imply WidgetKit refreshes are real-time playback updates.

Widget appearance uses `HeartableWidgetTheme` in a separate app-group key from
private content. `ThemeStore` publishes resolved semantic colors on launch,
selection, and active custom-theme edits/deletion. Reload timelines only when
the published palette changes. Full-color widgets follow the app palette;
accented/vibrant contexts defer contrast to WidgetKit, with only glyphs in the
accent group. Never hard-code a second widget theme or clear device appearance
when clearing account content.

State that belongs to a user must either live in a store reset by the account
shell or use an account-scoped persistence key/file. Register provider
credentials and account-owned preferences with `AccountSessionStore`.

Authentication and provider restoration are one ordered bootstrap owned by
`RootView`:

1. Supabase emits the locally persisted Heartable session immediately and
   refreshes it in the background.
2. `AccountSessionStore` activates that user's namespace before the session is
   published to views.
3. `MeStore` paints the account-scoped cached profile while reconciling the
   authoritative profile.
4. `ProvidersStore` merges the cached and RLS-protected
   `provider_connections` manifest, restores safe metadata, then probes local
   credentials.
5. The app shell hydrates cached library content and refreshes it only after
   provider restoration reaches a coherent state.

A provider pairing and a usable device credential are different states. Pairing
intent belongs to the Heartable account in Supabase; secrets stay in an
account-scoped, iCloud-synchronizable Keychain item. A missing credential must
surface as **Reconnect**, never silently rewrite the account pairing as
disconnected. Normal sign-out clears in-memory state only. Explicit service
disconnect or account deletion is what removes durable state.

## Provider and playback rules

`ProviderCatalog` is the single source of truth for provider availability,
capabilities, setup text, playback tier, and transport route. A provider must
never claim a capability its public API cannot deliver.

All provider content normalizes into `UnifiedTrack`, `UnifiedPlaylist`, and
related shared models. Track identity must deduplicate the same recording across
services without merging unrelated editions.

Playback starts through the provider that owns the selected track:

- Apple Music uses `ApplicationMusicPlayer`.
- Spotify uses Spotify Connect when a usable device exists. `SpotifyAppRemote`
  uses the official SDK to wake the phone player, play the requested URI, and
  return to Heartable when no device is active. A brief app switch is required;
  never promise invisible cold starts. The SDK token stays in memory, must match
  the account-bound Spotify user, and never replaces Web API credentials.
- Providers with legal direct streams use `LocalAudioEngine`.
- A stats-only provider never presents playback controls.

`PlayerStore` is the sole merged now-playing authority. Do not create competing
polling loops in views. Cancel stale starts, activate audio lazily, preserve the
queue and cached playlist data across navigation, and surface actionable errors
without immediately dismissing the player.

Direct-stream starts are structured, awaited operations: reactivate the audio
session on every start/resume, wait for actual playback or a bounded error, and
cancel obsolete generations on pause/stop. Never launch a detached/deferred
start from a provider adapter or expose credential-bearing AVFoundation errors.
An explicit pending track wins now-playing selection over stale old-provider
polls. A failed Spotify pause aborts a handoff; after SDK wake, retry only the
short Connect-device propagation gap, not authentication failures.

`PlaybackQueue` identifies occurrences, not just URIs. Shuffle must install the
whole selected queue, not merely choose a random first song. Queue ordering is
owned by Heartable; disable inherited native shuffle/repeat when installing it.
Preserve position and pause state when changing modes. Do not briefly start a
paused Spotify song just to update its queue: defer installation until Play.
Native queues contain one provider at a time; mixed-provider boundaries require
an active Heartable session. `AppleMusicQueue` resolves its first song immediately
and batches the remaining native entries, guarded by a cancellation generation.
Never use a MusicKit queue-entry ID as a provider song ID.

`AudioSettings` controls only Heartable's direct streams: gain and crossfade
duration. Preserve the previous fixed-volume preference when migrating; never
label a static gain as loudness normalization. Apply volume changes to both
players during a fade, and settle cancelled fades before pause/resume so a track
does not remain at partial gain. Provider-owned audio effects stay with Spotify
and Apple Music.

## Library and cache rules

The library is cache-first and stale-while-revalidate:

1. Render a valid account-scoped snapshot immediately.
2. Check provider revision/freshness in the background.
3. Apply a coherent replacement only when data changed.
4. Keep the last good snapshot when a provider request fails.

`LibrarySessionStore` owns Home library state above the tab hierarchy. Home
navigation must never own or await playlist traversal or artist aggregation;
tab selection renders cached core content while derived indexes reconcile in
the authenticated app shell.

The first authoritative provider sync must traverse the full playlist library
so artist/song indexes are accurate. Subsequent loads should use change
metadata and targeted refreshes. Never mix data between accounts.

Search supports explicit content-type and provider filters. Artist-page sorting
is limited to A–Z and Song Count.

Playlist detail alone enables landscape rotation for a song-cover browser: one
card per track occurrence, in the selected list order (not grouped by album).
Retain the portrait list and its scroll position while browsing covers. Reuse
the existing artwork cache and playback router; rotation never starts a sync.
The landscape presentation is a packed vinyl shelf with stable-width scroll
targets, a pulled-forward selected sleeve, and one shared track/play caption.

Backup names are local date and time only by default, persisted at
capture time, and editable through Rename in the backup actions drawer. Never
replace a user's custom name automatically. The first usable library gets a
baseline even with manual cadence; the server-side initial_backup_at marker
prevents reinstalls or an explicit data clear from recreating that baseline.
Clear generated music data with clear_my_music_data(expected_owner), never a
sequence of paginated child-ID deletes. Suspend backup/listening writes while
clearing, invalidate relevant caches, and preserve identity/provider pairings.

Backups must remain inspectable in-app: users can drill from a snapshot into its
playlists and tracks. The Changes view compares each snapshot with its immediate
predecessor and exposes added/removed song occurrences with collection context.
Capture playlist images, track album-art URLs, and durations in the existing
snapshot columns. CSV export/import must preserve optional artwork metadata and
provider-native URIs. Never replace historical track content with today's library.
Use stable source playlist IDs for comparisons with a legacy-name fallback.
Every snapshot page must load successfully before diffing; partial reads are
errors, not removals. Exclude and visibly name services not present in both
snapshots, since absence cannot prove deletion from that service.

## Listening stats

A listen is an actual qualified play, not library presence, album metadata, or
a provider import. Keep scopes explicit:

- **Heartable**: qualified plays observed by Heartable
- **Spotify**: Spotify-specific source data where the API exposes it
- **Apple Music**: Apple-specific source data where available

Do not inflate Heartable totals with Apple Music library items. Cross-provider
deduplication should combine recordings only after source counts are correctly
derived.

On first opening Top Tracks, `TopTracksSelection` prefers a populated cache
(Spotify first), then a connected Spotify source if caches are empty. If that
automatic source has no results, try another supported source. Keep a deliberate
selection for the screen session, even when empty; drop it only if the source is
no longer available. Auto-fallback must not create overlapping view-load tasks or
delay painting already-cached results. Never expose Apple library rows as stats.

## Social and profile

Friend activity has two layers:

- live now-playing state
- durable historical plays from the qualified play ledger

Reactions are user-owned, RLS-protected, and attached to durable activity.
Friends, requests, chats, deep links, and shared mixtapes must work after
sign-out/sign-in account transitions.

Profiles are fully editable. Public modules and featured playlists use saved
visibility/order. Selection limits must be explicit: either allow more items or
grey out additional choices at the cap. Profile edits should update `MeStore`
immediately, then reconcile with the backend.

Profile photos share one resize/upload/backend-update pipeline and support
Photo Library, Camera, and Files.

## UI and accessibility

- Root pages use `HeartablePageHeader` and the subtitle copy in `AppTab`:
  lowercase, short comma-separated phrases without a trailing period.
- Use semantic palette tokens; do not hard-code unrelated tints into the tab
  bar, sheets, or alerts.
- Prefer the warmer Library/Profile visual language for playlist detail,
  listening history, friend profiles, and account surfaces.
- Use shared back/down controls and consistent full-player/lyrics dismissal.
- Route all transient feedback through `BannerCenter` as an app-wide Heartable
  notification. `BannerCenter` delegates to Apple's notification system; never
  add screen-local toasts, snackbars, overlays, or duplicate playback feedback.
- Navigation pushes use the shared back chevron. Option drawers use the native
  drag handle and swipe-to-dismiss, without redundant Close/down/x buttons.
  Use `HeartableDrawer` for content-fitted menus and confirmations, and
  `heartableSheetChrome` for theme coverage. Single selections close the menu;
  editable forms retain their Save action. Full player/lyrics keep matched controls.
- iPhone drawers need explicit content-height detents, not only
  `presentationSizing(.fitted)`. Measure intrinsic content, let iOS clamp to the
  available height, and retain scrolling for large menus/accessibility text.
  `HeartableReorderSheet` provides native reorder actions without full-screen
  empty space for short lists. Keep the drawer layout regression tests.
- Use a single centered confirmation component for destructive or account actions.
- Every icon-only control needs an accessibility label and a minimum 44-point
  hit target.
- Loading should preserve useful cached content. Avoid splash loops,
  spinner-only screens, flickering artwork, and layout shifts caused by focus.

## Secrets and backend

Local secrets live only in ignored `Secrets.xcconfig`:

- required: `SUPABASE_HOST`, `SUPABASE_ANON_KEY`, `SPOTIFY_CLIENT_ID`
- optional: `LASTFM_API_KEY`, `LASTFM_USER`

Xcode Cloud stores the same required values as secret environment variables.
`ci_scripts/ci_post_clone.sh` must fail before compilation when a required value
is missing.

Supabase schema changes must be ordered migrations. Before shipping:

```sh
supabase migration list
supabase db lint --linked --schema public --level error --fail-on error
supabase db push --dry-run
```

Apply the migration before releasing a client that calls its RPC or table.
Policies must be account/friend scoped and safe to reapply in a repaired
migration history.

## Verification and release

For every source change:

```sh
xcodegen generate
xcodebuild \
  -project Heartable.xcodeproj \
  -scheme Heartable \
  -destination 'generic/platform=iOS Simulator' \
  test
```

For release work, follow `docs/RELEASE.md`. A build is not shipped merely
because compilation succeeded: confirm migrations, signing, archive upload,
TestFlight processing, launch metadata, privacy disclosures, age rating,
review access, and the public testing state.
