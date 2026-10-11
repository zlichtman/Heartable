# Release

Heartable ships as a private TestFlight beta for demos. Each build is a
reviewed commit on `main`, built by a manually started Xcode Cloud workflow.
Screenshot, website, and documentation changes don't produce a build.

## Identity

| Item | Value |
|---|---|
| Xcode project / scheme | `Heartable.xcodeproj` / `Heartable` |
| Bundle ID | `com.zlichtman.heartable` |
| Apple team | `28LJG7MXT3` |
| Supabase project | `ghmuafydukliccwamkrq` |

## 1. Prepare the commit

1. Start from a clean `main`.
2. Bump `CURRENT_PROJECT_VERSION` in `project.yml` past the latest build in
   App Store Connect. Xcode Cloud assigns its own build numbers, so check
   there, not just the repo.
3. Run `xcodegen generate`.
4. Run `ci_scripts/validate_release_identity.sh`, which lints the plist,
   entitlements, and privacy manifest and rejects tracked private material.
5. Build the Release configuration for the generic iOS Simulator.

## 2. Backend

```sh
supabase migration list
supabase db lint --linked --schema public --level error --fail-on error
supabase db push --dry-run
supabase db push
```

Apply migrations before uploading a client that depends on them, then confirm
local and remote migration versions match.

## 3. Apple and Spotify configuration

- The app uses Sign in with Apple and MusicKit (enabled under the App ID's App
  Services). Signing is automatic.
- The Spotify developer app has the iOS SDK enabled, registers the bundle ID,
  and uses the redirect URI `heartable://callback`. In development mode,
  Spotify only allows accounts added to the app's user list.

## 4. Xcode Cloud

The workflow builds the `Heartable` scheme from `main`, archives for iOS, and
prepares an App Store Connect distribution. It has no automatic start
conditions; start it manually from the release commit.

It needs `SUPABASE_HOST`, `SUPABASE_ANON_KEY`, and `SPOTIFY_CLIENT_ID` as
secret environment variables. `ci_scripts/ci_post_clone.sh` writes
`Config/Secrets.xcconfig` from them and fails before compiling if one is
missing.

## 5. TestFlight

1. Wait for processing and answer export compliance.
2. Smoke-test the processed build on a phone: sign in, connect Spotify and
   Apple Music, play from each, open a cached playlist, add a friend, and send
   a mixtape.
3. Release it to the internal testing group.

A build is done when testers can install it, not when the archive succeeds.
