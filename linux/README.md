# Linux ebook host and packaging

The ebook package supplies an optional inline WebKitGTK host. It uses the same
bundled Foliate reader, publication sanitizer, session bridge and book-byte input
as the other enhanced hosts. Flutter composes the reader texture with its own
toolbars and dialogs. The app calls `probeEbookLinuxHost()` before selecting this
host and retains the portable chapter reader when the host is unavailable or
cannot start.

## Build and runtime dependencies

The native host uses the GTK3 WebKitGTK API **4.1**, version **2.48.4 or newer**.
The hosted native gate uses real distribution headers and runtime packages.
Ubuntu 22.04 must pass actual enhanced rendering and input. Ubuntu 24.04 has a
separate recovery gate for its observed sandbox startup constraint; that result
is not counted as enhanced rendering. The Linux build jobs install
`libwebkit2gtk-4.1-dev` alongside the existing Flutter GTK development dependencies. Ubuntu publishes this package
for [22.04 LTS updates](https://packages.ubuntu.com/jammy-updates/libwebkit2gtk-4.1-dev)
and [24.04 LTS](https://packages.ubuntu.com/noble/libwebkit2gtk-4.1-dev).

The minimum includes the upstream fix for a `GtkOffscreenWindow` initialization
crash, documented in the official
[WebKitGTK 2.48.4 release notes](https://webkitgtk.org/2025/07/30/webkitgtk2.48.4-released.html).
Older releases are rejected by the runtime probe even if their APIs appear
compatible. That known older crash is separate from any failure on a newer
runtime, which still requires its own native diagnostics and verification.

`packages/crisp_ebook_reader/linux/CMakeLists.txt` checks for those headers and
CMake 3.19 or newer. If either is absent, or `CRISP_EBOOK_WEBKITGTK=OFF` is set,
it compiles a small plugin that reports the enhanced host as unavailable. The application remains
buildable and launchable. GTK, GModule and the enhanced host's epoxy OpenGL
interface are ordinary system dependencies; WebKit and JavaScriptCore are
resolved on demand through `GModule`, with no hard browser-library dependency.

For an enhanced build on Ubuntu/Debian, install the maintained system package:

```sh
sudo apt-get install libwebkit2gtk-4.1-0
```

Restart CrispCloud after installing or updating the runtime; the native module
and startup result are cached for the life of the process.

The Debian package recommends `libwebkit2gtk-4.1-0 (>= 2.48.4)`. It is deliberately
an optional recommendation so the portable reader remains usable on an
installation without the browser runtime. Tar and AppImage bundles also use the
system runtime. They do not include a partial copy of WebKit's shared libraries,
subprocesses, resources or sandbox helpers. A self-contained Flatpak/Snap runtime
would need its own complete packaging and validation work.

Enhanced bundles include the source-built `lib/crisp_ebook_reader_probe`
executable next to the plugin shared library. The plugin resolves that sibling
path directly; it does not search `PATH` or private WebKit helper directories.
CMake defers `install(TARGETS)` until after Flutter's bundle cleanup and installs
mode 0755. CI checks a clean installation and a repeated installation. Both
plugin and helper load WebKit dynamically, so neither gains a hard WebKit or
JavaScriptCore dependency.

Before either a probe or a direct native `create` can succeed, a fresh helper
process starts WebKit with the same ephemeral context, required sandbox,
application identity, offscreen window and browser settings. It serves only a
small fixed loopback document, then requires that document's exact JavaScript
reply from the real WebProcess. The supervisor and fresh worker disable their
own dumpability and set a zero core-size limit inherited by their children.
The supervisor bounds startup and kills/reaps its children on success,
failure, timeout or cancellation. Readiness requires the exact bounded proof,
clean worker exit, and completed child cleanup. The plugin coalesces concurrent
checks, keeps pending calls safely owned, and creates no reader after a failed
check. The native check has a 12-second deadline plus a 2-second termination
bound; Dart waits 16 seconds. These limits do not change the user's system or
WebKit sandbox policy.

This guards the measured installed-but-unusable runtime case: the Ubuntu 24.04
runner's WebKit startup previously raised a fatal `Failed to fully launch
dbus-proxy` in the UI process. It now runs that risky startup inside the helper.
A cached positive check is evidence of startup readiness in that environment,
not a guarantee that every later reader, graphic driver or runtime transition
will succeed. Per-reader error handling and the portable option remain needed.
Flatpak/Snap and other container-specific sandbox backends require their own
validation.

The host requires Flutter's OpenGL renderer and a graphical session. Mesa's
software OpenGL implementation is exercised in CI. Flutter's distinct
`FLUTTER_LINUX_RENDERER=software` mode does not support these external textures;
the probe reports that limitation and the app uses the portable reader.

The distribution remains responsible for WebKit security updates. WebKit has
[LGPL and BSD portions](https://webkit.org/licensing-webkit/); this integration
does not vendor or modify its engine. That technical packaging choice does not
replace the application's release and license review.

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

The matrix also compiles a portable-only host. The installed-runtime recovery
job must return unavailable after one shared canary attempt, reject direct
creation, retain zero native views/surfaces, and keep Flutter responsive. Native
supervisor tests exercise proof validation and child cleanup; the real display
job also checks that no new canary/WebKit/proxy processes remain. `readelf` must
show no WebKit or JavaScriptCore `DT_NEEDED` entry in either plugin or helper.
Finally each enabled job builds a fresh probe application while headers are
present, removes the optional runtime on that
disposable runner, and launches the **already-built** executable successfully
with an unavailable-host result. No rebuilding after removal is allowed.

Passing Dart analysis or source inspection is insufficient native proof. The
workflow's actual compile, framebuffer, input and runtime-absence results must
be green before this host is treated as verified on its supported CI target.
