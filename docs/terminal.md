# Embedded terminal

CrispCloud uses a terminal emulator connected to an interactive pseudo-terminal
(PTY). Local desktop shells run through `flutter_pty2`; remote shells run through
the existing `dartssh2` connection and host-key trust service. `xterm2` handles
the terminal screen, escape sequences, keyboard input and selection.

The old panel appended text, stripped SSH escape sequences and sent complete
lines through a separate input field. That could not preserve cursor movement,
alternate screens, shell line editing or full-screen applications. The new
transport boundary passes the original stream to the emulator and sends
keystrokes immediately to the PTY.

## Build versus reuse decision

Reuse the emulator and native PTY implementation; keep session ownership,
connection choices and file-browser integration in CrispCloud. Implementing VT
parsing, Unicode cell widths, input modes, scrollback reflow, IME and desktop PTY
lifecycle ourselves would create a large compatibility and maintenance burden.

The reviewed versions are `xterm2` **5.4.0**, `xterm2_core` **1.0.0**,
`flutter_pty2` **3.0.0**, and the existing `dartssh2` **4.1.0**. All four packages
are MIT licensed. The new direct dependencies, `xterm2` and `flutter_pty2`, are
pinned to these releases; `flutter_pty2` uses a local
override based on that exact release. A desktop-only build hook and spawn guard
keep unused subprocess native code out of the SSH-only mobile apps. A separate
Windows fix makes child standard handles connect to ConPTY even when the parent
application's input/output is redirected. The Unix backend is unchanged; see
[`packages/flutter_pty2/UPSTREAM.md`](../packages/flutter_pty2/UPSTREAM.md).
The application lockfile records the complete resolved dependency graph.

