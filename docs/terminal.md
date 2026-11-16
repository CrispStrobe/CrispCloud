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
keep unused subprocess native code out of mobile builds. A separate
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
| iOS | Embedded `ios_system` + Dash with bundled commands (no host process) | Direct SSH TCP connection |
| Web/PWA | Built-in in-memory shell | SSH through an explicitly configured secure WebSocket gateway |

The built-in Dart shell is used on Android, the web, and sandboxed desktop
builds that cannot spawn a host shell. It is implemented in Dart over a
small filesystem boundary (`sandbox_shell_fs.dart`), never launches a process
and therefore does not weaken App Sandbox or App Store review. On desktop the
real PTY is still preferred; if `forkpty`/`tcsetattr` is denied, the terminal
falls back to the built-in shell instead of failing. The status line says
"Sandbox shell" so the distinction is visible.

The iOS backend is separately labelled **iOS shell** and uses a bundled native
runtime. Its directory grants and explicitly reviewed cloud workspaces are
described in [Embedded iOS shell and staged workspaces](ios-shell.md). It has no
companion-app dependency. Workspaces are also available in other native builds.

The built-in shell supports navigation and file inspection (`pwd`, `cd`, `ls`,
`cat`, `head`, `tail`, `wc`, `grep`, `find`, `stat`, `file`, `xxd`/`hexdump`),
file operations (`mkdir`, `touch`, `rm`, `cp`, `mv`), shell utilities (`echo`,
`export`, `unset`, `env`, `date`, `whoami`, `uname`, `history`, `clear`,
`which`, `exit`) and simple pipelines/redirection. `file` reports UTF-8 BOM,
UTF-16 and LF/CRLF/mixed line endings, and `xxd` exposes raw bytes. External
programs, `sudo` and background jobs are intentionally unavailable; use SSH for
a full remote shell or an unsandboxed desktop build for the host PTY.

Quoted and escaped `|`, `<`, and `>` remain literal arguments. The shell checks
the complete pipeline for syntax errors before executing it; an unterminated
quote or missing redirection filename does not execute a destructive prefix.
Empty path operands are rejected, including an unset variable passed to `rm`.
Copying or moving multiple sources requires an existing destination directory.
Self-copies and directory destinations beneath the source are rejected, with
existing symbolic-link parents resolved on native filesystems. Native moves
fall back to copy-and-delete only for a reported cross-device rename error.

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
  open. App shutdown, explicit disconnect and connection failure end the
  connection. A plain SSH reconnect starts a new shell and cannot restore an
  exited process. A named tmux session can be reattached after disconnecting,
  subject to the remote host and tmux server remaining alive (see below).
- Each native local connection holds its own security-scoped folder grant for
  its lifetime. A transfer or restarted terminal cannot release another
  connection's grant. Normal exit, failed startup and disconnect release it;
  hiding the panel keeps it while the shell remains alive. The built-in shell
  finishes an already accepted filesystem command before disconnect releases
  access, and does not execute later queued input after disconnect.

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

Keyboard ownership is explicit: the left pane, right pane or terminal. Clicking
the terminal header restores terminal input, and hiding it returns ownership to
the last active pane. File refreshes and terminal output do not steal focus.
The file-browser shortcut handler defers while the terminal owns the keyboard.
Terminal chrome and typed SSH errors follow the selected application locale.

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

## Tabs, split views, search and text size

The terminal strip supports up to eight independent tabs. **New terminal** (+)
starts another local or built-in shell. Each tab has its own scrollback,
selection, SSH reconnect destination and search state. Switching tabs or hiding
the whole terminal keeps the connections alive. Use **Terminal layout** to split
the active pane side by side or top and bottom. Each split adds another
terminal, and splits can be nested to display up to eight panes. Clicking a
pane makes it the keyboard target. Selecting a hidden tab replaces the active
leaf while preserving every other visible pane.
The existing SSH service permits five concurrent SSH connections across the
app; the eight-tab limit also accommodates local and disconnected terminals.

Each split keeps its own direction and divider proportion. When the requested
layout cannot fit the available width or height, the active pane is displayed
alone and the full layout reappears when space permits. **Zoom active pane**
temporarily fills the workspace; **Restore panes** brings the same layout back.
**Single pane** changes the layout while keeping all other tabs connected.
**Previous pane** and **Next pane** cycle visible leaves, including while zoomed.
Double-click a tab or choose
**Rename terminal** to give it a local label; that label does not replace the
trusted SSH endpoint in the pane header. Closing a running tab asks before
disconnecting it. The last tab remains available; use Disconnect or Hide for it.
The current workspace stays in memory. Explicitly saved arrangements survive
app restarts, as described below; they reopen disconnected.

