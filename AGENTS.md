# Heartable engineering guide

The product constraints and engineering contracts that every change to the app
must keep. `README.md` covers what the app does and how to run it; this file
covers how it is built.

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

Backup CSV `snapshot_created_at` is the capture date, not the import date.
Preserve it on insert; legacy files require a user-selected original date.
Never infer it from downloaded-file timestamps or track-added dates.

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
5. The same `RootView` bootstrap hydrates cached library content (never a tab
   view's task, which has no defined order against the account reset); the app
   shell refreshes it only after provider restoration reaches a coherent state.
   An empty paired set is a prune: never pass one to a library sync before
   `ProvidersStore.hasRefreshed`, and never stamp freshness on a pass in which
   no provider answered.

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

Only Apple Music, Spotify, Plex, and Jellyfin are library connections. Last.fm,
when configured, is a separate history connection. Audius and Deezer have no search paths; their playback adapters remain only for
previously saved tracks. Radio is a separate curated station catalog, not a pairing.
Music Services displays only the four library connections; no public-search,
radio, history, or Coming Soon section belongs on that screen.
Never include public charts in library hydration, account restoration, or stats.
Music search queries only connected Spotify, Apple Music, Plex, and Jellyfin
libraries. Start with each connected service selected, allow individual toggles,
and provide no All selection button. The source drawer contains only connected
services; profiles and stations are independent result categories. Search choices
do not change account pairings, and reset with the account shell.
Profiles and radio remain available through their dedicated search controls.

All provider content normalizes into `UnifiedTrack`, `UnifiedPlaylist`, and
related shared models. Track identity must deduplicate the same recording across
services without merging unrelated editions.

Playback starts through the provider that owns the selected track:

- Apple Music uses `ApplicationMusicPlayer`.
- Spotify uses Spotify Connect when a usable device exists. `SpotifyAppRemote`
  uses the official SDK to wake the phone player, play the requested URI, and
  return to Heartable when no device is active. A brief app switch is required;
  never promise invisible cold starts. The App Remote playback token stays in memory, must match
  the account-bound Spotify user, and never replaces Web API credentials.
  After a native handoff confirms playback, install Heartable's following songs
  through that SDK connection (shuffle off, repeat off, seek, enqueue), without
  restarting the song through the Web API. Queue setup failure must not turn a
  confirmed song start into a failed/paused player;
  every player refusal must surface Spotify's own reason and the actions it
  marks as disallowed, never a generic "Premium required".
- Providers with legal direct streams use `LocalAudioEngine`.
- A stats-only provider never presents playback controls.

`PlayerStore` is the sole merged now-playing authority. Do not create competing
polling loops in views. Cancel stale starts, activate audio lazily, preserve the
queue and cached playlist data across navigation, and surface actionable errors
without immediately dismissing the player.

`PlayerStore.now` changes on every progress poll. Chrome (the tab shell, native
accessory policy, mini-player row, profile/chat status) observes the
position-free `nowSummary`; only views that draw progress, lyrics, or feed listen
qualification observe `now`, and those stay small leaves. A position tick must
never re-evaluate the TabView or re-host the bottom accessory.

Direct-stream starts are structured, awaited operations: reactivate the audio
session on every start/resume, wait for actual playback or a bounded error, and
cancel obsolete generations on pause/stop. Never launch a detached/deferred
start from a provider adapter or expose credential-bearing AVFoundation errors.
An explicit pending track wins now-playing selection over stale old-provider
polls. A failed Spotify pause aborts a handoff; after SDK wake, retry only the
short Connect-device propagation gap, not authentication failures.

Playback modes are In order and ordinary Shuffle. Do not restore weighted
shuffle, boost/downvote controls, or per-song weight synchronization.

`PlaybackQueue` identifies occurrences, not just URIs. Shuffle must install the
whole selected queue, not merely choose a random first song. Queue ordering is
owned by Heartable; disable inherited native shuffle/repeat when installing it.
Spotify control calls target the device that received Play and verify both
settings by readback; Spotify does not guarantee cross-endpoint execution order.
Preserve position and pause state when changing modes. Do not briefly start a
paused Spotify song just to update its queue: defer installation until Play.
Native queues contain one provider at a time; mixed-provider boundaries require
an active Heartable session. `AppleMusicQueue` resolves its first song immediately
and batches the remaining native entries, guarded by a cancellation generation.
Never use a MusicKit queue-entry ID as a provider song ID.

`AudioSettings` controls only Heartable's direct streams: gain and crossfade
duration. There is no Sounds settings screen; the values come from stored
defaults and must not be re-exposed as a panel. Preserve the previous fixed-volume preference when migrating; never
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

Merge refresh results independently per provider. `ProviderRead.success([])`
means a verified empty collection; `.unavailable` must preserve that provider's
last snapshot and playlist occurrences. Another service succeeding is never
permission to prune a failed service. Spotify metadata honors Retry-After across
reads; cached playback URIs remain usable without waiting for metadata refresh.

Derived library caches survive updates. Re-deriving them is a full provider
pull (hundreds of Spotify pages plus a playlist traversal), which is what trips
Spotify's rate limiter and blanks the Library, stats and backups for the whole
cooldown. `LibraryLaunchGuard` therefore discards caches only when a decode
marker was left raised by a previous run, meaning the app died while decoding.
There are two markers with two blast radii: the library marker covers the
decode of the liked/top/playlist-catalog cache and, if found raised, clears
every derived cache; the playlist-index marker covers only the decode of the
playlist-content index and, if found raised, clears only that directory, so
Home still paints from the surviving caches and no provider re-pull is needed.
Never extend either marker over the provider sync, which runs for minutes and
is routinely killed by the user or Xcode, and never clear caches on a build
change. Identity, pairings, Keychain items, backups and appearance are never
touched by this path.

Spotify's Retry-After cooldown persists across launches (`SpotifyReadBackoff`),
paged pulls leave a small gap between pages. Every Retry-After header is parsed
by `RetryAfter`: finite, never negative, at most 24 hours, and a stored cooldown
beyond that is ignored, because the value reaches `Int(...)`/`Duration`
conversions that trap. While the cooldown is active the playlist indexer skips
Spotify playlists instead of failing each one instantly. Browse, artist-index, and friend-playlist readers share a
two-request scheduler; automatic indexing uses one slot so visible navigation
can use the other. Requests are shared by subscribers and stop after the last
subscriber cancels. Optional indexing pauses when the scene is inactive. When a requested service cannot answer, `LibraryStore.providerNotice`
names it inline in the Library (with Spotify's resume time); cached content
stays on screen. Playlists persist to the cache as soon as they publish.

### Library memory model

Playlist contents are disk-backed. Startup reads a small versioned metadata
manifest; it does not retain every playlist's tracks. The recent-screen cache
holds at most three playlists and 12,000 track occurrences (one oversized
playlist may occupy the cache alone). Reads during view rendering are pure;
loading and eviction happen outside `body`.

- v2 playlist files remain readable. v1 monolithic caches migrate one entry at a
  time through a bounded streaming reader. Keep the original until every new
  file and manifest has been written successfully.
- Artist indexing reads playlist files one at a time. LibraryStore's compact
  unique-track projection and occurrence references preserve complete artist
  attribution and counts; MasterLibraryStore derives search data from it and
  must never independently refetch libraries or resurrect authoritative removals.
  These projections still scale with library size; do not claim constant total
  app memory.
- Cached playlist content publishes before network reconciliation. Global
  scheduling applies to visible, indexer, and transient friend reads. A canceled
  subscriber cannot cancel another screen's or indexer's shared request.
- Playlist display grows in windows of 100 rows as the user scrolls, at most once
  per appearance of the load-more row and only if it stays on screen briefly; a
  fling or scrubber drag must never cascade through the whole playlist. Sorting is
  computed once per content/order revision. Playback and landscape cover browsing
  keep the complete ordered playlist, including repeated song occurrences.
- Artwork disk hits, network reads and decodes share a four-operation budget;
  visible covers outrank prefetch. Keep decoded and disk caches bounded. Warm
  visible artwork as soon as core cached library data is published.
- An artist page lazily realizes its playlist sections. Listening stats remain
  source-specific and must never count library membership as observed listening.
- Library cache serialization still uses LibraryCacheIO. Only complete successful
  provider reads replace durable playlist content. Failure retains offline songs,
  artwork and previous revision metadata.

Footprint is logged at the start and end of cache hydration and at the end of a
sync and recorded through `DiagnosticsStore`, so a tester can share the numbers
from the Diagnostics screen without waiting for MetricKit delivery.

`LibrarySessionStore` owns Home library state above the tab hierarchy. Home
navigation must never own or await playlist traversal or artist aggregation;
tab selection renders cached core content while derived indexes reconcile in
the authenticated app shell.

The first authoritative provider sync must traverse the full playlist library
so artist/song indexes are accurate. Subsequent loads should use change
metadata and targeted refreshes. Never mix data between accounts.

Search supports explicit content-type and provider filters. Artist-page sorting
is limited to A–Z and Song Count.

Turning a visible playlist sideways reveals its song-cover browser: one
card per track occurrence, in the selected list order (not grouped by album).
Retain the portrait list and its scroll position while browsing covers. Reuse
the existing artwork cache and playback router; rotation never starts a sync.
The landscape presentation is a two-sided cover-flow shelf with stable-width
scroll targets and a side caption, sized inside the native chrome's content
area. Never wrap the entire shelf in a vertical scroller with a full-page
minimum height: it lets the player overlap the selected cover. Compare sleeve
and viewport geometry in the same coordinate space; scroll-content margins
change the built-in scroll coordinate origin. First/last targets must center.
The visible playlist enables portrait and landscape; rotating back restores its
list without a modal or mode button. The native tab bar and mini-player remain
available. Reserve the player accessory for the whole visible playlist lifetime,
including idle playback, and disable tab-bar minimization there. On iOS 26 the
tab bar never minimizes: that release re-hosts the accessory on every
inline/expanded change, the UIKit-layout → SwiftUI path in the iOS 26.6.2
watchdogs. Playlist visibility is published only on real visible/hidden
transitions, never on repeated appear callbacks. Starting/stopping
playback must change only accessory content, never the shelf viewport or mode.
Measure the native player at the stable tab shell and bound the landscape canvas
above that frame in global coordinates. Navigation can transiently propose a
taller area during rotation; pass the bounded size through to the shelf math
rather than letting nested geometry readers independently size the covers.
Regression tests must check the rendered ledge stays above the player through
repeated portrait/landscape changes, including oversized safe-area proposals.
Native initial/resize anchors must center the selected occurrence; do not use a
delayed scroll task that produces a visible correction after rotation.
Playlist Play lives opposite Back; in landscape it starts the selected song
with the whole playlist queue. Do not add a second play action to the caption.
Back and Play use matching native chrome and neutral semantic text tint.

Saved radio stations are account-scoped and survive relaunch. The station catalog
includes WSUM and other broadcasters with verified official HTTPS stream links.
Radio opens from the shortcut beside Library search and remains a station result
category. Keep Playlists/Artists and sort/layout controls on one row. Do not
restore show schedules, broadcast archives, or automatic broadcast song matching.
Station playback resolves a canonical ID; never trust stream URLs in shared tracks.

Gift mixtapes start from a friend's profile or the + action in Chats and
conversations, not a separate Library entry. Draft metadata and images stay owner-only until explicit Send atomically
grants recipient access. New media uses the private `mixtape-gifts` bucket and
stable references; generate short-lived signed URLs for display. Never persist
provider credentials in a gift. Apply and validate the matching migration before
releasing the client. Friend gifts remain editable; automatic cross-provider
recording resolution is not implemented.
Creation opens an untitled draft without a title prompt. Saved mixtapes are
reachable from Chats. Owner-only deletion requires a themed confirmation and
verified delete readback; tracks/shares/link snapshots cascade with the parent.
The song picker supports an ordered multi-selection across queries, cache-first
suggestions, existing-song exclusion, and stable insertion IDs on retries.
Track mutation failures must never be silently swallowed or presented as saved.

External links publish an explicit snapshot, never a live view of a private draft.
Only the owner can publish/update/revoke. A 256-bit bearer token lives in the web
URL fragment; the public Edge endpoint accepts it in a bounded POST body, looks
up its hash with server-only privileges, and signs snapshot media for 60 seconds.
Never log tokens or snapshot contents, cache link responses, expose private
provider URLs, or grant anonymous table/RPC access. Revoking removes future access,
not already downloaded copies. The read-only native sheet also works before login.
The browser viewer's canonical source is `web/mixtapes` in this repository; its
Sites delivery repository is a generated deployment mirror, not another GitHub repo.
Do not advertise an App Store/public TestFlight download until one actually exists.

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
New captures insert `capture_complete = false` and publish it only after every
child insert succeeds. Pending captures never appear in history or satisfy the
initial-backup check. Validate detail counts before caching; refreshing history
also refreshes expanded contents so an early legacy read cannot remain partial.
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

Onboarding's Spotify recent-history import uses `provider_play_history`, not
`play_log`. The account marker and at-most-50 rows commit atomically. RLS keeps
them private, and no friend activity/Heartable totals are generated. Import and
clear operations serialize on the same profile row so a late import cannot undo
a deliberate clear. Failed imports leave the marker unset for retry; never
silently substitute top rankings or library contents for recent play events.

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
Changing the time range pins the currently visible provider before loading the
new range. An empty or loading All range must never switch Spotify to Heartable.

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

Missing names and photos are seeded atomically from the first linked library
service using `seed_profile_from_first_connection`. `first_linked_at` is immutable
across restoration and disconnect/reconnect; never use the mutable `connected_at`
for first-service selection. Preserve user edits. Services without a profile API
(such as MusicKit) cannot supply a personal name; never substitute a later service
as though it were the first. Missing photos render local initials.

Playlist read failures retain cached content and expose actionable provider status.
Keep music-service diagnostics credential-free, deduplicated, and on-device.

Profile photos share one resize/upload/backend-update pipeline and support
Photo Library, Camera, and Files.

Contact discovery is a manual, one-shot operation, including with previously
granted or limited Contacts access. Read only emails, normalize and hash on-device,
then match confirmed Heartable account emails. Never persist address-book entries,
hashes, or matches; discard results on dismissal/account transition. No phone-only
matching is claimed. The backend excludes self, deleted, unverified, and blocked
accounts, rejects anonymous requests, and stores only a per-account rate-limit
timestamp in a non-exposed schema. Do not silently turn failed lookup into no matches.
Keep contact discovery in Friends. The Chats header has one plain + action with
the accessibility label Create mixtape, with its subtitle below the title/action row; large text stacks
the action instead of squeezing or truncating the heading.

## UI and accessibility

- Root pages use `HeartablePageHeader` and the subtitle copy in `AppTab`:
  lowercase, short comma-separated phrases without a trailing period.
- Use semantic palette tokens; do not hard-code unrelated tints into the tab
  bar, sheets, or alerts.
- Song layout is a device appearance preference: Classic by default, Compact,
  Artwork blocks, Borderless, Liner notes, or Cover grid. Playlist cover grids
  preserve occurrence order and queue indices; rows have no separators in
  Borderless mode. Shared unified/master song rows observe it immediately;
  do not rebuild the queue, change ordering, or alter landscape vinyl mode.
  Compact controls retain at least 44-point hit targets.
- Prefer the warmer Library/Profile visual language for playlist detail,
  listening history, friend profiles, and account surfaces.
- Use shared back/down controls and consistent full-player/lyrics dismissal.
- Route all transient feedback through `BannerCenter` as an app-wide Heartable
  notification. `BannerCenter` delegates to Apple's notification system; never
  add screen-local toasts, snackbars, overlays, or duplicate playback feedback.
- Notification preferences are device-level. Routine confirmations are silent
  and independently mutable; automatic backups and the opt-in Sunday 6 PM
  reminder have separate controls. Errors bypass routine mute, never master/OS
  settings. Recheck foreground policy and serialize reminder reconciliation.
  Do not advertise social push alerts before an APNs pipeline exists.
- The full player displays one themed, two-line lyrics capsule in both orientations,
  not a Lyrics navigation button or embedded lyrics scroller. Show current/next
  synced lines, or an untimed two-line excerpt without invented timestamps.
  Full text remains available through explicit expansion using the same model.
  Portrait reserves space for controls and lyrics first; artwork uses the remainder
  instead of forcing the page to scroll.
  In landscape, use a bounded two-column player with artwork beside track details,
  seeking and transport. Align the title with the cover's top edge and the
  transport row with its bottom edge; lyrics sit above seeking and transport.
  Derive both columns from one footprint, not independent vertical centering.
  Main controls must fit without scrolling; lyrics use a
  compact text preview with expansion. Accessibility text moves that preview
  beneath the artwork to preserve control space. Keep scrubbing/lyrics state
  above the orientation branches and test real control frames at short heights.
- The full player uses the classic artwork layout. No turntable player or Vinyl widget.
- Navigation pushes use the shared back chevron. Option drawers use the native
  drag handle and swipe-to-dismiss, without redundant Close/down/x buttons.
  Use `HeartableDrawer` for content-fitted menus and confirmations, and
  `heartableSheetChrome` for theme coverage. Single selections close the menu;
  editable forms retain their Save action. Full player/lyrics keep matched controls.
- Keep native sheet corner radius at the system default, not a fixed override.
  Paint the full playlist root behind both orientation branches; the invisible
  portrait list cannot be relied on to supply the landscape background.
- iPhone drawers need explicit content-height detents, not only
  `presentationSizing(.fitted)`. Measure intrinsic content, let iOS clamp to the
  available height, and retain scrolling for large menus/accessibility text.
  Grow the detent immediately but shrink it only by more than a text line: iOS 26
  insets partial sheets and lays full-height sheets edge to edge, so content near
  the screen height would otherwise oscillate between two widths forever.
  `HeartableReorderSheet` provides native reorder actions without full-screen
  empty space for short lists. Keep the drawer layout regression tests.
- Use a single centered confirmation component for destructive or account actions.
- Every icon-only control needs an accessibility label and a minimum 44-point
  hit target.
- Loading should preserve useful cached content. Avoid splash loops,
  spinner-only screens, flickering artwork, and layout shifts caused by focus.
- Observed collections notify every reader on any write, even an unchanged one:
  skip no-op Set/Dictionary writes in stores, and keep frequently changing
  values (counts, progress) in small leaf views. Repeating animations stop when
  the scene is not active and animate render-time transforms, not frames.

## Diagnostics

MetricKit is the crash source that does not depend on Apple's TestFlight
pipeline: `PerformanceDiagnostics` persists crash, hang, CPU and disk-write
diagnostics plus days with abnormal exits (memory limit, watchdog) through
`DiagnosticsStore` on the device, and Account shows them with per-report Share.
Memory-limit terminations never produce a crash log anywhere else. Nothing is
uploaded automatically; sharing is the tester's explicit action.

Watchdog (0x8BADF00D) reports carry only the frames of the moment iOS gave up,
usually SwiftUI internals. `MainThreadStallMonitor` pings the main thread from
its own queue; after two unanswered seconds it records content-free breadcrumbs
(screens, sync phases, rate limits, scene changes, handoffs) and main-thread
stack samples to a pending file, updated while the stall lasts. A recovered
stall becomes an "Unresponsive app" entry; an unrecovered one is imported on the
next launch. Breadcrumbs never contain song, playlist, account or credential
data. Add a breadcrumb for any new long-running operation or heavy screen.

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

Follow `docs/RELEASE.md` to ship. A build is not shipped merely because
compilation succeeded: confirm migrations, signing, archive upload, TestFlight
processing, launch metadata, privacy disclosures, age rating, review access,
and the public testing state, and verify the processed build is available to
existing testers before calling it delivered.
