# mediaremote-adapter (vendored)

Source: https://github.com/ungive/mediaremote-adapter at commit `73f14ab1568371e6e3c44063f21c34c5e2712c4d`
License: BSD 3-Clause (see `LICENSE`), © 2025 Jonas van den Berg and contributors.

Why: since macOS 15.4, `MediaRemote.framework` returns nothing to non-Apple processes.
The adapter loads it inside `/usr/bin/perl`, which is Apple-signed and still entitled, and
streams system-wide Now Playing (any app, any browser tab using media/Media Session) as JSON.

Only `bin/`, `src/` and `include/` are kept. `src/test` is only needed for a header the
adapter's `test` command imports; the test client itself is not built. `build_app.sh` compiles the framework with clang into
`Contents/Frameworks/MediaRemoteAdapter.framework` and copies the Perl script into
`Contents/Resources`. Files are unmodified.
