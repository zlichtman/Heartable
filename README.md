# Heartable

**Your music, with love.**

Heartable is a native SwiftUI music hub for people whose listening life spans
more than one service. It combines libraries, playback, listening history,
friends, chats, playlists, mixtapes, profiles, and backups in one warm,
personal interface.

The canonical repository is `zlichtman/Heartable`. The App Store app uses
`com.zlichtman.heartable`; its widget extension uses
`com.zlichtman.heartable.widget`.

## Product map

Heartable keeps five permanent tabs:

1. **Heartable** — listening activity, friends, recaps, and social discovery
2. **Chats** — friend conversations and music sharing
3. **Library** — cross-provider songs, artists, playlists, and search
4. **Backups** — capture, restore, import, and export
5. **Profile** — public profile, listening stats, settings, and account controls

Navigation titles are hidden by default but can be enabled in Appearance.
Backups remains a first-class tab, and the Heartable tab keeps the Heartable
name.

## Current release

- Marketing version: **1.0.0**
- Build: **52**
- Minimum OS: **iOS 26**
- Toolchain: **Swift 6**, SwiftUI, XcodeGen, Swift Package Manager
- Backend: **Supabase**
- CI/CD: **Xcode Cloud → App Store Connect → TestFlight**

## Architecture

```text
Heartable/
  App/                 lifecycle, authentication gate, five-tab shell
  Design/              themes, typography, shared UI components
  Features/            screen-level product modules
  Models/              normalized music and social models
  Networking/          shared HTTP behavior
  Services/
    Auth/              Heartable account session
    Backend/           typed Supabase operations
    Library/           cross-provider identity, indexing, and cache policy
    Player/            playback state and transport routing
    Providers/         music-service adapters and catalog
    Recap/             weekly listening recap and archive
    Social/            listening activity and friend sync
  Shared/              app/widget shared snapshot models
HeartableWidget/       recap, friend activity, and quick-access widgets
HeartableTests/        domain and regression tests
supabase/migrations/   ordered backend contracts
ci_scripts/            Xcode Cloud bootstrap
Tools/                 reproducible asset tooling
```

`project.yml` is the source of truth for targets and build settings. The
generated `Heartable.xcodeproj` is committed so Xcode Cloud can build without a
project-generation dependency.

Build 46 adds landscape song-cover browsing inside playlists, compact themed
option drawers, shared root-page headers, and backup artwork preservation
(including CSV round trips). Existing backups without saved artwork retain
placeholders; new captures preserve the provider's cover URLs.

Build 47 gives iPhone option drawers explicit content-sized detents, including
short reorder menus, with scrollable overflow and full theme coverage. Backup
changes identify the source playlist and service, preserve duplicate occurrences,
and use stable playlist IDs so renames do not look like song removals. Comparisons
require complete paginated reads; services missing from either backup are excluded
and named rather than presented as mass deletions.

Playback now owns an occurrence-aware queue. Playlist, artist, Heartables, and
mixtape selections send their actual ordered/shuffled/weighted queue to the player.
Apple Music queues retain native song IDs and load the remaining songs in batches.
Spotify uses its official iOS SDK to wake the phone player when Connect has no
device, then installs the Heartable queue. Spotify requires a brief app switch;
it cannot be cold-started invisibly on iOS. Same-service native queues continue in
the background; mixed-service boundaries require Heartable to be active. Provider
subscription, installation, and API capability limits still apply.

Build 48 opens Top Tracks on a source with cached stats, preferring Spotify on
first open when both sources have data or when a new account has no cache. Empty
automatic selections fall back to another supported stats source; deliberate
source selections stay put. Listening History uses one native toolbar trash
button. Sounds adds live direct-stream volume and adjustable 1–8 second
crossfades, preserving previous volume preferences without claiming loudness
normalization or control over Spotify/Apple Music audio effects.

Build 50 turns landscape cover browsing into a packed vinyl shelf. Playback
handoffs retain the requested track while starting, await real direct-stream
playback, reactivate interrupted audio sessions, and cancel stale starts.
Spotify cold starts allow a bounded Connect-device propagation wait after the
SDK handoff, and failed outgoing Spotify pauses stop the switch. These changes
do not remove provider restrictions or replace physical-device beta checks.

Services now separate connected music libraries, listening-history sources, and
search/radio catalogs, with one Coming soon group for unimplemented adapters.
WSUM's three stations are available as an optional search source. The first usable library
gets an automatic backup; subsequent backups honor the chosen cadence. New
backup names are date/time only and can be renamed from the actions drawer.
Clearing music data uses an account-checked database transaction, repairs
recursive mixtape-sharing policies, and invalidates related local projections.
See [the provider review and gift-mixtape design](docs/PROVIDER_AND_MIXTAPE_PLAN.md)
for remaining integrations and platform limits.

Home Screen widgets include Weekly Recap, Friends Listening, and Heartable
Shortcuts. Weekly Recap also supports the rectangular Lock Screen slot;
Shortcuts supports a circular Lock Screen slot. Add them through iOS's widget
gallery after opening Heartable once. Widget taps route into the relevant app
screen; they do not attempt background provider playback.

Build 51 makes all three widgets follow the selected app theme, including custom
palettes and edits. Appearance is stored separately from private widget content,
so signing out clears listening data without resetting the widget's colors.
Theme changes request a WidgetKit timeline refresh; iOS controls refresh timing
and its tinted/clear Home Screen and Lock Screen rendering modes.

