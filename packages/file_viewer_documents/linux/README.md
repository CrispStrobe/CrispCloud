# Linux document host

This host is adapted from the MIT-licensed `crisp_ebook_reader` package at
`CrispStrobe/crisperbooks` commit
`32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52`. The original MIT notice remains at
`../assets/licenses/crisperbooks-host-MIT.txt`; `../HOST_PROVENANCE.json` records
the original source identities and the document-specific modifications.

## Building the usable plugin

Flutter registers the plugin from `pluginClass: FileViewerDocumentsPlugin` in
the package pubspec. Its exported C function is
`file_viewer_documents_plugin_register_with_registrar`; its method channel is
`file_viewer_documents/linux_host`. The texture GType is
`CrispDocumentTexture`, distinct from the ebook plugin's `CrispReaderTexture`
because both plugins can be loaded in the same process.

`FILE_VIEWER_DOCUMENTS_WEBKITGTK` defaults to `ON`. The enabled implementation
requires CMake **3.19 or newer**, GTK3, GModule, epoxy, and
`webkit2gtk-4.1` development headers **2.48.4 or newer**. The version floor and
runtime probe are inherited from the reviewed upstream host. If the option is
off, headers are absent/older, or CMake is older, CMake builds an unavailable-host
stub. A successful app compilation alone therefore does not prove that this
document surface was included.

For a release/CI build, check the prerequisites before building:

```sh
cmake --version
pkg-config --atleast-version=2.48.4 webkit2gtk-4.1
pkg-config --exists gtk+-3.0 gmodule-2.0 epoxy
flutter build linux --release
test -x build/linux/x64/release/bundle/lib/file_viewer_documents_webkit_probe
```

Run these commands from the consuming app. Check that configuration reports
`file_viewer_documents: WebKitGTK4.1 host enabled`, rather than the stub message.
The plugin target uses C++17 and the
`FILE_VIEWER_DOCUMENTS_HAS_WEBKITGTK=1` definition only on the enabled branch.
The probe executable is installed beside the plugin through CMake's deferred
install rule and must retain its executable bit in the delivered bundle.

The CrispCloud Linux build steps in `ci.yml`, `nightly.yml` and
`release.yml` install `libwebkit2gtk-4.1-dev`. The CI workflow now includes the
version/installed-probe checks above to detect a silently disabled host. Nightly
and release builds retain their existing configuration.

## Runtime requirements and isolation

The distribution must provide the complete maintained system WebKitGTK4.1
runtime, including its subprocesses and sandbox helper. This package dynamically
loads `libwebkit2gtk-4.1.so.0` and does not copy a partial browser runtime into the
app bundle. It requires a graphical Linux session and Flutter's OpenGL renderer.
The isolated startup probe verifies the process sandbox, script evaluation and
offscreen snapshot capability before a viewer is created. Missing libraries,
unavailable sandboxing, a failed probe or a terminated browser produce an error;
the code does not disable the sandbox or substitute a fake document preview.

The trusted top-level page is served from an instance-specific loopback URL.
Child document frames use same-origin blob URLs with script permission removed
by their renderers. Native navigation permits the trusted document or its local
blob frames; it does not permit external browsing. The message bridge is bounded
to 1 MiB and the Dart layer checks channel/session/type before forwarding a
status to the app. Closing the widget releases the browser and local server.

Ordinary keyboard characters, navigation and editing shortcuts are dispatched
through GTK so document search fields can work. Ctrl+Tab returns focus to
Flutter. Full input-method composition, live WebKit rendering and platform
accessibility require graphical integration testing; the mocked Flutter widget
tests are not evidence that those platform behaviors have passed.

## Validation boundary

The package's Dart host tests run through the real app Flutter dependency graph.
They exercise loopback HTTP requests, session/navigation/message boundaries,
runtime failure reporting, input dispatch and disposal races. They mock the
Linux platform channel and do not compile or launch WebKit. The local workspace
does not contain GTK/WebKit/epoxy development headers or CMake, and Chromium
startup is blocked by its socket policy. Full Linux plugin builds and actual
browser/native rendering must be verified in CI or another supported runtime.
