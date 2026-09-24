# Heartable

Your music, with love.

A native iOS app that brings your music libraries, listening activity, and
friends together in one place, whichever services they live on.

**Demo:** https://zlichtman.com/open-source#heartable

## What it does

Five tabs, left to right:

- **Heartable** — a friend activity feed with live now-playing and durable play
  history, reactions, song and friend leaderboards, friend requests, invite
  codes, and one-shot on-device contact discovery.
- **Chats** — direct conversations with friends; the single `+` action creates
  a gift mixtape.
- **Library** — Apple Music, Spotify, Plex, and Jellyfin in one place.
  **Heartables** merges every liked song from every service into one list;
  playlists, folders, and mixtapes browse as a grid or list with custom
  ordering; a Playlists ⇄ Artists toggle shows per-playlist attribution; and
  one search box spans connected-library songs, artists, playlists, people, and
  live radio stations. Playlist detail offers six sorts and six song-row layouts,
  and rotating a playlist to landscape reveals a vinyl cover-flow shelf.
- **Backups** — scheduled and manual snapshots of the whole library, drill-down
  into any snapshot, a Changes view that diffs each snapshot against its
  predecessor at the song level, rename, and CSV import/export that preserves
  artwork and provider URIs.
- **Profile** — an editable public profile with reorderable modules and
  featured playlists, listening history, Weekly Recap, a theme editor with
  matching alternate app icons, layout and notification preferences, Music
  Services connections, and a crash and memory report screen.

Across all of it: one now-playing player with ordered or shuffled
queues and a synced-lyrics capsule; gift mixtapes with songs, notes, and photos
that share to the web through a revocable link; and three home-screen widgets
(Weekly Recap, Friend Activity, Quick Access).

Provider subscriptions and API restrictions apply. Spotify access currently
requires an approved development account. Some playback handoffs require opening
the provider app; cross-service queue transitions require Heartable to be active.

## Run locally

Requires Xcode with the iOS 26 SDK and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Fill in `SUPABASE_HOST`, `SUPABASE_ANON_KEY`, and `SPOTIFY_CLIENT_ID`.
Keep credentials out of Git; never put a server secret in the app.

```sh
xcodegen generate
open Heartable.xcodeproj
```

Choose the **Heartable** scheme and an iPhone simulator. Run tests with
**Product → Test**. Provider sign-in and playback also need a physical iPhone.

`project.yml` defines the project; regenerate the committed Xcode project after
changing it.

## Documentation

- [Engineering guide](AGENTS.md) — architecture, product decisions, and the
  contracts every change must keep
- [Release process](docs/RELEASE.md) — signing, Xcode Cloud, TestFlight, and
  App Store gates
- [Mixtape sharing](docs/MIXTAPE_LINKS.md) — the shared-link contract and its
  Edge Function

Screenshots used on the site live in `Demos/`.

## License

All rights reserved; see [LICENSE](LICENSE). The source is published for
viewing and evaluation.