Choose **Terminal actions → Find in terminal** for literal search over the
active screen and its scrollback. Case-sensitive and whole-word options, next
and previous matches, and Enter / Shift+Enter navigation are available. Escape
closes search. Matches use the emulator's Unicode and wrapped-line mapping;
search highlights do not overwrite the clipboard selection. Output refreshes
matches without dragging the viewport. Inactive searches pause, and scans are
throttled during heavy output. Search shows the first 1,000 matches, with `+`
when additional matches exist; it does not evaluate regular expressions.

Font controls adjust the current tab from 8 to 32 logical pixels and reset to
13. Font changes resize the PTY through the normal terminal layout path.

| Action | Linux / Windows | Apple platforms |
| --- | --- | --- |
| New terminal | Ctrl+Shift+T | Command+T |
| Close selected tab | Ctrl+Shift+W | Command+W |
| Next / previous tab | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Split side by side | Ctrl+Shift+D | Command+D |
| Split top and bottom | Ctrl+Shift+E | Command+Shift+D |
| Select pane in a direction | Ctrl+Alt+Arrow | Command+Option+Arrow (or Ctrl+Alt+Arrow) |
| Previous / next pane | Ctrl+Shift+[ / Ctrl+Shift+] | Command+[ / Command+] |
| Zoom / restore active pane | Ctrl+Shift+Enter | Command+Shift+Enter |
| Find | Ctrl+Shift+F | Command+F |
| Larger / smaller font | Ctrl+Shift+Plus / Ctrl+Shift+Minus | Command+Plus / Command+Minus |
| Reset font size | Ctrl+Shift+0 | Command+0 |
| Previous / next command mark | Ctrl+Shift+Up / Ctrl+Shift+Down | Command+Shift+Up / Command+Shift+Down |

Workspace shortcuts also work from the terminal search field. These shortcuts
apply while a terminal owns the keyboard; Ctrl+C remains a terminal interrupt.
Browser-reserved shortcuts can be intercepted by the browser before reaching
the app; the terminal strip and actions menu provide the corresponding controls.

## Saved arrangements and split sizing

Use **Terminal layout → Save arrangement** to save up to 20 named layouts.
An arrangement includes tab order and custom names, the selected tab, the
complete nested split layout with each branch's direction and proportion, each
tab's font size, and remembered SSH destinations including jump routes and
exact shell/tmux/screen modes. Drag any divider to adjust its branch from 20%
to 80%, or double-click that divider to balance it. **Balance panes** balances
every branch. Minimum pane sizes temporarily clamp displayed proportions without
changing the saved values. Tab controls can move a tab left or right. Saving
while zoomed retains the complete layout; transient zoom is not persisted.

**Saved arrangements → Restore** asks before replacing the current workspace,
including when disconnected tabs still contain scrollback. It ends existing
connections before replacing their tabs and refuses to finish replacement if
cleanup is not confirmed. An in-progress connection must be canceled first.
The restored tabs open **disconnected**; reconnect an SSH destination or start
a local shell explicitly.

Arrangements never store scrollback, command history, selection, passwords,
private keys, passphrases, broadcast membership or live connection objects.
Local working-directory grants and staged-workspace ownership are not restored.
Saved data uses the app's local preferences; it is not synchronized, and corrupt
or newer-format records are preserved instead of silently overwritten. The
arrangement store reads the earlier two-pane schema v1 and writes schema v2.
Migration happens only on a save/delete operation. Older app versions reject
v2 instead of silently discarding nested panes.

## Custom terminal key bindings

Choose **Terminal actions → Key bindings** to add, edit, disable or delete up to
50 local mappings. Capture an exact logical key and Ctrl/Alt/Shift/Meta chord,
then choose **Send text** or **Send key**. The same mappings apply to terminal
panes throughout this app instance and persist locally across restarts.

Text mappings contain at most 4,096 UTF-16 code units and send exactly that text;
they do not append Enter. Tabs and line breaks must be entered explicitly. Raw
escape and other control bytes are rejected. Key mappings choose a supported
terminal key and output modifiers. The emulator encodes a complete press/release
tap according to each recipient's keyboard protocol, including Kitty release
reporting. Broadcast groups receive the explicit mapping once and re-encode it
for each recipient. Holding a shortcut does not repeat a macro; its repeats and
release remain consumed even after focus moves to another terminal.

