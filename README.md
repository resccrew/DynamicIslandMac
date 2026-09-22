# Dynamic Island for Mac

A menu-bar-notch "island" for macOS: Now Playing for Spotify/Apple Music, a
matching card on the lock screen with karaoke lyrics, and device-connected
notices.

No sandboxing, no Developer ID — built to run from source, ad-hoc signed.

## Build & run

```sh
./build_app.sh --install
```

Builds a release binary, packages it as `Dynamic Island.app`, ad-hoc signs it,
and installs it into `/Applications`.

Run `./build_app.sh` alone to just build into `./build` without installing.

Requires Xcode (not just the Command Line Tools) — the lock-screen overlay and
`symbolEffect` rely on things the bare CLT toolchain doesn't ship.

## What's inside

- `IslandView` / `IslandWindowController` — the notch-shaped island itself,
  geometry described in `NotchShape.swift`
- `LockScreenView` / `LockScreenWindowController` — the Now Playing card drawn
  over the lock screen via a private window-server space (`SkyLightSpace.swift`)
- `AppleScriptNowPlaying` / `NowPlayingPoller` — reads Spotify/Music over
  AppleScript (no public "now playing" API exists for third-party apps)
- `LyricsProvider` — synced lyrics from the open [LRCLIB](https://lrclib.net) API
- `DeviceMonitors` / `BluetoothDeviceInfo` — charger and Bluetooth audio
  connect/disconnect notices, battery level and exact model via
  `system_profiler SPBluetoothDataType`

## Known limitations

- Liking a track only works in Apple Music. Spotify exposes "starred"
  read-only over AppleScript and has no scriptable "like" command; doing it
  for real needs Spotify's Web API with a user's own OAuth login, which isn't
  wired up here.
- No code signing certificate, so macOS will show a Gatekeeper warning on a
  freshly downloaded copy. Building from source avoids that entirely (a
  locally-built binary isn't quarantined).
- The lock-screen overlay and the Bluetooth-battery/model lookup lean on
  private window-server behaviour and Apple's own `system_profiler`,
  respectively — both are what's actually available for this kind of feature
  without a paid Developer ID, but neither is a documented public API and
  either could change with a macOS update.
