# Heartable release contract

This is the authoritative release path for Heartable.

## Canonical identity

| Item | Value |
|---|---|
| GitHub | `zlichtman/Heartable` |
| Branch | `main` |
| Xcode project | `Heartable.xcodeproj` |
| Scheme | `Heartable` |
| Apple team | `28LJG7MXT3` |
| App Store Connect ID | `6775338227` |
| App bundle | `com.zlichtman.heartable` |
| Widget bundle | `com.zlichtman.heartable.widget` |
| App Group | `group.com.zlichtman.heartable` |
| Supabase | `ghmuafydukliccwamkrq` |

Do not create another Heartable repository, App Store record, bundle ID, or
Xcode Cloud workflow. TestFlight builds remain on this record; expire obsolete
builds instead of replacing the record.

## 1. Source preflight

1. Confirm `main` is clean.
2. Increment `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Run `xcodegen generate`.
4. Lint plists and entitlements.
5. Run the full unit-test suite.
6. Build a generic Simulator Release configuration.
7. Review `git diff --check`.
8. Confirm no secret, `.p8`, `.env`, local build output, or account cache is
   tracked.

## 2. Backend preflight

```sh
supabase migration list
supabase db lint --linked --schema public --level error --fail-on error
supabase db push --dry-run
```

Apply required migrations before the client upload. Verify the local/remote
migration versions align afterward.

## 3. Apple configuration

The app and widget must both have App Groups enabled and assigned to
`group.com.zlichtman.heartable`. The main app also retains Sign in with
Apple and MusicKit.
Use automatic signing.

Xcode-managed certificates are team-wide. Do not revoke a certificate merely
because it was created by an older workflow; first prove that no unrelated app
or active workflow uses it. Obsolete app-specific provisioning profiles may be
removed after the replacement workflow signs successfully.

## 4. Xcode Cloud

Maintain one active workflow named **Heartable Release**:

- repository: `https://github.com/zlichtman/Heartable.git`
- project: `Heartable.xcodeproj`
- branch condition: `main`
- Xcode/macOS: latest release
- archive platform: iOS
- scheme: `Heartable`
- distribution preparation: App Store Connect
- auto-cancel superseded branch builds: on

Required secret environment variables:

- `SUPABASE_HOST`
- `SUPABASE_ANON_KEY`
- `SPOTIFY_CLIENT_ID`

Optional:

- `LASTFM_API_KEY`
- `LASTFM_USER`

The post-clone script creates `Secrets.xcconfig` and fails if a required value
is absent.

## 5. TestFlight

After the archive succeeds:

1. Wait for App Store Connect processing to finish.
2. Complete export-compliance questions.
3. Verify the build launches, signs in, connects providers, plays supported
   sources, restores cached library content, opens the player, and updates the
   public profile.
4. Assign the build to the internal group first.
5. Add external-test information and a reviewer account.
6. Submit the build for Beta App Review.
7. Enable the public TestFlight link only after approval.

Never call an internal-only build “public.”

## 6. App Store launch gates

Before App Review submission, App Store Connect must contain:

- subtitle, category, description, keywords
- support URL and privacy-policy URL
- current iPhone screenshots
- app privacy disclosures
- age-rating questionnaire
- content-rights declaration
- verified EU trader-status choice
- contact information and a working reviewer account
- review notes explaining provider sign-in and playback limitations
- selected processed build

The first public App Store release should use manual release after approval
until production login, migrations, analytics, and support paths have been
verified against the approved binary.