Bare printable shortcuts require Ctrl, Alt or Meta, preserving normal typing
and IME composition. Workspace navigation, copy/paste, search, zoom, command
navigation, Ctrl+C and the app's configured terminal-toggle shortcut retain
priority. A mapping requires the active visible connected terminal to have
keyboard focus. Shell output cannot trigger it.

Mapping text is stored in local preferences as plain text, as stated in the
editor. It is not a credential store. Unknown or corrupt schema versions are
preserved and cannot be overwritten by an unsuccessful load. These bindings
cover explicit text and terminal-key actions. Output observation is configured
separately under **Output triggers**; coprocesses, scripts, arbitrary raw-byte
macros and iTerm2's complete action set remain separate capabilities.

## Output triggers

Choose **Terminal actions → Output triggers** to create, preview, edit, disable
or delete up to 50 rules. Rules apply to all mounted terminal panes, including
hidden tabs, and are stored locally as plain text. Each rule has a name, a
literal string or limited pattern, case sensitivity, a **Mark** or **Notify**
action, and either a cooldown or a once-per-connection limit.

**Mark** creates a normal navigable terminal mark at the completed matching
line. Several matching lines in one network chunk receive separate marks;
splitting the same output across packets does not change their locations.
**Notify** shows an in-app message with the rule name and a bounded excerpt.
Notifications in the same frame are coalesced to the latest match for that pane.
These actions never send input, run scripts, change the clipboard, or join a
broadcast group. Reconnecting clears one-shot and cooldown state; rule settings
remain saved. The final unterminated line is evaluated once on natural output
EOF, while an explicit disconnect discards unfinished output.

Literal matching is the default. **Limited pattern** uses a finite-state
matcher with literals, `.`, character classes and ranges, `^`/`$`, `?`, `*`,
`+`, and ASCII `\d`, `\s`, `\w` plus their inverse forms outside character classes.
Groups, alternation, counted repetitions, lookaround, backreferences, and
patterns that can match empty input are rejected. This is not the full
iTerm2/ICU regular-expression language. The editor previews matching against
sample text before saving.

The observer consumes incoming decoded output and completed logical lines,
not arbitrary snapshots of the emulated screen. It strips styling and OSC/DCS
payloads, handles carriage-return/backspace/erase-line progress updates, and
ignores alternate-screen content and lines containing unsupported cursor edits.
It does not scan old scrollback when a rule is enabled. Names are limited to
80 UTF-16 code units, patterns to 256, and observed lines to 4,096 Unicode
code points. Each session admits at most ten actions and two million estimated
matching operations per second. Whole lines exceeding the matching budget are
skipped rather than queued; high-volume output is not a guaranteed event log.
The matcher never uses a backtracking regular-expression engine for user rules.

Unknown, oversized, duplicate-ID or corrupt preference records are retained and
reject writes until the problem is resolved. Captured output, connection
credentials, runtime cooldowns and notification history are never persisted.

## SSH port forwarding

On an active native SSH terminal, choose **Terminal actions → Port forwarding**.
The manager uses that terminal's existing authenticated, host-key-verified SSH
route, including its jump hosts. Add a listener, choose its mode and address,
and enter a listening port. Port **0** requests an available port; the manager
shows the actual assigned port after startup.

| Mode | Listener | Destination reached from |
| --- | --- | --- |
| Local | This device | Final SSH server |
| Remote | Final SSH server | This device |
| SOCKS5 | This device | Final SSH server, with a destination selected per SOCKS request |

