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
- Build: **47**
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

Home Screen widgets include Weekly Recap, Friends Listening, and Heartable
Shortcuts. Weekly Recap also supports the rectangular Lock Screen slot;
Shortcuts supports a circular Lock Screen slot. Add them through iOS's widget
gallery after opening Heartable once. Widget taps route into the relevant app
screen; they do not attempt background provider playback.

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
