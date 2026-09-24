# Library architecture — 1.0.0 (95)

Large playlist libraries previously combined full resident playlist contents,
overlapping browse/index requests, repeated derived work and artwork decoding.
This release separates durable storage from visible content and places shared
budgets around expensive work. The supplied reports did not contain the brother's
newer large-library crash stack, so these are verified architectural corrections,
not proof of the exact cause of that device's termination.

A subsequently supplied build-88 report from an iPhone17,1 on iOS 26.6.2 records
a background process-exit watchdog (0x8BADF00D): termination exceeded five
seconds. Its attributed thread is in Observation, SwiftUI and AttributeGraph;
the only Heartable frame is near the app entry path. This supports investigating
UI update pressure, but does not identify one source line or establish an
out-of-memory termination. The old playlist getter mutated an observable cache
from view rendering. The replacement is a pure read, covered by a regression
test; lifecycle cancellation and bounded rendering also reduce this pressure.

## Build 91 watchdog follow-up

Aaron's build-91 reports show two scene-update watchdog terminations on
an iPhone17,1 running iOS 26.6.2. The two 11:57 attachments are byte-identical
copies of the same incident (PID 4333); the 11:56 report is a separate process
(PID 4327). Both exceeded ten seconds, with the attributed thread in SwiftUI,
AttributeGraph and UIKit. They do not identify a provider operation, a source
line, or a memory-limit termination. The exact on-device trigger is unconfirmed.

Build 92 removes two concrete sources of render-time invalidation:

- Mini-player geometry no longer writes state at the TabView owner and is no
  longer broadcast as a changing environment value. A stable observable
  measurement is read only by the landscape viewport, ignores subpixel noise,
  and survives native accessory reparenting. Full playback controls remain.
- Custom playlist sorting is a pure projection. Catalog reconciliation persists
  ordering from a change handler, preserving new-item ordering and user moves.

A missed app-level foreground backup trigger bypassed the build-91 readiness
gate. It is removed. The scheduler now requires the shared library session and
repository, checks readiness itself, and rechecks after asynchronous preflight.
Both automatic triggers belong to the authenticated tab shell; manual backups
retain their existing behavior.

These are source-backed corrections and mitigations, not a reproduced diagnosis
of Aaron's exact watchdog. The available simulator runs iOS 27. Real-device
retry on his iOS 26.6.2 library remains required.

## Build 95 watchdog follow-up

Aaron's build-88 and build-91 reports (iPhone17,1, iOS 26.6.2) are watchdog
terminations, not crashes. Their CPU figures are normalized across six cores:
10.1 s of app CPU in the 10-second scene-update window, and 5.0 s in the
5-second exit window, is one core fully busy. The main thread was running
SwiftUI/AttributeGraph/Observation work for the entire window, not waiting.
Both freezes line up with his new account connecting Spotify and running its
first large-library sync. The developer device runs iOS 27, so the exact iOS
26.6.2 trigger is still unconfirmed. Build 92 removed the most likely cause,
the mini-player measurement written back into the tab shell. Build 95 removes
the remaining ways that machinery was driven and adds evidence collection:

- The tab shell, mini-player row and profile/chat status observe the
  position-free `PlayerStore.nowSummary`. A progress poll re-evaluates only the
  progress bar and an invisible listen-qualification leaf, never the TabView or
  its native accessory.
- Playlist visibility notifies the shell only on a real visible/hidden change.
- On iOS 26 the tab bar no longer minimizes, so the accessory is not re-hosted
  on each inline/expanded flip.
- Playlist-index state skips no-op observed writes, and Spotify playlists are
  not walked while Spotify's read cooldown is active. Each skipped instant
  failure used to invalidate every screen reading the repository.
- The playlist load-more row grows once per appearance, and the drawer detent
  has hysteresis against iOS 26's inset/edge-to-edge width change.