Local and remote modes require a destination host and port. SOCKS5 supports
TCP CONNECT with IPv4, IPv6 and DNS-name targets, and no-authentication
negotiation. DNS names are sent through SSH to resolve at the final server.
SOCKS BIND, UDP association and proxy username/password authentication are not
implemented. Bind choices are the literal loopback addresses `127.0.0.1` and
`::1`; remote binding policy is ultimately enforced by the SSH server, whose
[`GatewayPorts` configuration](https://man.openbsd.org/sshd_config#GatewayPorts)
can alter the requested scope.

Each connection allows at most 16 forwarding records and 32 clients per
listener, counting pending requests and SOCKS handshakes. The manager shows
listener status, allocated port, active connections and a bounded error. A
failed start stays visible and can be removed with **Stop**. A refused
destination closes that client while leaving the listener available for later
attempts. Traffic refreshes the SSH activity clock.

Closing the dialog leaves listeners running. **Stop** ends a listener and all
its clients. Disconnect, natural SSH closure, session replacement and service
disposal also close owned listeners. Nothing is persisted or restarted on
reconnect. Late socket/channel results are closed after cancellation; a pending
or active remote forwarding operation whose cancellation cannot be confirmed
closes the SSH transport so a remote listener cannot outlive its ownership.
The manager reports the closure rather than silently claiming a successful stop.

The forwarding bridge preserves backpressure and both half-close directions,
allowing a server to send its final response after the requesting client closes
its write side. Dial operations have a 15-second deadline and SOCKS negotiation
has a 10-second deadline. Browser builds cannot listen on native TCP sockets;
the forwarding action remains unavailable there. SSH-agent integration,
forwarding-profile persistence, shared connections across terminal tabs and
native tmux control mode remain separate work.

## Broadcast input

Use **Terminal layout → Broadcast input** and select at least two connected
tabs. Review the targets and choose **Start broadcasting**. A persistent banner
shows the active group and provides **Stop**. Newly opened tabs are not added
automatically.

Only explicit keyboard, IME and paste operations from the active, visible,
focused terminal are mirrored. Each recipient encodes the operation using its
own keyboard and bracketed-paste modes. Terminal responses, focus reports and
mouse reports stay with their own connection. User commands are sent to every
selected member while the group is active, including members in hidden tabs.

Broadcast stops when the workspace is hidden, a tab closes, a member disconnects
or reconnects, an arrangement restore is approved, input exceeds the supported
per-event limit, or forwarding fails. Stopping invalidates queued deliveries
that have not reached their transport. Group membership is tied to the exact
connections the user selected and is never saved in arrangements or profiles.

## SSH authentication, reconnect, tmux and screen

Open **Connect via SSH** and select **Password** or **Private key** under
Authentication. Key mode accepts a PEM/OpenSSH private key and an optional
passphrase for an encrypted key. Use **Paste private key** to preserve the key's
line breaks while keeping it masked, or reveal the field to edit it across
multiple lines. The passphrase decrypts the key locally; it is not used as the
server login password. Invalid keys or an incorrect passphrase fail before a
connection is opened. Both authentication modes use the same host-key checks
and direct TCP or explicit WebSocket gateway transport.

The Session selector offers five modes:

| Mode | Behaviour |
| --- | --- |
| **Remote shell** | Opens the server's normal interactive login shell. |
| **Create or attach tmux** | Creates the named session if absent, or attaches to it if it already exists. |
| **Attach existing tmux** | Attaches only to the exact named session; a missing session is an error and does not create one. |
| **Create new screen** | Creates a new GNU screen session with the requested name. |
| **Attach existing screen** | Resolves an exact existing screen name or full `PID.name` ID, then joins that session. Missing or ambiguous targets fail. |

The remote server must have `tmux` available on the SSH command path and allow
PTY execution. Names contain 1–64 ASCII letters, digits, underscores or hyphens
and cannot start with a hyphen. This deliberately excludes tmux target patterns,
window/pane separators and shell syntax. The service validates names before
replacing a running shell. It launches tmux through an SSH PTY exec request,
never by typing a startup command into the terminal. It does not detach other
attached clients. Missing tmux, a missing attach-only target, and server errors
remain visible in terminal output; no fresh-shell fallback hides the failure.
The terminal also retains the SSH channel's exit status when the server supplies
one, after both output channels have drained.

GNU screen must be available on the server's command path. New names follow the
same 1–64-character rule as tmux. Attachment also accepts a full `PID.name` from
`screen -ls`, including dotted tty/host suffixes. Duplicate names require a full
ID. Screen creation is explicit because its CLI has no atomic exact-name
create-or-attach operation; two Create actions can create distinct sessions
with the same human name.

Screen attachment reads a bounded listing in the C locale, rejects unavailable
and competing-prefix matches, then uses the full ID with `screen -x`. It does
not force-detach other displays, log out other clients, or fall back to a new
session or shell. Screen's CLI can still race with another process renaming or
creating sessions between listing and attachment; this is a conservative
listing check, not an atomic server-side exact-only attachment primitive.

The terminal header includes the trusted SSH endpoint and selected session.
**Detach from tmux** closes CrispCloud's SSH connection without sending `exit`
or `kill-session`. The server's tmux session normally keeps running. Existing
server settings such as `destroy-unattached`, host shutdown, or explicitly
exiting the session's last shell can still end it. Hiding the panel keeps the
current connection, while the existing SSH inactivity timeout still applies.
**Detach from screen** likewise closes only this SSH connection. The remote
session remains subject to screen's own settings, remote process exit and host
shutdown. Closing a terminal tab uses the same transport cleanup.

Use **Terminal actions → Reconnect SSH** to reopen the form with the last host,
port, username, authentication method, gateway and tmux or screen selection. Passwords,
private keys and passphrases are cleared and must be entered again. Canceling
this dialog leaves a currently connected terminal intact. These reconnect
settings live only in the current tab's memory unless explicitly saved as a
profile (see below). After a restart, entering the same server,
user and tmux name can reattach to the remote session. Selecting
**Attach existing tmux** avoids creating a fresh session if the old one is gone.

The native mobile extra-key row includes **Ctrl+B**, the default tmux prefix.
For default tmux bindings, tap Ctrl+B followed by `c` for a new window, `n`/`p`
for the next/previous window, `%` or `"` to split a pane, or `d` to detach.
Customized tmux prefixes and bindings remain controlled by the remote server;
the extra key sends the actual control character. The built-in sandbox shell
does not run tmux or screen. **Ctrl+A** sends screen's default prefix; with
default bindings, follow it with `c` for a new window, `n`/`p` to change windows,
or `d` to detach. Prefix actions select their pane before subsequent typing.

See the upstream [tmux getting started guide](https://github.com/tmux/tmux/wiki/Getting-Started)
for the default bindings and remote session model.
See also the [GNU screen invocation manual](https://www.gnu.org/software/screen/manual/html_node/Invoking-Screen.html).

### Jump hosts

The connection form's **Jump hosts** section supports up to three ordered SSH
hops before the destination. Add or edit each hop and enter its own username
and password or private key/passphrase. The app verifies the host key of every
hop and the final destination independently, using that endpoint's host and
port. A rejected key or failed hop ends that attempt and releases its route.

A jump route uses nested SSH direct TCP channels; the first hop receives the
outer TCP connection. When a WebSocket gateway is configured, it must forward
to that **first hop**, while later hops and the final host are reached inside
the verified route. The gateway URL does not configure the relay's destination.
Without a jump host, the existing direct/gateway behavior is unchanged.

Reconnect, saved profiles and arrangements retain hop addresses, usernames and
authentication methods, but recursively remove every hop's password, private
key and passphrase. Reopening a saved route requests credentials for every
endpoint. Repeated endpoints and routes longer than three hops are rejected.
One complete route occupies one slot in the existing five-session application
pool, although it owns multiple SSH clients internally.

Jump hosts do not add SSH-agent authentication, agent forwarding or persistent
connection multiplexing. Native forwarding controls now use the final verified
connection, as described in [SSH port forwarding](#ssh-port-forwarding).
OpenSSH destination import is available separately from saved profiles below.

### Browse existing tmux and screen sessions

Choose **Terminal actions → Browse tmux sessions** or **Browse screen sessions**.
Enter the destination and route credentials, complete the usual host-key
verification, and choose an existing session from the filterable picker. The
connection form hides new-session options for this workflow. The selected
session becomes the tab's attach-only reconnect destination.

tmux entries show their names, window counts and attached-client counts. Screen
entries show the full `PID.name` so duplicate human names are distinguishable.
Unsupported names and unavailable targets remain visible but cannot be chosen.
The existing exact Screen resolver checks the selected full ID again during
attachment. Other clients remain attached.

Discovery uses fixed listing commands over a separate execution channel on the
verified connection, without a PTY. It waits for both output streams and the
channel status, limits combined output to 256 KiB and results to 512 sessions,
and applies a ten-second request deadline. It does not type commands into an
existing shell. No interactive shell starts before selection. Canceling the
picker closes the newly authenticated connection; stale results after a
disconnect, replacement or hidden panel cannot start a shell.

The listing is a snapshot and does not eliminate remote session rename/exit
races. Missing tools and failed or oversized listings are reported. This
workflow attaches the normal terminal stream; native tmux control-mode window
and pane mapping is not implemented.

## Saved SSH profiles

After entering a destination, choose **Terminal actions → Save SSH profile**
and give it a name. **Saved SSH profiles** lists destinations to reopen or
delete. Selecting one opens the regular connection form for credential entry;
canceling that form leaves the existing connection intact.

Profiles store only their name, host, port, username, authentication method,
optional gateway, ordered jump hosts and exact shell/tmux/screen settings.
Passwords, private keys and passphrases are removed recursively before a
profile is constructed and are absent from the versioned persisted schema. Profiles use the app's local preferences and
survive ordinary app restarts; they are not exported or synchronized by this
feature. Reusing a name explicitly replaces that profile. Up to 50 profiles
are supported. Concurrent saves from different tabs are serialized; unreadable
or newer-format saved data is left untouched and reported as an error.

Direct-only profile stores retain schema version 1. A store with jump routes
uses version 2 and does not downgrade again; older app versions reject that
newer data instead of silently turning a saved jump route into a direct login.

An attach-only profile remains attach-only, including after restarting the
app. Profile loading does not bypass host-key verification or connect
automatically. A saved Create new screen profile still creates a new screen
session on each connection; select Attach existing screen to resume one.

### Import OpenSSH configuration

Open **Saved SSH profiles → Import OpenSSH config**, paste a configuration, and
supply a default username if it is omitted in the text. **Preview** lists each
literal positive Host alias, its resolved destination and ordered jump route,
identity-file hints, and line-specific diagnostics. Select entries and review
or edit their proposed unique profile names, then choose **Import selected**.
Import never connects; opening a saved profile asks for credentials normally.

Supported settings include `Host` blocks and case-sensitive wildcard/negated
patterns, case-insensitive directive names, first-value precedence for scalar
options, `HostName` (including `%h`), `User`, `Port`, ordered `ProxyJump`, and
additive `IdentityFile` hints. Jump aliases resolve their own username, port and
authentication hint independently. Identity paths are displayed only: they are
not expanded, read or persisted, and private keys must be chosen when connecting.
The importer follows OpenSSH's proxy precedence, including disabling `none`.
Nested proxy routes must be flattened into at most three explicit hops.

`Match` or `Include` anywhere in the paste blocks every alias until the complete
configuration is flattened. `ProxyCommand` execution and unsupported
routing/security options block the aliases to which they apply. Diagnostics
explain the blocked configuration. Unsupported display/performance preferences
are identified where they can be safely omitted. This is a bounded destination
importer, not a complete OpenSSH evaluator or a live configuration watcher.

Input is limited to 128 Ki UTF-16 code units, 2,048 lines, 4,096 characters per
line and 100 literal aliases. A paste over the total text-size limit rejects
the whole edit and invalidates the previous preview instead of truncating route
settings. Other size/count limits retain the text but reject the entire preview.
The existing 50-profile limit still applies. Selected profiles are added under
one storage lock and one write; a collision or capacity failure saves none of
them. Existing profiles are never overwritten by import.

## Shell integration and command navigation

The terminal observes decoded OSC 133/633 prompt/command markers, OSC 7
working-directory reports and iTerm2 manual marks from the existing emulator.
A compatible shell can then provide a per-tab command history, command start
and finish times, exit status and a shell-reported directory in the status bar.

Choose **Terminal actions → Shell integration setup**, select **Bash 4.4+** or
**Zsh**, review the script and copy it. Paste and run it yourself in the intended
interactive shell. This enables integration for that shell session. The app
does not inject the script or edit startup files. Existing prompt hooks are
retained, and running the setup a second time does not wrap the prompt again.
The Bash helper uses a scalar prompt-hook fallback on Bash 4.4–5.0 and array
hooks on Bash 5.1+. The Zsh hook reports the previous command's status and
returns success so subsequent prompt hooks still run.

The built-in Dart shell and embedded iOS Dash are not Bash or Zsh. The setup
scripts do not enable automatic command tracking in those backends. Other
shells can emit compatible markers themselves. Multiplexers and shell themes
may filter or replace markers; verify the resulting behavior in the intended
environment instead of assuming it from ordinary PTY attachment.

Available controls:

- **Command history** filters retained commands and directories. Selecting an
  entry scrolls to it; it does not execute that command.
- **Previous command / Next command** move between retained prompt/manual marks.
  The keyboard equivalents are in the shortcut table above.
- **Add mark** works without shell setup. iTerm2 SetMark sequences are also
  recognized.
- **Select last command output** selects the completed command's retained output.
  Copy remains an explicit separate action.
- **Notify when command finishes** arms a one-shot in-app notification for the
  next observed command completion. It is not an operating-system push alert.

Tracking retains at most 500 marks and bounds each command/directory label to
2,048 UTF-16 code units. Anchors follow wrapped and wide-character reflow and
expire with scrollback. A running command can still report completion after
large output evicts its prompt, but navigation and selection require retained
anchors. Alternate-screen applications cannot create shell marks or overwrite
the displayed shell directory.

History is in memory for that connection and is cleared on reconnect. Remote
command and directory metadata remain display-only: they cannot execute a
local command, authorize file access, navigate the file panel or access the
clipboard. A prompt without a corresponding completion status is shown with
unknown status; the app does not invent a successful result.

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
  test/ssh_gateway_test.dart test/ssh_terminal_gateway_test.dart \
  test/tmux_session_options_test.dart test/ssh_terminal_connect_dialog_test.dart \
  test/ssh_terminal_reconnect_test.dart \
  test/screen_session_options_test.dart test/screen_session_command_test.dart \
  test/terminal_tabs_test.dart test/terminal_search_test.dart \
  test/terminal_search_bar_test.dart test/ssh_terminal_profiles_test.dart \
  test/ssh_terminal_profiles_dialog_test.dart \
  test/terminal_backend_metadata_test.dart test/widget/terminal_localization_test.dart \
  test/terminal_workspace_panel_test.dart test/terminal_panel_test.dart

flutter test --platform chrome --concurrency=1 \
  test/terminal_session_test.dart test/terminal_widget_test.dart \
  test/ssh_terminal_transport_test.dart \
  test/ssh_gateway_test.dart test/ssh_terminal_gateway_test.dart \
  test/tmux_session_options_test.dart test/ssh_terminal_connect_dialog_test.dart \
  test/ssh_terminal_reconnect_test.dart \
  test/screen_session_options_test.dart test/terminal_tabs_test.dart \
  test/terminal_search_test.dart test/terminal_search_bar_test.dart \
  test/ssh_terminal_profiles_test.dart test/ssh_terminal_profiles_dialog_test.dart

flutter analyze --no-fatal-warnings --no-fatal-infos
flutter build web --release
```

Current continuation suites, in addition to the established cohort above:

```sh
flutter test --concurrency=1 \
  test/ssh_jump_host_test.dart test/ssh_jump_transport_test.dart \
  test/ssh_jump_dialog_test.dart \
  test/terminal_arrangements_test.dart \
  test/terminal_arrangements_dialog_test.dart \
  test/terminal_arrangements_widget_test.dart \
  test/terminal_shell_integration_test.dart \
  test/terminal_shell_directory_labels_test.dart \
  test/terminal_user_input_test.dart \
  test/terminal_broadcast_test.dart test/terminal_broadcast_dialog_test.dart \
  test/ssh_multiplexer_session_test.dart \
  test/ssh_multiplexer_discovery_test.dart \
  test/ssh_multiplexer_sessions_dialog_test.dart \
  test/ssh_terminal_profiles_test.dart test/ssh_terminal_reconnect_test.dart \
  test/terminal_pane_layout_test.dart \
  test/ssh_config_import_test.dart test/ssh_config_import_dialog_test.dart \
  test/terminal_key_bindings_test.dart test/terminal_key_bindings_widget_test.dart

python3 tool/terminal_shell_setup_smoke.py
python3 tool/terminal_ssh_config_oracle.py --dart /path/to/dart
python3 tool/run_terminal_live_smoke.py --flutter /path/to/flutter
```

The new Dart suites are also listed in the existing Chrome, Windows and macOS
jobs. Linux's normal suite discovers them automatically. See the
[current source-bound validation record](terminal-parity.md) for actual results.
The [earlier failed runtime attempt](validation/terminal-20261115/runtime-attempts.md)
remains historical evidence and does not describe the recovered environment.
No GitHub Actions result is awaited or required for this work.

The live SSH runner requires OpenSSH server/client tools. It creates disposable
keys and two servers bound only to loopback, verifies a real jump route, executes
Unicode commands, reconnects and checks changed-host-key rejection. All fixtures
are cleaned up. Add `--with-pty` only when the test sshd has permission to write
login records; unprivileged environments may forbid interactive SSH PTYs while
permitting non-interactive channels. Test keys are never committed. The runner
also accepts `--project` to explicitly select a separately documented harness.

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
   Repeat with an unencrypted key and an encrypted key, including a wrong
   passphrase. Confirm that reconnect prefills the destination but no secrets.
   On a test host with tmux, create a named session, start a long-running
   command, detach, and reattach to the same session. Check exact-name attach,
   a missing attach-only target and a host without tmux. Existing clients must
   remain attached, and invalid names must not issue any remote command.
8. **Mobile and browser transports.** On Android/iOS, connect via SSH and
   exercise the software keyboard, IME, paste and extra keys. On web, supply a
   controlled `wss://` gateway and verify the real SSH endpoint's host-key
   prompt, interactive output and resize. Check that missing/invalid gateway
   URLs are rejected and no host shell or native library is offered/loaded.
   Also exercise the browser's in-memory built-in shell; those files are local
   to that terminal session and are not the browser's selected filesystem.
   Test a signed sandboxed macOS build separately from an unsandboxed build.
9. **Tabs and split views.** Create a nested layout with up to eight panes,
   mixing side-by-side and top/bottom splits, and type into each pane. Output
   in another pane must not redirect typing. Switch a third tab into a split, rename it, hide/reopen the terminal,
   and shrink the window until the split collapses. All retained sessions must
   keep their own output. Cancel a running-tab close, then retry and confirm;
   only that connection should close.
10. **Search and font size.** Search wrapped text and wide Unicode output, cycle
    matches, toggle case/whole-word matching, and change the font size. Click
    back into the terminal while search stays open and verify that typing goes
    to the shell. Switch tabs, hide/reopen, and resize around the search bar's
    minimum height; the query should survive without stealing another pane's
    focus. Verify Ctrl+C still interrupts the shell.
11. **GNU screen.** On a controlled host, create a session, start a long-running
    command, detach and reattach by exact name and full ID. Check duplicate
    human names, a missing target, and another already attached client. Errors
    must remain visible; attachment must not create a new session or evict the
    other client. Repeat after a connection loss.
12. **Saved destinations.** Save shell, tmux attach-only and screen attach-only
    profiles, restart the app, and reopen each. Destination and mode should
    survive, but every credential field must be empty. Canceling credential
    entry must leave a live connection intact. Replacing a profile by name and
    deleting one profile must leave the others unchanged.

13. **Jump routes.** Use controlled SSH hosts to test direct, one-hop and
    three-hop routes, mixed authentication, distinct host-key prompts, a
    rejected intermediate key, denial of direct TCP forwarding, late handshake
    cancellation and reverse cleanup. Repeat through a gateway that targets the
    first hop. Saved profiles and restored arrangements must ask for all
    credentials again.
14. **Session discovery.** List tmux and Screen sessions with attached and
    detached clients, choose an exact target, and cancel the picker. Check
    duplicate Screen names, unsupported names, no sessions, missing tools,
    delayed status after output EOF, oversized output and cancellation while
    listing. A stale picker must never start a new shell.
15. **Arrangements and broadcast.** Save mixed tabs with a custom divider
    proportion, restart, restore and reconnect explicitly. Check corrupt/newer
    preferences and cleanup failure. Broadcast harmless text to selected test
    shells with different bracketed-paste/cursor modes; verify the banner,
    source focus, Stop, disconnect/reconnect, hidden workspace and queued-input
    revocation. Never use a production command as a broadcast smoke test.
16. **Shell markers.** Install setup in controlled Bash/Zsh sessions and run
    successful and failing commands, Unicode-directory changes and a long-output
    command. Confirm existing prompt hooks run with the expected status,
    repeated setup is idempotent, command navigation follows resize/reflow,
    output selection excludes the next prompt and one-shot notifications fire
    once. Repeat inside the actual tmux/Screen configuration.

17. **OpenSSH import.** Preview a controlled configuration with defaults,
    negated patterns, independent jump aliases and identity hints. Compare
    destination resolution with `ssh -G -F <file> <alias>` without connecting.
    Confirm blocked external directives, duplicate-name rejection, atomic
    capacity failure, whole-paste bounds and disconnected saved profiles.
18. **Key bindings.** Capture a harmless function-key mapping, test literal text
    without implicit Enter and a complete mapped key tap in classic and Kitty
    modes, then enable/disable/edit/delete it. Test duplicate/reserved chords,
    holding the key while moving between panes, normal typing/IME and broadcast
    recipients with different keyboard modes. Reopen after restarting.

Only claim platform smoke tests that were actually executed. In particular,
Linux unit/native checks do not certify Windows, signed macOS or physical
Android/iOS behavior.