Build 52 refines landscape vinyl browsing: a centered sleeve with balanced
perspective on either side, a separate track caption, and no shelf content under
the mini-player. The first/last songs center correctly. Playlist Play stays in
the top-right navigation slot; in vinyl mode it begins at the selected song.

Music providers are Apple Music, Spotify, Plex, and Jellyfin. Audius, Deezer
(previews), and WSUM appear as logo-only public search sources;
they never become account pairings or contribute chart data to personal stats.
Internet Archive, ListenBrainz, Mixcloud, and the general Radio Browser adapter
have been removed.
Search defaults to All: Heartable, connected libraries, and public catalogs/radio.
Its themed Type drawer supports multiple selections and real service
logos, including the installed Heartable icon.

Spotify onboarding imports up to 50 provider-reported recent plays, once per
account, without delaying entry into the app. These private history rows are
marked Spotify and stay separate from Heartable-observed counts and friend
activity. Clearing history also prevents an in-flight import from restoring it.
An existing Spotify connection needs reconnecting to grant the new recent-history
scope. Queue installation now verifies native Shuffle/Repeat state on the device
that received Play instead of assuming accepted commands finished in order.

### Build 55 (release preparation)

Radio opens from the shortcut beside Library search, keeping Playlists/Artists
and sorting on one row. Search uses six controls in two rows: Type, Songs,
Playlists, Artists, Profiles, and Stations. All includes WSUM shows, while
explicit app selections remain scoped. Stations are not listed as songs/artists.
Unsupported provider profile searches explain the limitation and offer Heartable
profile search instead of a misleading empty result. Music Services no longer
lists radio or a Coming Soon section; radio remains in Library and search.

Validation: 227 tests passed, Simulator Release and release identity checks
passed, and warm/dark search-control screenshots were inspected. The live WSUM
schedule returned Sam's Jams for the query `sam`.

### Build 54 (available to the internal Test group)

Radio now sits beside Playlists and Artists, with a Radio search filter. WSUM
programs have persistent hearts and native recent-broadcast/track-list views.
The Search in drawer uses a compact themed source grid. Backup expansion retains
loaded contents and distinguishes initial loading/errors from verified emptiness.
Spotify playlist counts accept both `items` and legacy `tracks`; missing/null
page items cannot replace a cached collection with an empty response.

Validation: 224 tests passed; the Simulator Release build and identity check
passed. Warm/dark drawer screenshots were inspected. The live WSUM parser
resolved 18 recent broadcasts and 19 latest-broadcast track rows for Sam's Jams.
This does not establish whether a tester's device received Spotify HTTP 429.

### Build 53 (available to the internal Test Group)

- Provider-specific refreshes retain Spotify playlists and cached track order
  during rate limits, even while another service refreshes successfully.
- Lyrics are visible inline in the player, with synced highlighting or scrollable
  plain text. WSUM has saved stations and official show listings; schedule entries
  are not represented as on-demand recordings.
- A friend's profile has a Mixtape plus action: start a private draft, add songs,
  notes and photos, then Send. The private-media/database migration is deployed
  and its owner/recipient privacy checks passed on September 6.
- Notification controls separate silent routine confirmations, automatic backups,
  an opt-in weekly reminder, and sounds. See the [notification audit](docs/NOTIFICATIONS.md).

Build 53 completed Xcode Cloud and TestFlight processing on September 6.
Local validation on September 6: 218 tests passed (including 13 notification
tests), release identity passed, and unsigned generic-iPhone and generic-Simulator
Release builds succeeded. Remote Mixtape rollback-only privacy tests also passed; no test users
remain. Signed distribution and physical-device acceptance remain release gates.

Account-owned state is namespaced by the Supabase user. Provider pairing intent
is stored in an RLS-protected account manifest, while provider secrets remain in
account-scoped, iCloud-synchronizable Keychain items. A normal sign-out clears
runtime state without disconnecting services; an explicit disconnect removes
the pairing. Widgets receive secret-free snapshots through
`group.com.zlichtman.heartable`; they never initialize Supabase or provider
clients.

Backups retain inspectable playlist and track contents. The in-app Changes view
compares each snapshot to its immediate predecessor and calls out added and
removed song occurrences with their collection context.

## Local setup

Requirements:

- Xcode with the iOS 26 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Create the ignored local configuration:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Set the required values:

- `SUPABASE_HOST`
- `SUPABASE_ANON_KEY`
- `SPOTIFY_CLIENT_ID`

`LASTFM_API_KEY` and `LASTFM_USER` are optional.

Generate and open the project:

```sh
xcodegen generate
open Heartable.xcodeproj
```

## Verification

```sh
xcodegen generate
xcodebuild \
  -project Heartable.xcodeproj \
  -scheme Heartable \
  -destination 'generic/platform=iOS Simulator' \
  test
```

Before a release, also run a signed Release archive or let Xcode Cloud perform
the archive with automatic signing. See [docs/RELEASE.md](docs/RELEASE.md) for
the complete release contract.

## Backend changes

Supabase project `ghmuafydukliccwamkrq` is the system of record. Schema changes
must be additive, migration-backed, linted, and deployed before a client that
uses them ships.

```sh
supabase migration list
supabase db lint --linked --schema public --level error --fail-on error
supabase db push --dry-run
```

Never commit `Secrets.xcconfig`, `.env` files, Apple private keys, provider
tokens, or generated build output.

## App icons

The primary icon is the canonical dark Heartable mark used on launch,
TestFlight, and the App Store. Theme alternates are generated from the palette
definitions:

```sh
swift Tools/generate_app_icons.swift
xcodegen generate
```
