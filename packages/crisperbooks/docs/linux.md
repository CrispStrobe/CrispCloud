# Linux ebook host and packaging

The ebook package supplies an optional inline WebKitGTK host. It uses the same
bundled Foliate reader, publication sanitizer, session bridge and book-byte input
as the other enhanced hosts. Flutter composes the reader texture with its own
toolbars and dialogs. The app calls `probeEbookLinuxHost()` before selecting this
host and retains the portable chapter reader when the host is unavailable or
cannot start.

## Build and runtime dependencies

The native host uses the GTK3 WebKitGTK API **4.1**, version **2.48.4 or newer**.
The hosted native gate targets Ubuntu 24.04 with the distribution's real headers
and runtime. The Linux build jobs install `libwebkit2gtk-4.1-dev` alongside the
existing Flutter GTK development dependencies. Ubuntu publishes this package
for [24.04 LTS](https://packages.ubuntu.com/noble/libwebkit2gtk-4.1-dev).

The minimum includes the upstream fix for a `GtkOffscreenWindow` initialization
crash, documented in the official
[WebKitGTK 2.48.4 release notes](https://webkitgtk.org/2025/07/30/webkitgtk2.48.4-released.html).
Older releases are rejected by the runtime probe even if their APIs appear
compatible. That known older crash is separate from any failure on a newer
runtime, which still requires its own native diagnostics and verification.

`packages/crisp_ebook_reader/linux/CMakeLists.txt` checks for those headers and
**CMake 3.19 or newer**. If either is absent, or `CRISP_EBOOK_WEBKITGTK=OFF` is set,
it compiles a small plugin that reports the enhanced host as unavailable. The application remains
buildable and launchable. GTK, GModule and the enhanced host's epoxy OpenGL
interface are ordinary system dependencies; WebKit and JavaScriptCore are
resolved on demand through `GModule`, with no hard browser-library dependency
in the application or plugin.

The enhanced build also installs `lib/crisp_ebook_webkit_probe` beside the
plugin. This separate executable is linked to the system browser runtime. Its
installation is deferred until after Flutter recreates the bundle, preserving
executable permissions. Keep the helper with the bundle when packaging it;
an absent or non-executable helper makes the enhanced host unavailable.

For an enhanced build on Ubuntu/Debian, install the maintained system package:

```sh
sudo apt-get install libwebkit2gtk-4.1-0
```

Restart CrispCloud after installing or updating the runtime; the native module
probe is cached for the life of the process.

The Debian package recommends `libwebkit2gtk-4.1-0 (>= 2.48.4)`. It is deliberately
an optional recommendation so the portable reader remains usable on an
installation without the browser runtime. Tar and AppImage bundles also use the
system runtime. They do not include a partial copy of WebKit's shared libraries,
subprocesses, resources or sandbox helpers. A self-contained Flatpak/Snap runtime
would need its own complete packaging and validation work.

The host requires Flutter's OpenGL renderer and a graphical session. Mesa's
software OpenGL implementation is exercised in CI. Flutter's distinct
`FLUTTER_LINUX_RENDERER=software` mode does not support these external textures;
the probe reports that limitation and the app uses the portable reader.

The distribution remains responsible for WebKit security updates. WebKit has
[LGPL and BSD portions](https://webkit.org/licensing-webkit/); this integration
does not vendor or modify its engine. That technical packaging choice does not
replace the application's release and license review.

## Isolated startup check

Loading a WebKit shared library does not prove its sandboxed subprocesses can
start. Some environments reject a required namespace or D-Bus proxy operation;
WebKit can treat that as fatal to its embedding process. Before creating a
reader view, the plugin launches the bundled helper with the same graphical
session, ephemeral context, enabled sandbox and view settings. The helper
loads only a fixed trusted page, checks JavaScript execution and verifies a
painted snapshot. It receives no publication, URL, account or source path.

The check runs asynchronously with an eight-second parent deadline, so Flutter
can continue responding. A crash, rejected startup, missing helper or timeout
returns an unavailable-host result and keeps the portable reader usable. On
every exit, timeout or plugin disposal, the app stops remaining members of the
helper's process group and reaps the direct child. It observes exit before
reaping so the leader's PID cannot be reused during cleanup. Core dumps are
disabled for this disposable process; native
stdout/stderr are discarded. No browser sandbox or host security policy is
weakened to obtain a successful result.

Concurrent callers share the check. Results are cached for at most two seconds
and real reader load, rendering or process errors invalidate them. Readiness
reduces known process-launch failures; it cannot guarantee that a later native
operation or changing system state will succeed. The real rendering and input
gate below remains required.

## Native boundary and lifecycle

Each reader has an ephemeral, sandboxed WebKit context and its own scoped
loopback asset endpoint. Only the exact trusted reader document can receive the
host bridge. Navigation policy allows that document and same-origin blob book
frames, blocks new windows, and denies native permissions, downloads, file
choosers and authentication prompts. Publication scripts and remote resources
remain prohibited by the shared sanitizer, iframe sandbox and CSP.

The host obtains CPU snapshots through WebKitGTK's public
[`get_snapshot`](https://webkitgtk.org/reference/webkit2gtk/2.40.0/method.WebView.get_snapshot.html)
API and uploads immutable buffers inside Flutter's `FlTextureGL.populate`
callback. GPU operations stay on the raster thread. Each surface is capped at
16 megapixels, including GTK display scale. A bounded pool of at most four
registered surfaces is reused across books; its GL objects live until their
owning engine context is destroyed. This avoids racing the Linux embedder's
asynchronous texture unregister path. Closing a reader immediately cancels its
pending work, destroys its WebKit view/context and closes its local server.

## Current interaction limits

The native gate exercises text selection, copy to the system clipboard, page
keys, pointer dragging, resizing, independent simultaneous readers and Flutter
modal focus. Search, notes and text editing remain Flutter controls, including
their normal IME handling. The embedded publication surface is read-only; it
does not implement native editable-content IME composition.

Tab stays in Flutter focus traversal, so it does not traverse links inside a
publication. The texture also does not yet expose WebKit's document
accessibility tree through Flutter semantics. Those are outstanding parity
gaps. The automated native display gate runs X11/Xvfb; Wayland, real touch
hardware, assistive technology and distribution-specific graphics drivers
require separate validation. This host alone is not a claim of full FBReader
feature parity.

## Required native verification

The `Ebook Linux embedded host` workflow builds an isolated Flutter application
using actual Ubuntu headers. Its enhanced-host job requires independently
colored pixels from the book and a Flutter overlay in the real X11 framebuffer,
then tests input, clipboard, navigation, multiple instances and lifecycle. A
hostile test publication must send no script/image/iframe/CSS requests to a
listening local probe. The native surface arithmetic test includes large and
high-DPI allocations at the pixel budget boundary.

The matrix also compiles a portable-only host. `readelf` must show no WebKit or
JavaScriptCore `DT_NEEDED` entry. Finally the enhanced job builds a fresh probe
application while headers are present, removes the optional runtime on that
disposable runner, and launches the **already-built** executable successfully
with an unavailable-host result. No rebuilding after removal is allowed.

The standalone `test/linux/runtime_probe_test.cc` exercises actual child
processes for coalescing, short cache expiry/invalidation, abnormal exit,
missing/non-executable helpers, timeout, disposal and process-group cleanup.
An independent `EXPECT_RUNTIME_BLOCKED=true` integration mode requires an
installed runtime whose sandboxed startup is rejected, verifies that direct
view creation fails safely, and checks that Flutter remains responsive. That
fallback result is separate from successful enhanced publication rendering.

Passing Dart analysis or source inspection is insufficient native proof. The
workflow's actual compile, framebuffer, input and runtime-absence results must
be green before this host is treated as verified on its supported CI target.
