# Providers and gift mixtapes

Reviewed September 6, 2026. This separates implemented adapters from proposed work;
an upstream API having a feature does not mean Heartable implements it.

## What belongs where

| Section | Services | Current Heartable behavior |
|---|---|---|
| Music libraries | Spotify, Apple Music, Plex, Jellyfin | Connected libraries and playlists; playback through Connect/MusicKit or direct server streams. Jellyfin favorites are supported; Plex favorites are not. |
| Listening history | Last.fm (when configured) | Read listening statistics; not an audio player. Also supplies loved tracks. |
| Search & radio | Audius, Deezer, WSUM | Opt-in discovery sources, not paired library accounts. Audius plays full streams, Deezer plays previews, and WSUM provides live radio. |
| Coming soon | SoundCloud, TIDAL, Bandcamp, Qobuz, YouTube Music, Amazon Music, Pandora | No connection buttons until a real, tested adapter exists. Existing provider identifiers stay stable. |

Radio includes WSUM 91.7 FM, Freeflow, and Sports, using the station's official
HTTPS streams. Station listening is visible as now playing but is not counted
as repeated song listens. Radio browse/search includes persistent station/program
hearts (account-scoped on this device), the official Spinitron show calendar,
and native recent-broadcast and track-log pages for all listed shows. Hearted
programs sort first. Track logs are not replay recordings; live listening is
offered during airtime. Schedule/page failures retain the last successful cache.
[WSUM](https://wsum.org/), [official calendar](https://spinitron.com/WSUM/calendar?layout=1)

Internet Archive, ListenBrainz, Mixcloud, and the general Radio Browser adapter
are removed from the active catalog. Legacy raw identifiers remain decodable.

### Worth adding next

1. **Bandcamp collection access:** Bandcamp announced a Subsonic beta in July
   2026 with collection streaming/downloads and playlist management. This is a
   substantially better fit than scraping the store. Implement an OpenSubsonic
   adapter using user-generated credentials, namespace its IDs, and verify the
   actual Bandcamp-supported endpoint subset. Do not present a marketplace
   search API or friend's purchased files as part of that access.
   [Bandcamp announcement](https://blog.bandcamp.com/2026/07/16/discover-improvements-and-subsonic-implementation/)
2. **SoundCloud:** supported OAuth, likes, playlists, and playback are a good
   match. Requires an approved/registered application and correct OAuth flow;
   confidential credentials belong on the backend, never in the iOS binary.
   [Official developer documentation](https://developers.soundcloud.com/docs)
3. **TIDAL:** use the official iOS SDK and registered OAuth client, with the
   required subscription/access checks. It needs real-device playback and
   provider-switch verification before appearing as live.
   [Authorization documentation](https://developer.tidal.com/documentation/api-sdk/api-sdk-authorization)
4. **Existing adapters:** add explicit write capabilities separately from read
   capabilities. Prioritize Jellyfin playlist/favorite mutations, then Audius
   account-backed likes/playlists with proper OAuth. Never silently equate Plex
   ratings with favorites or public popularity charts with personal listens.
   [Jellyfin SDK](https://typescript-sdk.jellyfin.org/functions/generated-client.PlaylistApiFp.html),
   [Audius SDK](https://docs.audius.co/sdk/)

Qobuz, Amazon and Pandora require developer/partner access before promising
full playback. A YouTube video embed is not a native YouTube Music audio
integration. These remain unimplemented, not simulated connections.

## Playback contract

Heartable owns the requested track and handoff transaction. It must silence the
previous transport before starting the next one, reject stale callbacks/polls,
wait for actual playback readiness, and expose retryable errors. A failed stop
must not start a second audible provider. Local stream startup is cancellable
and bounded; Spotify Connect activation retries are bounded and device-specific.

Spotify still has a platform limitation: waking a stopped Spotify application
through App Remote requires Spotify's authorization/app-switch lifecycle.
Heartable can initiate it, but cannot promise a cold start that never opens
Spotify. Apple Music uses MusicKit in process; direct-stream services use the
shared audio engine. History-only and browse-only services cannot be players.
[Spotify lifecycle documentation](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle)

Physical beta matrix: cold start, paused player, active player, rapid A→B→A,
expired tokens, missing app/subscription, denied local-network access, offline
stream, Bluetooth/headphone changes, background/foreground, and account switch.
Simulator tests do not prove authenticated third-party playback works.

## Gift mixtapes: next release, backend deployed

The implemented flow begins at the plus on a friend's profile. A private draft
can contain ordered song occurrences, a cover, a dedication, and per-song notes
and photos. Drafts reopen from that profile. Explicit Send verifies friendship
and a nonempty track list, then atomically grants recipient access and records
the send time. A recipient can read and play the gift but cannot edit it.

New media uses the private `mixtape-gifts` bucket and short-lived signed URLs.
Legacy public covers are unchanged. The approved migration and recipient index
were applied on September 6. Rollback-only tests verified private drafts/media,
recipient read-only access after Send, unrelated-user denial, and idempotent
delivery. No fixture users remain. Database lint passes and no migrations remain
pending. Physical-device photo upload and recipient playback still need acceptance
testing against the distributed client.

The current shared tape remains editable by its owner. Sending creates no APNs
push; recipients see it in-app on the sender's profile. Cross-service playback
uses stored provider references and requires the relevant service to be usable.

### Further design work (not implemented)

The gift is a Heartable-owned arrangement, not a Spotify playlist masquerading
as a cross-service object:

- Each occurrence retains its own UUID, including repeated songs. A future Send
  should publish an immutable gift version;
  subsequent edits need a new published version rather than silently changing
  what the friend received.
- A recipient resolves each recording against their own connected services:
  exact provider ID first, then ISRC, then verified artist/title/duration/edition.
  Live, remix, explicit/clean and remastered variants need a visible choice when
  ambiguous. Show Ready, Choose match, or Unavailable; do not play a wrong match.
- Playback routes the next resolved song through the existing handoff coordinator.
  Metadata may be cached; provider tokens and credential-bearing stream URLs may
  never appear in shared payloads.
- Optional Save to Spotify/Apple/Jellyfin is a separate, consented export with a
  preview of matches and omissions. It must not overwrite an existing playlist.

Engineering: keep owner/recipient RLS on metadata and media; add atomic append
and reorder operations with revision checks and idempotency keys. The current
editor's append decoder has been repaired, but its client-side max-position
calculation is not a substitute for multi-device transactional ordering. Sharing
policies now avoid the recursive mixtape/share lookup and enforce the parent
owner through a composite foreign key.

### Local save has two distinct meanings

1. **Keep the mixtape:** persist the permitted metadata and artwork, preserving
   ordering and notes. Validate access when online and clear account-private
   caches at sign-out. Offline metadata does not grant offline audio rights.
2. **Keep playable local audio:** only user-imported files or downloads explicitly
   supported by the source. Import through Files, copy under an account-scoped
   Application Support directory, read metadata off the main thread, and store
   a stable local asset ID—not a security-scoped URL in the shared track.
   Spotify/Apple offline media stays under those providers' control. Sharing
   a mixtape does not redistribute imported or purchased audio files.

## Notifications

The current local-notification audit and category controls are documented in
[NOTIFICATIONS.md](NOTIFICATIONS.md). Remote social push delivery is future work.

### OS notification icons

Heartable calls the supported alternate-app-icon API and persists the confirmed
icon. The system owns notification headers and may retain old icon snapshots;
there is no public per-local-notification app-icon override. Do not fake sender
avatars, delete notification history, or repost old notifications as a workaround.
[Apple notification appearance](https://developer.apple.com/documentation/usernotificationsui/customizing-the-appearance-of-notifications)
