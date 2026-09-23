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
- `SystemNowPlaying` / `NowPlayingPoller` — system-wide Now Playing: Spotify, Music,
  **any browser tab playing video/audio** (YouTube, SoundCloud, Twitch, VK, Яндекс Музыка … in
  Chrome, Safari, Arc, Firefox, Yandex Browser) and any other media app. Read through the vendored
  [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, `Vendor/`), since
  macOS 15.4+ only lets Apple-signed processes use MediaRemote; AppleScript to Spotify/Music is the
  fallback. Pages without a cover show the browser/app icon; live streams show LIVE.
- `CallMonitor` — ongoing calls in Telegram, FaceTime, Zoom, Discord, WhatsApp, Slack, Teams,
  Skype, Viber, Signal, Webex or a browser (Meet etc.), detected from which process holds the
  microphone (CoreAudio) and whether a camera is on (CoreMediaIO). Shows the app, call duration,
  mic/camera state and an "open" button. Priority in the island: glance > call > timer > media.
- `SystemTimerMonitor` — the **system Clock (Часы) timer**, started in the Clock app, by Siri or
  a Shortcut: countdown (1:05:09 past an hour), pause state, title, and a "Таймер завершён" glance
  when it goes off. Read from `mobiletimerd`'s unified-log entries (`log show` at launch, then
  `log stream`), since the timer daemon serves only entitled Apple processes; no permissions needed
  (admin user). Pause/cancel stay in Clock — the card has an "Открыть Часы" button.
- Collapsed content (media, timer, call) sits only in the two "ears" beside the camera notch,
  never under it; the timer and call widen the island evenly to fit.
- `LyricsProvider` — synced lyrics from the open [LRCLIB](https://lrclib.net) API

## QA / debug MCP

Debug builds (`./build_app.sh debug`) start a local control server on `127.0.0.1:47800`
(`DebugControlServer.swift`, compiled only under `#if DEBUG` — release builds don't contain it).
The `mcp/` folder is an MCP server that lets Claude drive and check the running app:
read state, inject a fake track or call, send play/pause/next through the real source,
simulate hover/tap/glance/system timer (seconds/paused/title/fire)/lock-screen preview,
screenshot the island (including bursts for animations), and check invariants.

```sh
cd mcp && uv run pytest -q                      # MCP tests
claude mcp add --scope user island -- uv --directory /path/to/DynamicIslandMac/mcp run island-mcp
```

## Known limitations

- Liking a track only works in Apple Music. Spotify exposes "starred"
  read-only over AppleScript and has no scriptable "like" command; doing it
  for real needs Spotify's Web API with a user's own OAuth login, which isn't
  wired up here.
- No code signing certificate, so macOS will show a Gatekeeper warning on a
  freshly downloaded copy. Building from source avoids that entirely (a
  locally-built binary isn't quarantined).
- Call detection sees microphone use, not the call itself: a browser tab using the mic counts
  as a call, and muting inside the app isn't visible.
- System Now Playing depends on `/usr/bin/perl` and the private MediaRemote framework; if a macOS
  update breaks it, the app falls back to AppleScript (Spotify/Music only).
- The lock-screen overlay and the Bluetooth-battery/model lookup lean on
  private window-server behaviour and Apple's own `system_profiler`,
  respectively — both are what's actually available for this kind of feature
  without a paid Developer ID, but neither is a documented public API and
  either could change with a macOS update.
