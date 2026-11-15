# Terminal feature coverage

CrispCloud reuses xterm2 for terminal emulation and owns its transports, session
lifecycle and file-browser integration. This document tracks application-level
coverage against a desktop terminal workflow; it is not a claim of complete
iTerm2 compatibility.

## Integration baseline

The terminal workspace continuation starts at `ebb8d13c` on `main` (15 November
2026). All 16 remote branches were reviewed before development. PR #136 is
already merged, as are the subsequent worksheet and Office documentation PRs
#137 and #138. The two remaining divergent branch histories have identical
trees to their squash merges. Both storage-carving branches are ancestors of
`main`. No additional branch merge or cherry-pick is required.

## Coverage before this continuation

| Area | Existing support | Work in this continuation |
| --- | --- | --- |
| Terminal emulation | PTY, ANSI/VT rendering, Unicode, alternate screen, mouse, bracketed paste | Keep upstream emulator and existing clipboard boundary |
| Local shells | Desktop PTY/ConPTY; built-in shell; embedded iOS shell | Independent terminal tabs and split views |
| SSH | Password and encrypted private-key authentication; verified host keys; explicit browser gateway | Reusable destination profiles without saved credentials |
| Persistent remote sessions | Named tmux create/attach and exact attach; detach; reconnect | GNU screen launch and attachment |
| Navigation | Scrollback, selection and explicit copy/paste | Find in scrollback and font zoom |
| Mobile | Extra keys and direct SSH | Screen prefix alongside tmux prefix |

## Remaining larger parity areas

- Native tmux control-mode mapping of remote windows and panes.
- SSH jump hosts, agent forwarding, connection multiplexing and port forwarding.
- Shell integration markers, command navigation and command-aware notifications.
- Durable window arrangements and optional secure credential/identity profiles.
- User-defined key maps, triggers, broadcast input and automation APIs.
- Inline graphics/file-transfer protocols and their explicit trust controls.

These are independent capabilities and require separate implementation and
validation. Running tmux in a PTY does not implement iTerm2's native tmux
control-mode integration.

## Validation policy for this continuation

Use local focused tests, static analysis and available platform smoke checks.
Push incremental checkpoints to the remote feature branch. GitHub Actions may
remain queued on the free tier; development and completion do not wait on that
queue. Record unexecuted platform checks explicitly.
