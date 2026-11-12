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
G10, G11 and G18 remain **implementing** until their code, tests, documentation
and remote checkpoints are recorded. The baseline still has seven closed
scopes and five implemented scopes with named acceptance pending.

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
