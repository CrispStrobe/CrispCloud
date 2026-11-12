# External tools and archive endpoint continuation

Baseline: `d76fe9bbb743e4194bfd54edc930abe9ad4f4854`, following the
[preceding continuation](continuation-20261112.md). The 51 stable gap IDs and
their earlier evidence remain in the [gap register](README.md).

## Active increments

| Gap | Concrete implementation | Required completion evidence |
| --- | --- | --- |
| G10 | Source-bound external editor sessions with native private staging, watched save generations, conflict-aware upload and retained unsent edits | Save bursts serialize/coalesce; original account/path checks survive reconnect/restart; failures retain recoverable local edits; cleanup follows explicit close and durable outcome |
| G11 | Configured read-only text/image comparison tools for captured local or remote pairs | Separate literal arguments and distinct private inputs; reviewed executable launch; source/cancellation checks; detached tools cannot trigger premature cleanup; originals remain untouched |
| G18 | Captured writable archive-member endpoints with staged transaction review and verified whole-container publication | Supported formats preserve contents/protection/metadata within declared bounds; cancellation, conflicts and publication failure preserve originals; stage-only outcomes cannot authorize move-source deletion |

G10 establishes reusable private staging/lifetime rules before G11 is published.
G18 develops independently against the existing archive workspace. Host wiring,
shared API integration, Flutter runners and remote publication are serialized.
Each coherent code/test/documentation increment is saved to a remote feature
branch, followed by its validation and acceptance-status update.

## Common boundaries

- Capture source/account/file identity before asynchronous preferences, staging
  or process preparation. A current pane or display label cannot replace that
  captured capability later.
- External programs receive reviewed separate arguments. Tool exit alone does
  not establish that a detached application has released its private files.
- Never interpret a private-stage write as a successful original-file save or
  a committed archive transaction. Publication and verified outcomes have
  explicit ownership.
- Keep unsent edits and failed transaction evidence recoverable. Ordinary
  session metadata contains references and fingerprints, never credentials or
  archive passwords.
- Existing editor/archive size bounds remain until a separately tested memory,
  disk, cancellation and consistency design justifies changing them.
- Native program launch, signed permissions and live-provider interoperability
  retain named target-runtime acceptance checks. Passing fixtures do not close
  those checks automatically.
- Reuse existing permissive dependencies. Any additional dependency requires
  exact version, provenance and license review before inclusion.

## Validation and checkpoints

Implementation and observed gates are appended as each increment is completed.
G11 is **implemented / native acceptance pending** and G10 is **implemented /
native and live acceptance pending**. G18 remains **implementing** until its
complete workflow and checkpoint are recorded.
The baseline had seven closed scopes and five implemented scopes with named
acceptance pending; G11 and G10 raise the latter count to seven.

### Private staging foundation

The shared [private staging contract](../private-tool-staging.md) is implemented
with retained application-data directories, bounded verified streams,
checksummed manifests and native session leases. A separate directory mutation
lease excludes reopening during cleanup, including the Windows interval in
which the child handle must close before its directory can be deleted. Closed
retained handles cannot falsely report a later deletion as successful.

Observed gate: **10 native filesystem tests passed**, including the explicit
cleanup/reopen race and close-then-delete regression. Narrow pinned Dart
analysis reported **no issues**. No dependency was added. This checkpoint is a
foundation only; it does not mark G10 or G11 complete or imply target-platform
application-launch acceptance.

