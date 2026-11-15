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
`main`. No additional branch merge or cherry-pick was required at that point.
During development, main advanced through PRs #139, #141, #142 and #144–#148
to `50b45932`; those Office-only changes were merged into the feature branch
too, preserving their main-branch history.

A later branch audit found `integrate/utf16-custom-xml-20261115` equivalent to
main for its bibliography implementation and tests. The new
`codex/zotero-support-20261115` branch at `454f0ec9` contains separate unmerged
work that appeared after the initial integration baseline; it is not included
in this terminal continuation. Its Office changes overlap ongoing main work,
and it had no open pull request at the time of that audit.

## Implemented coverage

| Area | Existing support | Added in this continuation |
| --- | --- | --- |
| Terminal emulation | PTY, ANSI/VT rendering, Unicode, alternate screen, mouse, bracketed paste | Keep upstream emulator and existing clipboard boundary |
| Local shells | Desktop PTY/ConPTY; built-in shell; embedded iOS shell | Up to eight independent terminal tabs; two-pane horizontal/vertical layouts; names, focus isolation and close confirmation |
| SSH | Password and encrypted private-key authentication; verified host keys; explicit browser gateway | Up to 50 named destination profiles with no saved credentials; safe concurrent writes and unchanged trust checks |
| Persistent remote sessions | Named tmux create/attach and exact attach; detach; reconnect | Explicit GNU screen create and attach, bounded exact-listing resolution and non-evicting detach |
| Navigation | Scrollback, selection and explicit copy/paste | Unicode/wrap-aware literal search, case/word options, bounded highlights and navigation; per-tab font zoom |
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

The reference workflow areas come from iTerm2's
[feature highlights](https://iterm2.com/documentation-highlights.html) and
[tmux integration guide](https://iterm2.com/documentation-tmux-integration.html).
See [the terminal guide](terminal.md) for exact supported behavior and controls.

## Validation policy for this continuation

Use local focused tests, static analysis and available platform smoke checks.
Push incremental checkpoints to the remote feature branch. GitHub Actions may
remain queued on the free tier; development and completion do not wait on that
queue. Record unexecuted platform checks explicitly.

## Local validation results

The implementation at `44434bad` was checked with the repository's pinned
Flutter 3.47.8 / Dart 3.13.7 toolchain on Linux on 15 November 2026.

| Check | Result |
| --- | --- |
| Native terminal regression cohort | 229 passed, 2 platform-specific skips across 22 test files |
| Actual Linux PTY | Passed TTY allocation, ANSI/final output, resize, Unicode input/output, Ctrl+C and disposal checks |
| Screen command resolver | Passed POSIX shell fixtures for exact IDs/names, duplicate/missing/unavailable sessions, prefix collisions, bounds and quoting |
| Static analysis | No issues across all 28 changed Dart files |
| Formatting and whitespace | Clean; all 28 Dart files already formatted |
| Dependency resolution | Pinned lockfile resolution succeeded; dependency manifests and lockfile unchanged |
| CI configuration | YAML parsed and referenced terminal test paths verified; new suites included in Chrome, Windows and macOS jobs |
| Visual layout | Actual widgets rendered and inspected at desktop and narrow Android sizes using synthetic connections; split layout, collapsed mobile view, search highlights and extra keys checked |
| Browser execution | Blocked before startup: Chromium aborted at `process_singleton_posix.cc:297` with `socket() failed: Operation not permitted (1)`; browser tests did not execute |

The two native skips are the Windows ConPTY test and the macOS-only interactive
shell smoke test. The visual fixtures are UI checks, not live SSH/tmux/screen
connections or physical-device tests. Production cleanup remained unchanged;
test streams now explicitly complete cancellation on Flutter's simulated clock.

Live SSH gateway/host sessions, physical Android/iOS keyboard/IME behavior,
signed macOS and packaged Windows remain release smoke checks. A local attempt
to start tmux/screen persistence was blocked by this workspace's Unix-socket
restrictions; resolver fixture success does not certify live persistence.
No GitHub Actions result was awaited or required for this continuation.