| Option considered | License | Decision |
| --- | --- | --- |
| [xterm2 5.4.0](https://pub.dev/packages/xterm2) | MIT | Selected. Native Flutter rendering, a pure-Dart core, and recent maintenance without a WebView. |
| [flutter_pty2 3.0.0](https://pub.dev/packages/flutter_pty2) | MIT; bundled Dart native API is BSD-3-Clause | Selected with small patches for desktop-only assets and Windows standard handles. Uses Unix PTYs and Windows ConPTY, bounded I/O queues and a native-assets build hook. |
| [dartssh2 4.1.0](https://pub.dev/packages/dartssh2) | MIT | Retained. Already supplies SSH, PTY allocation, window-size updates and the verified host-key connection path. |
| [Original xterm 4.0.0](https://pub.dev/packages/xterm) | MIT | Established codebase, but the latest original release is older and xterm2 continues its maintenance. |
| [terminal_view 0.5.0](https://pub.dev/packages/terminal_view) | MIT | Viable mobile-focused xterm fork; keep as an alternative if device testing identifies a rendering problem. |
| [xterm.js](https://github.com/xtermjs/xterm.js) | MIT | Strong browser engine. Embedding it would add JavaScript/WebView bridges and platform-specific focus, clipboard and packaging work to this Flutter app. |
| [Terminal Lite](https://github.com/TerminalStudio/lite) | MIT | Useful example, but an experimental complete app brings unrelated architecture and documented tab-focus limitations. |
| [flutter_alacritty](https://pub.dev/packages/flutter_alacritty) | MIT package | Rust/FFI and a desktop-oriented engine add native dependencies without solving a present requirement better. |
| [xterm3](https://pub.dev/packages/xterm3) | AGPL-3.0-or-later from 6.0.0 | Excluded by the requested permissive-license criterion. This is a separate fork; xterm2 5.4.0 remains MIT. |

This decision does not change CrispCloud's own license.

## Platform support

This table describes the application's available transports, not every platform
listed on a dependency's package page.

| Platform | Local shell | SSH shell |
| --- | --- | --- |
| Linux desktop | Unix PTY with the user's available shell; built-in shell if the PTY is denied | Direct SSH TCP connection |
| macOS desktop | Unix PTY in an unsandboxed build; built-in sandbox shell in the App Store build | Direct SSH TCP connection |
| Windows desktop | ConPTY with the available Windows command shell; built-in shell if ConPTY fails | Direct SSH TCP connection |
| Android | Built-in sandbox shell (no host process) | Direct SSH TCP connection |
| iOS | Built-in sandbox shell (no host process) | Direct SSH TCP connection |
| Web/PWA | Built-in in-memory shell | SSH through an explicitly configured secure WebSocket gateway |

The built-in shell is the normal local terminal wherever an App Sandbox, mobile
OS or browser forbids spawning a host shell. It is implemented in Dart over a
small filesystem boundary (`sandbox_shell_fs.dart`), never launches a process
and therefore does not weaken App Sandbox or App Store review. On desktop the
real PTY is still preferred; if `forkpty`/`tcsetattr` is denied, the terminal
falls back to the built-in shell instead of failing. The status line says
"Sandbox shell" so the distinction is visible.

The built-in shell supports navigation and file inspection (`pwd`, `cd`, `ls`,
`cat`, `head`, `tail`, `wc`, `grep`, `find`, `stat`, `file`, `xxd`/`hexdump`),
file operations (`mkdir`, `touch`, `rm`, `cp`, `mv`), shell utilities (`echo`,
`export`, `unset`, `env`, `date`, `whoami`, `uname`, `history`, `clear`,
`which`, `exit`) and simple pipelines/redirection. `file` reports UTF-8 BOM,
UTF-16 and LF/CRLF/mixed line endings, and `xxd` exposes raw bytes. External
programs, `sudo` and background jobs are intentionally unavailable; use SSH for
a full remote shell or an unsandboxed desktop build for the host PTY.

Simulator support in an upstream PTY package is not evidence that arbitrary
local shells work on physical iOS devices. Although `flutter_pty2` also contains
Android/iOS paths, CrispCloud intentionally enables host processes only on
desktop.

Browsers cannot open raw SSH TCP connections. The browser connection dialog
therefore requires the user's own `wss://` gateway URL, using the existing
`WebSSHSocket` transport. That gateway must forward binary WebSocket messages
to the intended SSH server's TCP stream. It must already know its forwarding
destination; the separate Host and Port fields identify the actual SSH endpoint
for host-key verification and do not configure gateway routing. CrispCloud does
not provision a gateway or select a third-party relay.

The gateway URL must have a valid host and port and cannot contain credentials,
query parameters or a fragment. Gateway access control is configured by its
operator; the terminal still performs SSH authentication and verifies the
actual server's host key. Native desktop and mobile connections use direct TCP
by default.

Windows ConPTY is implemented upstream, but upstream 3.0.0 still marks Windows
as experimental. A packaged Windows run remains part of the release smoke test.
The local Windows patch explicitly sets `STARTF_USESTDHANDLES` while leaving
the standard handles null, so Windows assigns the child to its pseudoconsole
instead of duplicating the parent's redirected handles. This follows the
[Microsoft terminal maintainer's guidance](https://github.com/microsoft/terminal/discussions/15814)
and fixes the case exposed by Flutter's headless test runner.

## Data flow and ownership

- `TerminalView` renders the `Terminal` model and reports its measured columns
  and rows. Initial PTY dimensions and later resizes reach both local and SSH
  backends. The PTY uses an xterm-compatible terminal type.
- Local PTY output is one ordered byte stream. SSH standard output and standard
  error are each decoded incrementally, then delivered to the terminal without
  stripping escape sequences. UTF-8 characters may span transport chunks.
- Emulator output includes ordinary text, Enter, Tab, arrow keys, control keys,
  mouse reports and terminal replies. It is written to the active transport
  without adding a newline or inventing a prompt.
- `Terminal.paste` supplies bracketed-paste encoding when the shell or running
  application enables that mode. User-initiated clipboard operations are
  separate from remote escape-sequence clipboard requests.
- The native transport drains output through `done` before normal exit
  cleanup. Explicit close releases the PTY and subscriptions; it is not a
  detached background process manager. If output closes while the process is
  still alive, the panel shows "Waiting for exit…" and keeps Disconnect enabled.
- A hidden terminal can retain its in-memory session while the file browser is
  open. App shutdown, explicit disconnect and connection failure end a session.
  Reconnecting starts a new shell; it cannot restore an exited process. Use a
  remote multiplexer such as `tmux` when persistence across network or app
  restarts is required.

SSH retains the existing 30-minute inactivity timeout. Terminal input, output,
and resizing count as activity; hiding a quiet SSH session does not suspend
that timeout. Local desktop shells have no corresponding inactivity timer.

The shell only has its normal local or remote filesystem. A selected cloud
provider is not automatically mounted into it. Starting a local shell in the
file browser's local directory is a convenience, not a virtual filesystem
bridge or a restriction on the commands the shell can run.

## Input, clipboard and trust

The terminal receives input directly. Desktop copy/paste follows terminal
conventions: Ctrl+Shift+C / Ctrl+Shift+V on Linux and Windows, and Command+C /
Command+V on Apple platforms. Ctrl+C remains an interrupt. Selection and copy
must use the active buffer so an old selection cannot refer to an alternate
screen after a TUI exits. The bundled `AppMono` font supplies consistent cell
advances.

Remote output does not gain clipboard read/write permission. In xterm2 5.4.0,
`TerminalView` supplies default OS clipboard handlers when the model callbacks
are null. CrispCloud supplies explicit no-op/deny callbacks and disables
iTerm2/Kitty clipboard extensions; simply leaving the callbacks null would not
be sufficient. Explicit user copy/paste continues to work.

SSH uses the same persisted host-key trust mechanism as SFTP. Unknown keys
require an informed trust decision; changed keys are rejected. A server may
permit SFTP while forbidding a shell or PTY; that produces a connection error,
not a fallback that bypasses server policy. Terminal transcripts and typed
commands are not persisted as a new history database.

## License provenance

The following SHA-256 values identify the exact pub archives reviewed on
2026-11-06. They match pub.dev's version metadata; all four archive files were
independently hashed. The dartssh2 value also matches the existing application
lockfile.

| Package/version | License file in archive | Archive SHA-256 |
| --- | --- | --- |
| xterm2 5.4.0 | `LICENSE`: MIT, copyright 2020 xuty | `da8f15c6ecd0a0e06ca11f8d9fe55d6f1e686823ff084ad82fccf9a5fd1f8c00` |
| xterm2_core 1.0.0 | `LICENSE`: MIT, copyright 2020 xuty | `500ac551e448d8fa9766671aba26303dd5979d9d1af93df77af80afae16c75de` |
| flutter_pty2 3.0.0 | `LICENSE`: MIT, copyright 2022 xuty | `9802f793109fe7241cc172780571d501e50db6b247624a6b7c4df889bb9cbfe6` |
| dartssh2 4.1.0 | `LICENSE`: MIT, copyright 2022 xuty | `39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51` |

Authoritative package metadata and downloadable archive URLs:

- [xterm2 5.4.0 metadata](https://pub.dev/api/packages/xterm2/versions/5.4.0)
- [xterm2_core 1.0.0 metadata](https://pub.dev/api/packages/xterm2_core/versions/1.0.0)
- [flutter_pty2 3.0.0 metadata](https://pub.dev/api/packages/flutter_pty2/versions/3.0.0)
- [dartssh2 4.1.0 metadata](https://pub.dev/api/packages/dartssh2/versions/4.1.0)

The xterm2 runtime dependencies are `xterm2_core`, `characters`, `convert`,
`meta`, `quiver`, `equatable`, `zmodem` and Flutter. Their licenses are MIT,
BSD-3-Clause or Apache-2.0. The new core depends only on `characters`.
`flutter_pty2` declares `ffi`, `code_assets`, `hooks` and `native_toolchain_c`,
all BSD-3-Clause. The native build uses system PTY/ConPTY APIs rather than
shipping a separate terminal application or a winpty binary. Its Dart build
tooling was already present in the application's dependency graph.

Flutter collects the packages' top-level license files. `flutter_pty2` also
bundles Dart SDK native API headers and `dart_api_dl.c` under `src/include/`;
their BSD notices are distinct from the package's MIT license. CrispCloud
includes the additional notice and full BSD-3-Clause text in
[`assets/licenses/terminal/DART_BSD_LICENSE.txt`](../assets/licenses/terminal/DART_BSD_LICENSE.txt)
and registers it on the app's license page. The upstream license text is
[Dart SDK LICENSE](https://github.com/dart-lang/sdk/blob/main/LICENSE), Git blob
`be5c7b45c38a54f9bde197ed254753167d61ad1b`.

On an upgrade, resolve and review the lockfile, inspect the actual package
archive licenses and native notices, and rerun the terminal checks. A similarly
named fork or a higher version number is not a license guarantee.

## Build and smoke-test guide

Use the Flutter version pinned by `.fvmrc` and run `flutter pub get` normally.
The `flutter_pty2` override compiles and bundles its native library on desktop
only; its matching spawn guard rejects mobile before native symbol resolution.
The build machine needs a C toolchain: Xcode command-line tools on macOS, clang on
Linux, or Visual Studio C++ tools on Windows. The resolved `native_toolchain_c`
0.19.5 auto-discovery uses clang on Linux; using gcc requires explicit toolchain
configuration. Its hook skips native code assets when the target disables them,
including web compilation.

Focused regression commands from the application root:

```sh
flutter test --concurrency=2 \
  test/terminal_session_test.dart test/terminal_widget_test.dart \
  test/terminal_process_test.dart test/terminal_native_assets_test.dart \
  test/ssh_terminal_transport_test.dart test/ssh_terminal_test.dart \
  test/ssh_gateway_test.dart test/ssh_terminal_gateway_test.dart

flutter test --platform chrome --concurrency=1 \
  test/terminal_session_test.dart test/terminal_widget_test.dart \
  test/ssh_gateway_test.dart test/ssh_terminal_gateway_test.dart

flutter analyze --no-fatal-warnings --no-fatal-infos
flutter build web --release
```

CI runs the terminal tests in the Linux suite, the browser tests in Chromium,
and a native PTY smoke test in the existing Linux/macOS/Windows matrix so
platform failures are visible early. Windows and macOS build jobs retain the
full terminal regression checks before packaging; all packaged builds still
require the complete Linux suite to pass.
The Windows case exercises the actual ConPTY backend through `TerminalSession`,
including emulator replies to startup queries, interactive input, a separately
rendered command-output line and the exit code. Its runner redirects standard
I/O, so it also covers the Windows handle-assignment patch.

Run the terminal unit/widget tests and static analysis, then exercise the
packaged app on each enabled target. Automated checks are not a substitute for
physical-device keyboard/IME or Windows ConPTY validation.

1. **Real TTY and working directory.** Open a local desktop terminal; run
   `pwd`, `tty` and `stty size` on Unix. Confirm the directory matches the
   intended local folder and stdin is a TTY. On Windows, verify the selected
   shell, its working directory and console dimensions.
2. **Interactive input.** Type a partial command, move the cursor with arrows,
   edit with Backspace/Delete, use Tab completion and Up/Down history. Run
   `sleep 30` on Unix and interrupt it with Ctrl+C. The prompt should return
   without closing the session.
3. **Escape handling.** Run
   `printf '\033[31mred\033[0m normal\r\n'`; confirm colored output. Run an
   installed full-screen program (`vim`, `less` or `top`), resize the window and
   panel, then exit. Its alternate screen should restore the prior shell.
4. **Resize.** Check `stty size` before and after resizing. Open an SSH PTY and
   repeat; remote rows and columns should follow the view, including after a
   resize that happened while the connection was starting.
5. **Selection and paste.** Copy a wrapped selection, paste Unicode and
   multiline text into a test editor, and check bracketed-paste behavior. While
   a TUI captures the mouse, verify the supported local-selection override.
   Confirm remote OSC clipboard queries do not expose the local clipboard.
6. **Session lifecycle.** Hide and reopen the panel during a running command.
   Then disconnect or restart explicitly, including while a connection is
   opening. No old output, stale error, duplicate shell or late callback should
   attach to the new session. `exit` must preserve final output and show the
   stopped state. A failed executable or SSH shell request must report a
   useful error.
7. **SSH trust and failure.** Verify first-use trust, a known host, rejection of
   a changed key, invalid credentials, network loss and a server denying PTY
   allocation. Do not enable unattended acceptance of unknown hosts for tests.
8. **Mobile and browser transports.** On Android/iOS, connect via SSH and
   exercise the software keyboard, IME, paste and extra keys. On web, supply a
   controlled `wss://` gateway and verify the real SSH endpoint's host-key
   prompt, interactive output and resize. Check that missing/invalid gateway
   URLs are rejected and no local shell or native library is offered/loaded.
   Test a signed sandboxed macOS build separately from an unsandboxed build.

Only claim platform smoke tests that were actually executed. In particular,
Linux unit/native checks do not certify Windows, signed macOS or physical
Android/iOS behavior.
