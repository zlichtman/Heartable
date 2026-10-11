# Demos

The screenshots shown on the [Heartable project page](https://zlichtman.com/open-source#heartable),
in the order they appear there.

| Image | Shows |
|---|---|
| `heartable-05.webp` | Music services with Apple Music and Spotify connected |
| `heartable-01.webp` | Library: Heartables and every playlist |
| `heartable-02.webp` | Artists ranked by song count |
| `heartable-09.webp` | Backups: schedule, CSV import, and changes between snapshots |
| `heartable-mixtape.webp` | A mixtape as a cassette, with songs from Spotify and Apple Music |
| `heartable-03.webp` | An artist page: every song of theirs in your library |
| `vinyl-beginning-to-blue.jpg`, `vinyl-exile.jpg`, `vinyl-light-theme.jpg` | Vinyl mode: a playlist turned sideways |

`heartable-mixtape.webp` and `vinyl-exile.jpg` are captured from the app's
Debug screenshot fixtures with the **HeartableScreenshots** scheme:

```sh
xcodebuild test -project Heartable.xcodeproj -scheme HeartableScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Set `TEST_RUNNER_SCREENSHOT_DIR` to choose where the PNGs are written. The
fixtures exist only in Debug builds and are opened with the
`-HeartableScreenshot mixtape|friend|vinyl` launch argument.
