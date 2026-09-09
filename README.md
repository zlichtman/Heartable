# Heartable

Your music, with love.

A native iOS app that brings your music libraries, listening activity, and
friends together.

## What it does

- Browse Apple Music, Spotify, Plex, and Jellyfin in one library.
- Play music with ordered, shuffled, or weighted queues, inline lyrics, and
  landscape vinyl browsing.
- Chat with friends and share mixtapes made from songs, notes, and photos.
- Back up playlists, inspect changes, and import or export your collection.
- Personalize themes, app icons, track layouts, and widgets.

Provider subscriptions and API restrictions apply. Spotify access currently
requires an approved development account. Some playback handoffs require opening
the provider app; cross-service queue transitions require Heartable to be active.

## How it works

Built with **Swift 6 and SwiftUI** for **iOS 26+**. Provider adapters normalize
music into shared models, while the player routes playback to each service.
Supabase handles accounts, social features, and backups. Cached library data
keeps browsing responsive between refreshes.

- `Heartable/Features` — app screens
- `Heartable/Design` — themes and shared UI
- `Heartable/Services` — providers, playback, caching, and backend integration
- `HeartableWidget` — widgets
- `HeartableTests` — unit and regression tests
- `supabase/migrations` — database schema
- `web/mixtapes` — shared mixtape viewer

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

[Development guide](CLAUDE.md) · [Release process](docs/RELEASE.md) ·
[Mixtape sharing](docs/MIXTAPE_LINKS.md)
