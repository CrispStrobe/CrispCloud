# Embedded terminal

CrispCloud includes a terminal emulator connected to a real pseudo-terminal on
desktop, a built-in sandbox shell where host processes are unavailable, and SSH
through its existing connection layer.

The full transport, recovery, tmux and packaging contract is preserved in the
[terminal details](terminal-details.md).

## Backends

| Platform | Local shell | SSH |
| --- | --- | --- |
| macOS desktop | Unix PTY in an unsandboxed build; sandbox shell in the App Store build | Direct TCP |
| Linux desktop | Unix PTY; built-in shell if PTY setup fails | Direct TCP |
| Windows desktop | ConPTY; built-in shell if ConPTY fails | Direct TCP |
| Android | Built-in sandbox shell | Direct TCP |
| iOS | Bundled `ios_system` + Dash shell | Direct TCP |
| Web/PWA | Built-in in-memory shell | User-supplied secure WebSocket gateway |

The built-in shell never launches a host process. It supports navigation, file
inspection, basic file operations, pipelines/redirection and bounded
utilities. It does not provide `sudo`, background jobs or arbitrary external
programs.

## Open and use

Open the terminal with **F9**, the Tools menu or the command palette. It can be
hidden while keeping the session alive.

Default terminal copy/paste:

- Linux/Windows: `Ctrl+Shift+C` / `Ctrl+Shift+V`;
- macOS: `Command+C` / `Command+V`.

`Ctrl+C` remains an interrupt. Keyboard ownership follows the active pane or
terminal and is restored when the terminal is hidden.

## SSH

CrispCloud uses `dartssh2` with host-key verification. Supported features:

- password and key authentication, including the local SSH agent;
- saved profiles and OpenSSH config import;
- jump hosts;
- window resizing and keepalive;
- SSH port forwarding with saved profiles;
- broadcast input across selected sessions;
- reconnect and tmux/screen session browsing.

A plain reconnect starts a new shell. Reattaching a named tmux session preserves
that session only while the remote server and tmux process remain alive.

## Tabs and arrangements

- Multiple terminal tabs and split views.
- Search and adjustable text size.
- Saved arrangements and split sizing.
- Custom key bindings.
- Output triggers.
- Automatic session recovery after interruption.

Recovered sessions are explicitly presented; CrispCloud does not pretend an
exited remote process is still running.

## Security

- Host keys must be trusted before authentication.
- Remote terminal output cannot read or write the clipboard. Clipboard
  extensions are denied unless the user explicitly copies or pastes.
- Each native local connection owns its security-scoped folder grant.
- A hidden terminal keeps its session; explicit disconnect releases it.
- SSH has a 30-minute inactivity timeout. Terminal I/O and resizing count as
  activity.
- Browser SSH requires a gateway supplied by the user. CrispCloud does not
  provide or select a relay.
- The shell sees its normal local or remote filesystem; cloud accounts are not
  silently mounted into it.

## Limits

- The browser cannot open raw TCP. A secure WebSocket gateway is mandatory.
- The built-in shell is not a full Unix environment.
- iOS host-process execution is intentionally unavailable.
- Windows ConPTY is implemented upstream but remains experimentally marked;
  packaged smoke tests are required.
- The terminal does not restore an exited process after reconnect.
- Live SSH/tmux behavior and platform packaging are separate acceptance gates.

## Related

- [iOS shell and staged workspaces](ios-shell.md)
- [SSH forwarding, recovery and packaging details](terminal-details.md)