- Other fixes: the Artists sort is memoized, Edit Profile's playlist list is
  lazy and no longer starts a full sync, the player visualizer pauses when the
  scene is inactive and animates a transform instead of layout, and profile
  photos decode through ImageIO off the main actor.
- `MainThreadStallMonitor` records breadcrumbs and main-thread stack samples
  for any stall over two seconds, including one that ends in a watchdog. The
  next Diagnostics report names the screen and operation.

Validated on the iOS 26.2 simulator. The same work also fixes several server-data
traps: non-finite or huge Retry-After values, malformed LRC timestamps,
duplicate list identities, and continuation resume/hang paths.

## Loading and memory

- Restore the account-scoped core cache first and warm visible artwork immediately.
- Read a small playlist metadata manifest at startup. Decode playlist files as
  needed; keep at most three recently used playlists and 12,000 occurrences in
  the resident browse cache. One oversized playlist can occupy the cache alone.
- Share two playlist request slots across browsing, indexing and friend reads.
  Background indexing uses one slot, leaving capacity for visible navigation.
  Cancellation releases a subscription; other consumers retain shared work.
- Derive artist data by reading one playlist file at a time. Derive search data
  from that reconciled projection instead of independently fetching the library.
- Sort playlist content once per revision/order. Realize rows in windows of 100,
  retaining the complete playback queue and duplicate occurrences.
- Share four artwork operations across disk reads, downloads and decoding, with
  visible covers taking priority. Keep the existing decoded and disk cache caps.
- Pause optional indexing when the scene becomes inactive; resume unfinished work
  when it becomes active. Automatic backups wait for a successful, complete core
  and playlist-index load. Interrupted or failed loads defer automatic backup.

Cache migration streams the old monolithic document one entry at a time and
keeps the original until migration succeeds. Existing per-playlist files remain
readable. Provider failure retains the last good songs, artwork and revisions;
only complete successful results replace durable content. Account transitions
invalidate pending generations and keep storage scoped to the correct owner.

The compact artist/search projections still scale with library size. A single
large playlist still needs its complete ordered queue in memory. Backup capture
still constructs a full compact snapshot and refreshes provider contents; this
release prevents it from starting during the initial library load, but does not
make backup memory constant. A cold provider download still takes network time.

## Product cleanup

Music search includes only connected Spotify, Apple Music, Plex and Jellyfin
services. Each begins selected, individual toggles remain, and there is no All
selection button. Profile and station search remain separate categories.

Radio contains saved stations and the curated WSUM, KEXP and WFMU station catalog.
Show schedules, archives and broadcast-song matching are removed. Existing
station IDs and saved stations remain compatible. Deezer/Audius search paths are
removed; playback adapters remain for previously saved tracks.

Removed unused secondary library loaders, obsolete weight synchronization,
unreachable sharing UI/API wrappers and other confirmed unused helpers. Moved
screenshot scenery into development-only assets. Removed the two requested fake
mixtape gallery images. Playback, gifts, chats, profiles, backups, themes, widgets
and the landscape cover browser remain supported.

## Validation

The full simulator suite passes: **320 tests, zero failures**. It covers bounded
playlist retention, offline artwork restoration, request sharing/cancellation,
cache migration and corruption, account isolation, complete playback queues,
backup readiness, connected search filters and canonical radio station IDs,
alongside the existing playback, social, backup and layout regression tests.
New UI regressions render a 3,000-song playlist with a bounded initial list while
retaining its full queue, rotate it, verify measurement updates do not redraw
the tab owner, reject subpixel measurement invalidation, preserve custom order
without render-time writes, and reject automatic backup before readiness.

Release checks also require the optimized simulator build, release identity and
secret checks, clean diff formatting, aligned database migrations, schema lint
and a no-change migration dry run. Signed Cloud archive and TestFlight processing
are separate delivery gates. Real-device validation with the affected Spotify
library remains necessary to confirm the observed crash no longer occurs.
