# Gap closure continuation — 12 November 2026

Continuation baseline: `403e942dc99779883210125a01841ef209e19d2e`.
The preceding scope and eight implementation increments remain preserved in the
[gap register](README.md) and [validation record](validation-20261112.md).

## Active increments

| Gap | Concrete increment | Completion boundary |
| --- | --- | --- |
| G05 | Persistent gathering stack with original-source references, captured destination review and per-item outcome reconciliation | Deduplicate by identity; retain canceled, skipped, unavailable and failed references; remove only confirmed successes |
| G09 | Reviewed desktop command entry with literal arguments, filename/path insertion and scoped customisable shortcuts | Capture actual local context and resolved executable; preserve editor/terminal input ownership and existing execution review |
| G25 | Verified byte-offset FTP download resume through existing recovery/staging contracts | Negotiate server restart support, validate original source and partial output, preserve strict TLS and owned transport cleanup |
| G49 | Maintained English/German/French help with offline topics and explicit language fallback | Correct stale canonical instructions first; keep translated workflows aligned and detect outdated topic versions |

Each implementation is independently reviewed and receives focused regression
coverage before closure. Coherent code and documentation checkpoints are pushed
to stacked remote feature branches as work proceeds. Root-owned integration
serializes shared host changes, Flutter runners and remote commits.

## Continuation rules

- Existing account, source, tab, grant and navigation identity checks remain in force.
- A grouped operation may complete partially; only observed successful outcomes may change gathering references or recovery state.
- Command entry uses a literal argument vector and the existing execution review.
- FTP offset support alone is insufficient evidence for safe recovery; source and partial-file verification must be connected to the actual resumed stream.
- Translated documentation must describe delivered behavior and supported limits; native/browser acceptance remains separately recorded.
- New dependencies require permissive license and provenance review. No dependency is planned for these increments.

Follow-on work is selected from the existing stable gap IDs after these
prerequisites are verified. Final results, branch checkpoints and remaining
boundaries are appended here rather than replacing earlier evidence.

## G25 — Verified FTP download resume

The first code checkpoint, `6b122d6`, is preserved on
`feature/ftp-download-resume-20261112` in
[PR #70](https://github.com/CrispStrobe/CrispCloud/pull/70), stacked on the
continuation scope branch [PR #69](https://github.com/CrispStrobe/CrispCloud/pull/69).
The follow-up adds exact cleanup of consumed, journal-owned partial files and
keeps prior references across retries and failed checkpoint confirmations.

The final eight-suite transfer gate passed **285 tests** across resume,
retained-stage cleanup, local backend, operation service, recovery, phase guards,
FTP session and physical transport lifetime. Tests exercise real native files
and loopback plain/implicit/explicit TLS peers. The shared cleanup services and
their new tests pass focused analysis without findings. No dependency was added.

A final three-suite crash-edge gate passed **89 tests** after review found a
zero-byte newest payload could hide an older usable prefix. Recovery now skips
only an empty regular candidate, keeps its path for later verified cleanup, and
can use the older verified prefix. Directory and symlink candidates still stop
recovery. Counts overlap and are not summed as unique tests.

Source bytes, prefix bytes and the complete reconstructed file are verified;
the transport advertises range capability only after restart negotiation.
Cleanup checks the published digest and retained prefix, rejects links or
unrelated directory entries, and removes only the exact payload and empty
private directory before move-source deletion. Errors retain review evidence.
The [feature documentation](../ftp-resume.md) records bounds and protocol limits.

Status is **implemented / live-server acceptance pending**. Selected real
servers and signed/native builds remain G50 acceptance; upload resume, FXP and
direct-protocol proxies retain their separate gap IDs.

## G09 — Reviewed command entry

Command entry adds typed programs and saved commands, literal typed arguments,
filename/path insertion, bounded absolute-directory PATH lookup and an immutable
prepared invocation. It captures the actual ordinary local source, pane session,
tab, navigation, selection, grants and filesystem evidence. Returning to an old
selection does not revive a stale review. The existing separate Run action checks
that evidence again; cancellation or closing during preparation starts nothing.

The eight-suite command/context/runner/keyboard gate passed **152 tests**.
Coverage includes real temporary filesystem evidence, source/tab/grant changes,
single-use preparation, default/custom shortcuts, output/exit completion and
enlarged German/Arabic dialogs. Focused analysis of new implementation/tests and
the review-lifetime changes has no findings. No dependency was added.

Independent review found the original argument-prefix check both missed some
recognized inline-code modes and rejected option-like data after a script.
The corrected finite interpreter grammars preserve script arguments, reject
unsupported prefix/evaluation modes and normalize known shell names on Windows.
The final service/dialog/context gate passed **62 tests**, including 14 added
interpreter/alias/Windows regressions. Its changed Dart files analyze cleanly.
The 152-test and 62-test gates overlap and are not summed.

The final simulated-process test needed alternating bounded event-loop turns
and widget pumps because Dart's completed stream-cancellation future is owned
by the root zone. The test still requires actual run completion, exit zero,
exact output and rendered exit status; production execution was not changed to
accommodate the test harness.

Status is **implemented / native acceptance pending**. Windows argument
transport, Linux/macOS permissions and symlinks, signed/store restrictions and
actual keyboard dispatch remain G50 acceptance. The [feature guide](../command-entry.md)
states the finite interpreter-option model and the remaining path-based launch
race explicitly.
