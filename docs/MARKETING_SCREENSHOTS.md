# Heartable marketing screenshots

Capture the app itself using the debug fixtures. The website mixtape image uses
an iPhone 16 Pro Max on iOS 26.5, at its native 1320 × 2868 resolution, with the
existing Midnight theme. Export at 720 × 1564 for the website.

The mixtape fixture opens the editor as a navigation destination, so its Back
button and toolbar are laid out by iOS exactly as they are for a saved mixtape.
It uses the original scenery cover, shared theme colors, and real editor view.
Do not substitute a navigation-root capture or a different iOS major version.

Launch arguments:

```text
-HeartableScreenshot mixtape -heartable_theme midnight
```

The HeartableScreenshots scheme provides `testMixtapePortrait` and the existing
vinyl shelf capture. Set `TEST_RUNNER_SCREENSHOT_DIR` to choose the PNG output
directory when running it through xcodebuild. Simulator status-bar overrides
can standardize the time and battery before capture.

Simulator screenshots omit the physical Dynamic Island. The website adds that
cutout to the device frame only for captures marked `deviceCutout`; screenshots
with a recorded Live Activity already include their own island content.

These fixtures are compiled only in Debug and do not change a user's selected
appearance or the Release onboarding flow.
