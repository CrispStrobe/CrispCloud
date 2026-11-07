# Embedded iOS shell provenance and scope

This package builds a local Dash interpreter and selected `ios_system` commands
inside CrispCloud. It never opens a companion app, starts an OS subprocess, or
requires a jailbroken device. The exact source URLs, full Git commits and SHA-256
digests are in `tool/sources.json`. Local changes are reviewable unified diffs in
`patches/`. `tool/prepare.py` verifies source before applying those patches and
records the compiler version and every generated artifact digest in
`ios/Resources/BuildProvenance.json`.

## Licensing

CrispCloud integration source uses the application's AGPL-3.0 license. The
`ios_system` wrapper has its own BSD license. Native utility source files retain
their own notices; they are not all covered by the wrapper's license.

**Dash is not described here as entirely BSD.** At the pinned Dash revision,
`COPYING` explicitly identifies `src/mksignames.c` as GPL version 2 **or any later
version**, and explicitly states that its generated output is linked into Dash.
That is why `licenses/GPL-2.0.txt` is included. This is an *or-later* grant, not a
GPL-2.0-only dependency. The original BSD notices, Dash's complete COPYING file,
and the GPL text are preserved. Distributors must keep the corresponding source
available, including the pinned upstream archives, these patches and build
scripts. The build does not silently rewrite or relicense third-party notices.

The pinned Automake `missing`, `compile`, and `depcomp` build helpers carry
GPL-2.0-or-later terms with their explicit Autoconf distribution exception.
`install-sh` retains the X Consortium permission notice and identifies the FSF
changes as public domain. Their complete header notices are retained both in
the source scripts and in the aggregate LICENSE; they are build tools rather
than code linked into the iOS frameworks.

`LICENSE` combines the integration license and all copyright/license notices
collected from the relevant upstream source directories. Flutter includes this
package's LICENSE in its application license registry. The same text is bundled
as `NativeNotices.txt` for native distributions. Some notices describe unused
helper files in those directories; preserving these additional notices is
intentional. `tool/prepare.py --verify-only` regenerates the notices from the
pinned source and checks every patch on Linux as well as macOS.

## Curated runtime

Frameworks: `ios_system`, `files`, `text`, `shell`, `awk`, `tar`, and six Dash
interpreter images (`dash`, `dashA` through `dashE`) needed for nested scripts.
The only enabled commands are the explicit keys in `ios/Resources/commands.plist`.
The shell framework's unrelated JavaScript/Swift/WASM source files are excluded
from compilation. No downloaded native program is installed at runtime.

The Flutter frontend remains responsible for rendering terminal escape codes.
This package supplies a canonical input editor over FILE streams: typing, echo,
backspace/delete, arrows/home/end, a bounded history, pasted multiline commands,
Ctrl-C, and permanent session EOF. There is no host PTY, job control, raw input
mode, terminal completion, or promise that arbitrary full-screen tools work.
Dash supplies normal shell syntax: variables, functions, loops, conditionals,
pipelines, redirection, substitutions, and scripts. Only bundled commands and
scripts that use them can execute. Shell language support does not imply Linux
binary compatibility or the ability to install arbitrary native executables.

## Local patches

- Load an explicit command dictionary from the plugin resource bundle; resolve
  its framework paths to the signed app's Frameworks directory.
- Use Dash for `sh -c` as well as interactive `sh`; bypass the upstream minimal
  sh command parser.
- Export the embedded Dash entry point as `dash_main`; verify every curated
  command's export in every device and simulator architecture before packaging.
- Borrow input/output/error streams under ios_system's owned-stream leases and
  wait for all descendants to clean up before closing them.
- Preserve the host application's crash handlers instead of installing the
  upstream command crash handlers process-wide.
- Cooperatively interrupt the interactive root at safe parser/evaluator
  boundaries, after its cancelled descendants have drained. No SIGINT is sent
  to Flutter and no arbitrary thread is forcefully terminated.
- Add cancellation points to AWK evaluation and sed's branch loop.
- Suppress SIGPIPE on each native pipe descriptor so an early/cancelled reader
  cannot deliver a process signal to the Flutter host.
- Read canonical shell input a line at a time so pasted `read` input is not
  swallowed by Dash's parser buffer, and poll the input for cancellation.
- Read COLUMNS/LINES/ROWS from the live native session after a resize, with
  synchronized copies and without delivering process signals to the app.
- Release session bookkeeping only after all owned commands have completed.

## Process and lifecycle constraints

Only one embedded local session is active at a time. ios_system utilities share
process cwd and some legacy library state even though command streams and much
of the environment are per command. App file operations must use absolute paths.
The original process cwd and engine flags are restored after the command tree
has completed; restoring them while a command still runs would be unsafe.

The caller retains any security-scoped folder grant through `exitCode`. The
native engine neither obtains nor extends access to other applications' folders.
For provider files use CrispCloud's staged workspace and explicit sync flow.
The app sandbox remains the operating-system access boundary; the shell is not
an additional security boundary inside the app.

Output is bounded and backpressured during normal operation. Cancellation drains
native writes independently of Dart listeners, retaining a bounded tail and
reporting truncation if necessary. Backgrounding or detaching the plugin cancels
the session; this is not a persistent background shell service. Ctrl-D closes the
input stream permanently, unlike transient terminal VEOF on a real PTY.

## Build and verification

On macOS with Xcode selected:

```sh
python3 packages/crisp_ios_shell/tool/prepare.py
packages/crisp_ios_shell/tool/test_native.sh
```

Preparation builds device arm64 and universal arm64/x86_64 simulator XCFrameworks
from the same source and patches. The native test command accepts an optional
booted simulator UDID; otherwise it selects/boots an available iPhone simulator.
It runs the real engine, not a substitute availability implementation. Flutter
transport/editor tests run with `flutter test` from this package.

The frameworks are embedded but command images must be loaded on demand, so the
pod uses `-dead_strip_dylibs` to prevent eager linkage of unused command images.
The native test suite verifies repeated sessions and nested Dash invocation.
App packaging must retain `ios_system` while avoiding direct load commands for
`dash*`, `files`, `text`, `shell`, `awk`, or `tar`; `tool/check_packaging.py`
checks that invariant on a built `.app`.