Remote checkpoint: `47b7c57012cfc23f8100bad8c5a7fb4c53171a12` on
`feature/private-tool-staging-20261112`,
[draft PR 75](https://github.com/CrispStrobe/CrispCloud/pull/75).

### Conditional publication foundation

[External remote editing](../external-remote-editing.md) now has a narrow
provider contract for publishing only the reviewed existing revision. Its first
adapter uses Dropbox's immutable account identity, exact file ID/path/revision,
revision-addressed reads, bounded sequential upload sessions and strict update
commit. An uncertain response retains the caller's pending generation for
reconciliation; no unconditional retry or alternate destination is available.

Observed gate: **17 provider tests passed** and narrow pinned analysis reported
**no issues**. Ambiguous finish errors are covered explicitly. The watched
editor session and UI remain in progress; the provider foundation alone does
not close G10. Other providers need their own original-preserving publication
contract before they can upload external edits automatically. No dependency was
added and no S3/Azure transfer adapter was changed.

Remote checkpoint: `2297f8e3f7a261c8cbf80b48ffa70bf25df2998d` on
`feature/conditional-remote-publication-20261112`,
[draft PR 76](https://github.com/CrispStrobe/CrispCloud/pull/76).

### G11 — external comparison tools

The [external comparison workflow](../external-comparison.md) is connected to
Tools, configurable menus, overflow and verified context-menu pairs. Both local
and remote inputs become distinct private copies. Separate configuration and
launch reviews use literal argument lists, fresh source versions, executable
identity and final copy digests. Launch-attempted files survive close/restart
until explicit tool-closed confirmation permits cleanup; originals are never
published by the comparison workflow.

Observed gates: **80 tests** across the five service/dialog/popup/offline-help
suites, **36 tests** across source capture and menu model/command ownership, and
**3 full-browser integration tests** in an isolated worktree of this exact
increment and its remote base. Total: **119 passing tests across nine suites**.
Initial fixture failures were corrected: a test selected only one row, an
argument assertion compared presentation rather than parsed tokens, and a
cancelled stream's root-zone completion needed the widget runner's real async
boundary. No production behavior was weakened to make those assertions pass.

The three offline guides were updated and their source/translation digests
validated. Narrow feature analysis is clean; host files retain existing
unrelated warnings. Installed-tool acceptance on Linux/Windows/macOS remains
explicit, as do provider metadata and OS path-launch race limits. No dependency
was added. G11 is implemented for the documented private-copy workflow; G10
merge-back and automatic remote editing remain separate.

Remote checkpoint: `77af99427e2d7d1b3719a22376a4ebf56508edbd` on
`feature/external-comparison-tools-20261112`,
[draft PR 77](https://github.com/CrispStrobe/CrispCloud/pull/77).

### Archive publication and recovery foundation

The [archive publication foundation](../archive-endpoints.md) adds a bounded
intent journal, exclusive operation leases, expected-record/catalog checks,
private candidate verification, preserved native access metadata, exact
no-replace backup/install and whole-container confirmation. Cleanup verifies
both published and recovery contents; unknown or changed evidence is retained.
A failed unacknowledged journal intent revokes subsequent mutation authority.

Observed gate: **24 tests passed**, including real native publication and
lease exclusion, concurrent recovery, lost acknowledgements, changed originals,
changed access policy, candidate policy changes before installation and file
growth during bounded cleanup. Narrow foundation analysis reported no issues.
No dependency was added.

Production publication is currently **native local only**. A remote backend
needs a separately proven access-policy contract as well as exact no-replace
movement; no current remote adapter claims it. Browser operation leases and
remote access-policy preservation are implementation prerequisites, not merely
unperformed live tests. Two exclusive moves have an original-name absence
window and are not described as atomic replacement. Durable packing drafts
remain G21. G18 stays implementing while endpoint transactions, host routing
and recovery UI are connected.

Remote checkpoint: `005771bd53f2cd437cb70b23ebe83c224792bd00` on
`feature/archive-publication-recovery-20261112`,
[draft PR 78](https://github.com/CrispStrobe/CrispCloud/pull/78).

### G10 — external remote editing

The [external editing workflow](../external-remote-editing.md) now joins private
retained copies, reviewed executable/arguments, initially-off upload consent,
serialized watched generations, exact-source recovery, explicit conflict
replacement and uncertain-commit reconciliation. Dropbox is the initial
revision-guarded publication adapter. Other bounded-download sources expose
independent local editing/export. A copied/exported local file never marks the
remote original saved. Tools, configurable menus, overflow and verified popup
captures use the actual original source independently of pane labels.

Observed gates: **62 distinct core/provider/export/lifecycle/native-staging
checks**, **16 dialog checks**, **10 source/popup capture checks**, **4
full-browser checks**, and **33 offline guide/reader checks**. Total: **125
distinct passing checks across 11 suites**. The final five lifecycle checks were
rerun after the cleanup corrections. Earlier failed runs identified a quiet
native watcher cancellation hang, a specific-error classification issue and
cleanup/shutdown catalog races. Those were fixed without weakening publication
or retained-content checks. A final lifecycle assertion was aligned with the
implemented immediate reopening of surviving private files.

Focused feature analysis is clean, and English/German/French guides validate
with 23 aligned current topics. Files/generations remain limited to 64 MiB;
native/live acceptance and further original-publication provider contracts stay
explicit. No dependency was added.

Remote code checkpoint: `c5ddfffd011dbaf61c3cbd3dc8f7efc1c5f52e2f` on
`feature/external-remote-editing-20261112`,
[draft PR 80](https://github.com/CrispStrobe/CrispCloud/pull/80).

### G18 — native writable archive endpoints

The [archive endpoint workflow](../archive-endpoints.md) now connects ordinary
captured source selections to native local archive destinations. F5, paste and
context-menu commands retain the exact outer container and current inner
directory before asynchronous work. Private member copying produces a concrete
whole-container review; only verified physical publication returns a transfer
receipt. Existing member editing, renaming, removal and new empty-directory
creation share the same reviewed publisher. Nested archives retain their
separate passwords and captured container generations.

Moves publish before attempting revalidated source-file deletion. Source
directories and files without a valid conditional-removal contract remain with
an explicit partial result. Source revision maps are copied at capture, and
empty, malformed or shadowing revision values cannot authorize deletion.
Cancelled archive pastes preserve cut references, including when another actor
has removed the original source. A newer clipboard intent or a navigated and
reopened archive cannot retarget an older pending action.

ZIP metadata handling preserves supported modification times, permissions and
encrypted payloads, including ZIP64 count boundaries. Signed-negative UTC
timestamp inputs remain read-only with the pinned reader. Malformed shared or
overlapping local metadata cannot amplify scanning; inconsistent encryption
markers refuse writing. All original protected members in a supported writable
archive must authenticate before replacement or removal is allowed. Existing
directory metadata remains unchanged when importing children into that directory.

The account-scoped recovery UI is reachable through Tools and overflow even
from an ordinary folder when an interrupted publication has left the original
archive name temporarily absent. A recovery attempt refreshes the captured
destination and requires a fresh import review. Restart recovery carries no
source-deletion authority.

Observed final gates: **104 passing checks across eight archive suites**, and
**58 distinct passing checks across six host, clipboard, gathering, browser-menu
and offline-help suites**. Total: **162 checks across 14 suites**. The final
archive gate includes seven added audit regressions for malformed policy,
source revision evidence and authentication of later protected members. The
two earlier dialog failures were caused by animated fake time expiring a real
stream deadline; the corrected fixtures execute real I/O within the test
runner's real asynchronous boundary and retain the original review, source
preservation and publication-receipt assertions.

Focused feature analysis is clean; the shared menu file retains its existing
unrelated findings. English, German and French guides validate with 23 aligned
topics. No dependency was added.

**Status:** native local increment delivered. G18 remains partially implemented
because no remote adapter supplies the required publication access-policy
contract, and browser publication still needs an operation-lifetime lease.
Those are code prerequisites, separately tracked from native release acceptance.
The two-move publication absence window, bounded in-memory drafts and G19–G24
follow-on scopes remain explicit.

Remote checkpoints on `feature/writable-archive-endpoints-20261112`:
core `e32401cebba2d72874f02c111d8715e83959d28c`,
UI/help `c74986aea4253d97ae2488b3800754941670d162`, and
reviewed fixes `af79a894f84a1853f6e0b7b4f56c3051ebfb3fd3`.
Review: [draft PR 81](https://github.com/CrispStrobe/CrispCloud/pull/81).
