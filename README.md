# Heartable

Your music, with love.

A native iOS app that brings your music libraries, listening activity, and
friends together in one place, whichever services they live on.

**Screenshots and demo:** https://zlichtman.com/open-source#heartable

## What it does

Five tabs, left to right:

- **Heartable**: a friend activity feed with live now-playing and durable play
  history, reactions, song and friend leaderboards, and friend requests.
- **Mixtapes**: gift mixtapes with songs from any service, notes, and photos,
  made for a friend and sent to them in the app.
- **Library**: Apple Music, Spotify, Plex, and Jellyfin in one place.
  **Heartables** merges every liked song from every service into one list;
  playlists, folders, and mixtapes browse as a grid or list with custom
  ordering; and one search box spans connected-library songs, artists,
  playlists, people, and live radio. Rotating a playlist to landscape reveals a
  vinyl cover-flow shelf.
- **Backups**: scheduled and manual snapshots of the whole library, drill-down
  into any snapshot, a song-level diff against the previous snapshot, and CSV
  import/export that preserves artwork and provider URIs.
- **Profile**: an editable public profile with reorderable modules and
  featured playlists, listening history, Weekly Recap, a theme editor with
  matching alternate app icons, and an on-device crash and hang report.

Across all of it: one player with ordered or shuffled cross-service queues and
a synced-lyrics capsule.

## How it's built

- SwiftUI and Observation, Swift 6 with complete strict concurrency, iOS 26
- Supabase (Postgres with row-level security, RPCs, Storage, Edge Functions)
- Official Spotify iOS SDK and Web API, MusicKit, and direct streams for Plex
  and Jellyfin
- XcodeGen and Swift Package Manager; Xcode Cloud for TestFlight builds

Every provider normalizes into one set of unified models, and a single
`PlayerStore` routes playback to whichever service owns the selected song. The
library is cache-first: an account-scoped snapshot renders immediately while
providers refresh in the background, and a failed provider read never erases
cached content. See [Architecture](docs/ARCHITECTURE.md) for details.

## Run locally

Requires Xcode with the iOS 26 SDK and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

The app's public Supabase and Spotify identifiers are built in. To point it at
your own backend or Spotify app, copy the example config and fill it in:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then generate and open the project:

```sh
xcodegen generate
open Heartable.xcodeproj
```

Choose the **Heartable** scheme and an iPhone simulator. Provider sign-in and
playback need a physical iPhone.

Heartable is a portfolio project and runs as a private TestFlight beta.
Provider subscriptions and API restrictions apply: Spotify's development mode
allows only a handful of approved accounts.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): app structure, playback, caching, and
  backend contracts
- [Release](docs/RELEASE.md): Xcode Cloud and TestFlight builds

## License

All rights reserved; see [LICENSE](LICENSE). The source is published for
viewing and evaluation.
