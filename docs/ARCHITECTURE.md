# Architecture

## Layout

| Path | Responsibility |
|---|---|
| `Heartable/App` | Lifecycle, auth and onboarding gate, tab shell |
| `Heartable/Design` | Semantic palettes, typography, shared components |
| `Heartable/Features` | Feature-owned views and presentation state |
| `Heartable/Services/Auth` | Heartable session and account namespacing |
| `Heartable/Services/Backend` | Typed Supabase API and DTOs |
| `Heartable/Services/Library` | Normalization, track identity, caching, search |
| `Heartable/Services/Player` | Player state, queues, and transport routing |
| `Heartable/Services/Providers` | One adapter per music service |
| `Heartable/Services/Recap` | Qualified listening aggregation for Weekly Recap |
| `Heartable/Services/Social` | Friend activity, relationships, and now-playing sync |
| `HeartableScreenshots` | UI-test target that captures the demo screenshots |
| `supabase/` | Ordered migrations, SQL tests, and Edge Functions |

`project.yml` is the source of truth for targets and build settings; the
committed `Heartable.xcodeproj` is generated from it.

## State and accounts

Long-lived `@Observable` stores are created in `HeartableApp` and injected into
the view tree; screen-specific state stays in its feature module.

Everything that belongs to a user lives either in a store reset by the account
shell or under an account-scoped persistence key, file, or Keychain item, so
signing into a second account never shows the first account's data.
`AccountSessionStore` owns that namespace.

Startup is one ordered bootstrap in `RootView`:

1. Supabase restores the persisted session immediately and refreshes it in the
   background.
2. `AccountSessionStore` activates that user's namespace before any view sees
   the session.
3. `MeStore` paints the cached profile while fetching the current one.
4. `ProvidersStore` merges the cached and server-side provider pairings, then
   probes the device's credentials.
5. Cached library content hydrates; a provider refresh starts only once
   provider restoration has settled.

A provider pairing (stored with the Heartable account) and a usable device
credential (stored in the Keychain) are separate states. A missing credential
shows **Reconnect** instead of silently disconnecting the service.

## Providers and playback

`ProviderCatalog` is the single source of truth for each service's
capabilities, setup text, and playback route, so the UI never offers an action
a provider's API cannot perform. Apple Music, Spotify, Plex, and Jellyfin are
library connections, and radio is a curated station catalog.

All provider content normalizes into `UnifiedTrack`, `UnifiedPlaylist`, and
related models. Track identity deduplicates the same recording across services
without merging different editions.

`PlayerStore` is the only now-playing authority. Playback starts through the
service that owns the selected song:

- **Apple Music:** `ApplicationMusicPlayer`.
- **Spotify:** Spotify Connect when a device is active; otherwise the official
  App Remote SDK wakes Spotify, starts the requested song, and returns to
  Heartable. The following songs are queued through the same SDK connection.
- **Plex, Jellyfin, radio:** `LocalAudioEngine`, built on AVFoundation, with
  crossfade and gain.

`PlaybackQueue` tracks song occurrences rather than URIs, so a playlist that
repeats a song keeps its order. Shuffle installs the whole shuffled queue, and
native shuffle and repeat are disabled so Heartable owns the order. Each start
is a cancellable, awaited operation: a stale start or provider poll can never
overwrite a newer request, and a Spotify Play response is only treated as
success once the requested song is confirmed on the target device.

Chrome that doesn't draw progress (the tab shell, mini-player row, profile
status) observes a position-free `nowSummary`, so per-second progress updates
re-render only the small views that display them.

## Library and caching

The library is cache-first and stale-while-revalidate:

1. Render the account's cached snapshot immediately.
2. Check each provider for changes in the background.
3. Apply a replacement only when data changed.
4. Keep the last good snapshot when a provider request fails.

Results merge per provider. `ProviderRead.success([])` means a verified empty
collection, while `.unavailable` preserves that provider's cached data, so one
service failing never prunes another's content.

Playlist contents are disk-backed: launch reads a small manifest, and a bounded
in-memory cache holds only recently viewed playlists. Lists grow in windows of
100 rows as you scroll, and artwork loads share a small concurrency budget in
which visible covers outrank prefetch.

Spotify rate limits are respected across launches: `Retry-After` cooldowns
persist, and background indexing yields to visible navigation through a shared
two-slot request scheduler. Derived caches survive app updates because
rebuilding them means a full provider pull; `LibraryLaunchGuard` discards a
cache only if the previous run died while decoding it.

## Backups

A backup captures every playlist and track occurrence with artwork, duration,
and provider URIs. Captures are written with `capture_complete = false` and
published only after every child row is inserted, so a partial capture never
appears in history. The Changes view diffs each snapshot against its
predecessor using stable playlist IDs, refuses to diff partial reads, and names
any service missing from either snapshot instead of reporting its songs as
removed. CSV export and import preserve artwork and provider URIs.

## Listening stats and social

A listen is an observed, qualified play, never library membership or a
provider's import. Heartable, Spotify, and Apple Music stats stay
source-specific.

Friend activity combines live now-playing state with durable play history.
Friends are found through in-app search and added with friend requests.
Reactions, friendships, and mixtapes are protected by row-level security.

Every mixtape is made for a friend, from the Mixtapes tab or the friend's
profile. It stays a private draft until **Send** atomically grants the
recipient access, and its media lives in a private Storage bucket behind
short-lived signed URLs. Mixtapes never leave the app; there are no public
links.

## Feedback

All transient feedback goes through `BannerCenter`, which shows an in-app toast
above whatever is on screen, including sheets, and coalesces repeated messages.
The only system notification is the opt-in Sunday Weekly Recap reminder.

## Diagnostics

`PerformanceDiagnostics` records MetricKit crash, hang, CPU, and disk-write
reports on the device. `MainThreadStallMonitor` pings the main thread from its
own queue; after two seconds without an answer it records content-free
breadcrumbs and main-thread stack samples, so watchdog terminations come with
context. Nothing is uploaded automatically; the Diagnostics screen lets a
tester share a report explicitly.

## Backend

Supabase schema changes are ordered migrations under `supabase/migrations`,
with rollback-only SQL tests under `supabase/tests`. Every table and RPC is
scoped to the account or its accepted friends. Secrets live only in the ignored
`Config/Secrets.xcconfig` locally and in Xcode Cloud's secret environment
variables; `ci_scripts/ci_post_clone.sh` fails the build if one is missing.

## Verification

Changes are verified by building for the simulator and checking behavior on a
physical iPhone, since provider sign-in, authenticated playback, and app
switching can't run in the simulator:

```sh
xcodegen generate
xcodebuild -project Heartable.xcodeproj -scheme Heartable \
  -destination 'generic/platform=iOS Simulator' build
```

The SQL tests under `supabase/tests` run inside rolled-back transactions and
cover the database's access rules.
