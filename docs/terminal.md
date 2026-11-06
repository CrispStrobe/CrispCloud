# Terminal, sandbox and distribution

The embedded terminal deliberately has different backends per platform and per
distribution channel. macOS App Sandbox and iOS do not permit a normal
`Terminal.app`-style shell, so the app must choose between a sandboxed real
shell, a built-in command layer, or an unsandboxed Developer ID build.

## Backend matrix

| Platform / channel | Backend | Filesystem scope |
| --- | --- | --- |
| **macOS App Store** | Real `/bin/zsh` under a PTY (`/usr/bin/script`) | App container + folders granted via Browse/Grant Access |
| **macOS Developer ID / direct DMG** | Real user shell (`/bin/zsh -i`) | Normal user-level filesystem access, subject to macOS TCC prompts |
| **iOS App Store** | Built-in command interpreter (no process spawning) | App container + document-picker grants |
| **Windows / Linux** | Real user shell | Normal user-level filesystem access |
| **Web** | Unavailable | Browser sandbox |

A Developer ID build is signed/notarized but does **not** enable App Sandbox.
Notarization and sandboxing are independent. This is the same reason
Double Commander and similar file managers ship macOS DMGs outside the App
Store: they need normal filesystem access. TCC still protects Desktop,
Documents, Downloads and removable volumes, so even unsandboxed builds can
trigger system permission prompts or require Full Disk Access.

## macOS App Store: sandboxed real shell

The entitlement requires:

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.bookmarks.app-scope</key><true/>
```

The flow is:

1. The user selects a folder with **Browse** or **Grant Access**.
2. `MacOSBookmarkService` stores a security-scoped bookmark for that folder.
3. Before starting the shell, `MacosFileService.beginStreamAccess` calls
   `startAccessingSecurityScopedResource` and keeps it active for the terminal
   session.
4. The shell is started in that folder under a PTY.

The child shell inherits the app's sandbox. It can only see the app container
and granted folders. It cannot see unrelated paths, other volumes, or
root-owned files.

### Limits

- `/Library`, `/System`, other users' homes and similar paths remain blocked.
- Root-owned files such as `/Library/DropboxHelperTools/...` are unreadable even
  after a folder grant because a bookmark cannot change POSIX ownership/mode.
  The terminal reports this as an ownership/permission problem instead of
  asking for the folder again.
- Root access is never available from a sandboxed build.
- Background execution and process lifetime follow normal app rules.

## macOS Developer ID: unsandboxed shell

A Developer ID build can omit App Sandbox. The terminal then starts a normal
interactive shell with the user's rights. This is the Terminal.app-like mode.
macOS TCC may still prompt for protected folders; root-owned files still need
`sudo` or an elevated helper.

## iOS: built-in command layer

iOS does not allow spawning arbitrary system binaries or shell helpers. The
terminal therefore provides a built-in interpreter that uses `dart:io` inside
the app sandbox. It supports:

```
pwd cd ls dir cat mkdir touch rm cp mv echo date whoami uname clear exit help
```

`ls` supports `-l` and `-a`-style flags; `rm` supports `-r`/`-f`; `cp`/`mv`
support files and directories. The working directory starts in an accessible
app folder. Files outside the app container are only reachable through
document-picker grants.

This is the same architectural choice as a-Shell (built-in `ios_system`
commands) and iSH (an emulated userland): the app brings its own commands
instead of pretending to be a system terminal.

## Terminal UI

- The input line is a normal text field. The file browser's global key handler
  defers to any focused text field, so printable keys and Cmd+C/V reach the
  terminal instead of copying file selections.
- Terminal output is selectable. Right-click opens the standard text selection
  toolbar plus **Copy all**.
- The header has a **Copy all** button that copies the entire session buffer.
- PTY ANSI colour/cursor escapes are stripped before display.
- Closing/restarting the terminal releases the security-scoped access it held.

## Build flavors

Recommended split:

- **macOS App Store**: sandboxed target, option 1 (real sandboxed shell) with
  the built-in layer as fallback.
- **macOS Developer ID**: unsandboxed target, option 3 (normal shell).
- **iOS App Store**: built-in layer only.
- **Windows/Linux**: normal shell.

The app can detect the sandbox at runtime (`APP_SANDBOX_CONTAINER_ID`) and pick
the appropriate backend, or use separate build flavors/entry points.

## Security notes

- Never log command text that may contain credentials or tokens.
- SSH host keys are confirmed before authentication; private keys and
  passphrases use the app's secure storage.
- The built-in shell, like the real shell, executes user-authored commands.
  Do not expose it to untrusted input.

## Focus model

Keyboard focus is a sticky, explicit target: **left pane**, **right pane**, or
**terminal**. Clicking a pane or the terminal header changes the target; it is
not stolen by refreshes, tab changes or dialogs. The active surface is visibly
highlighted (pane highlight / terminal header colour). While the terminal owns
focus, printable keys, arrows and Cmd+C/V go only to the terminal; the file
browser's type-ahead and global shortcuts are suspended until focus is moved
back to a pane.

The terminal no longer prints its own `$ ` prompt marker: the real shell prompt
is the only prompt. A command typed before the shell prompt appears is queued
and sent after the prompt is detected.
