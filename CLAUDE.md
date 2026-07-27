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
- App Store Connect Apple ID: assigned when the clean Heartable record is created
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
- Supabase Swift as the third-party application dependency
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

State that belongs to a user must either live in a store reset by the account
shell or use an account-scoped persistence key/file. Register provider
credentials and account-owned preferences with `AccountSessionStore`.

## Provider and playback rules

`ProviderCatalog` is the single source of truth for provider availability,
capabilities, setup text, playback tier, and transport route. A provider must
never claim a capability its public API cannot deliver.

All provider content normalizes into `UnifiedTrack`, `UnifiedPlaylist`, and
related shared models. Track identity must deduplicate the same recording across
services without merging unrelated editions.

Playback starts through the provider that owns the selected track:

- Apple Music uses `ApplicationMusicPlayer`.
- Spotify uses Spotify Connect when a usable device exists and falls back to an
  honest open-in-Spotify path when the API cannot start playback.
- Providers with legal direct streams use `LocalAudioEngine`.
- A stats-only provider never presents playback controls.

`PlayerStore` is the sole merged now-playing authority. Do not create competing
polling loops in views. Cancel stale starts, activate audio lazily, preserve the
queue and cached playlist data across navigation, and surface actionable errors
without immediately dismissing the player.

## Library and cache rules

The library is cache-first and stale-while-revalidate:

1. Render a valid account-scoped snapshot immediately.
2. Check provider revision/freshness in the background.
3. Apply a coherent replacement only when data changed.
4. Keep the last good snapshot when a provider request fails.

The first authoritative provider sync must traverse the full playlist library
so artist/song indexes are accurate. Subsequent loads should use change
metadata and targeted refreshes. Never mix data between accounts.

Search supports explicit content-type and provider filters. Artist-page sorting
is limited to A–Z and Song Count.

## Listening stats

A listen is an actual qualified play, not library presence, album metadata, or
a provider import. Keep scopes explicit:

- **Heartable**: qualified plays observed by Heartable
- **Spotify**: Spotify-specific source data where the API exposes it
- **Apple Music**: Apple-specific source data where available

Do not inflate Heartable totals with Apple Music library items. Cross-provider
deduplication should combine recordings only after source counts are correctly
derived.

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

- Use semantic palette tokens; do not hard-code unrelated tints into the tab
  bar, sheets, or alerts.
- Prefer the warmer Library/Profile visual language for playlist detail,
  listening history, friend profiles, and account surfaces.
- Use shared back/down controls and consistent full-player/lyrics dismissal.
- Use in-app banners/toasts for non-destructive feedback and a single centered
  confirmation component for destructive or account actions.
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
