# External comparison tools

CrispCloud can open a reviewed pair of files in an installed text or image
comparison tool. It makes a private copy of **both** inputs, including local
files, and shows the source of each copy before opening the tool. Changes to
those copies are never copied back by CrispCloud. There is no merge or save-back
action in this workflow.

## Choose a tool

Open **Tools → External comparison tools** to configure a text tool and an image
tool separately. Each preference contains an absolute executable path and an
argument template. External comparison software is not bundled or selected
silently for you.

An argument template must contain `{left}` and `{right}` exactly once each, as
separate arguments. For a tool that accepts two file paths, use:

```text
{left} {right}
```

If the tool supports an option separator, its template might be:

```text
-- {left} {right}
```

Other options depend on the installed tool. Separate arguments with spaces. To
include spaces in a literal option value, quote that value as a JSON string,
for example `"label with spaces"`. The executable field accepts the actual
absolute path, including spaces, without surrounding quotes. Saving a preference
does not open a tool.

The template is an argument list. There is no shell expansion: wildcards,
environment variables, pipes and command substitutions remain literal text.
The two placeholders are replaced with private copy paths, one argument per
path. On Windows the executable must be an `.exe` file. Known shells and script
interpreters are not accepted as comparison executables.

## Prepare and review a pair

Select two files in the active pane, or select one file in each pane. If a pane
has no selection, its cursor file can supply its one input. Choose **Compare
with external tool**, select text or image comparison, and prepare the pair.
Both inputs must be verified regular files from an available source. Folders,
symbolic links and archive entries must be handled outside this workflow.

The file context menu can also compare a pair selected together or a file with
one unambiguous same-named file in the other pane. The pair is captured when the
menu opens. Changing the selection afterward does not replace that pair;
changing its source or navigating away invalidates it. Duplicate matching names
in a collection require an explicit selection.

The preparation view identifies the two original source accounts and paths.
The review then shows the resolved executable and the complete argument list,
including both private paths. **Open comparison tool** is a separate action.
Preparing or canceling the review does not launch anything.

Same names and paths from different accounts remain separate inputs. The
source comes from each verified file row, including verified collection rows;
it is not inferred from which side of the window contains the file.

The configured tool runs with the normal permissions of your desktop account.
CrispCloud supplies private copies as the comparison inputs and performs no
publication to the originals; it does not sandbox the external program or
restrict extra literal options you configure for it.

## Retained comparisons

After a launch is attempted, private copies remain available when the dialog
or CrispCloud closes. They also remain if the operating system reports a launch
failure: a launcher may have opened another process before its acknowledgement
was lost.

Return to **External comparison tools** to inspect retained comparisons. Close
all external windows using a comparison, select **Remove private copies**, and
confirm that those windows are closed. Removing a comparison deletes only its
private directory. It does not delete either original.

There is no automatic cleanup based on process exit. Some comparison programs
hand work to an existing window or a detached child, so the initial process
cannot reliably tell CrispCloud when the files are no longer in use. Retained
records are offered for inspection and cleanup after restart; they are not
automatically relaunched and do not restore permission to read or change the
original source.

Copies prepared during this session are removed if their review closes before
any launch attempt. An interrupted preparation or an unreadable retained record
is kept for explicit cleanup rather than silently discarded.

## Limits and availability

| Item | Current limit or behavior |
| --- | --- |
| Platforms | Native Linux, Windows and macOS outside the Mac App Store build |
| Browser and mobile | External process launch is unavailable |
| Inputs | Two regular files; at most 256 MiB each |
| Retained comparisons | Eight before another preparation is refused |
| Preparation | At most 15 minutes, with cancellation and source checks during reads |
| Final launch validation | A separate 15-minute deadline before the OS handoff |
| Preferences | Separate text and image executable/argument lists on each platform |
| Template | At most 64 arguments; at most 4,096 characters per argument/path; 32 KiB serialized configuration |
| Original changes | No merge-back, remote upload, rename or deletion |

The copy limit bounds bytes accepted by the staging workflow. A provider adapter
may buffer data internally, so it is not a promise that every transport uses
constant memory. The eight-session admission limit bounds application-created
input payloads to 4 GiB; an external program can grow its private files, so this
is not a disk quota. Existing interrupted or older records can be shown beyond
the admission limit and must be cleaned before new work is prepared.

A missing source, changed account, revoked local grant, changed file, changed
executable, altered private copy, cancellation or timeout prevents a new launch
while validation is pending. Once the OS handoff begins, CrispCloud cannot
recall a detached program; the copies remain retained. If preparation cannot
remove an incomplete private directory, the session remains visible for cleanup.

## Source consistency and technical boundaries

The following details describe the current guarantees and their limits.

### Capture and validation

`captureExternalComparisonPair` captures both verified original rows
synchronously. Each input stores an immutable file snapshot, its actual storage
reference, the original backend, and the original navigation, operation-session
and local access-grant guards. The capture never resolves a newer account after
an asynchronous menu choice. Its guard latches invalidation; restoring a pane,
account or grant does not revive a capture once its loss is observed.

Preparation checks each source with `stat` before reading, after its copy, and
again after both copies. The baseline retained for launch includes the fresh
metadata obtained before copying, even when the directory listing lacked a
size or modification time. Available revision/ETag identifiers, stable object
identifiers, sizes, modification times and file types are compared. The
original path is used only with its original backend for stat/read operations.

This does not create an atomic snapshot on every provider. A provider that
exposes no revision and a replacement preserving all reported metadata may
escape detection. The prepared bytes are nevertheless fixed private copies,
and their SHA-256 digests are checked again before launch. No source-write
capability is restored from a retained manifest.

The executable is resolved and inspected with the existing native command
host, then checked again against its reviewed path, type, size, timestamps and
mode. Both private file digests and both source versions are checked again
before persisting launch intent. Source/session guards are checked immediately
before the final OS call. These checks cannot remove the narrow filesystem
race between the last check and an OS path-based launch; this is not an atomic
execute-by-handle guarantee.

### Private storage and launch lifetime

The shared `PrivateToolStagingStore` owns per-session private directories,
exclusive native leases, bounded streaming writes, content digests and
checksummed manifests. Comparison records use the `external-compare` kind.
Generated file names are `left` and `right`, with a short safe extension where
available, so identical original names cannot collide.

The G11 service writes a durable launch-intent record **before** passing paths
to `Process.start`. It launches the resolved executable with a separate argument
list, `runInShell: false`, and detached mode. The working directory and the two
substituted inputs are inside the private session. No process exit is used as
cleanup authority. A failed acknowledgement or failed post-launch metadata
write conservatively retains the session.

Disposing the service releases native leases and retains files. If disposal
occurs while a launch acknowledgement or explicit cleanup is pending, that
operation releases its lease when it settles. The service does not race the
launch acknowledgement with deletion, because a late launch might still need
the copies.

Cancellation reaches pending metadata futures and cancels the upstream source
stream. A newer preparation invalidates the older intent. Native filesystem
creation and cleanup are awaited so ownership of an incomplete stage is never
lost. These filesystem operations and the OS launch acknowledgement may settle
after a cancellation; they do not authorize a later unreviewed launch.

### Integration ownership

`ExternalComparisonPair.dispose()` is idempotent and invalidates the capture.
`showExternalComparisonDialog(..., pair: pair)` takes ownership until the dialog
closes. A caller that opens a context menu must dispose an unused capture when
the menu closes; a chosen action must hand ownership to the dialog before that
popup completion callback runs. `ExternalComparisonMenuAction` implements this
handoff for the browser context menu.

Calling `showExternalComparisonDialog` without a pair opens preferences and
retained-session cleanup. `showExternalComparisonForSelection` captures an
explicit selection before opening the same surface. The app-scoped provider
keeps retained-session leases independent of a particular dialog's lifetime.

## Verification

Focused automated coverage includes configuration persistence and corruption,
literal Unicode/space/shell-character arguments, separate same-named accounts,
local copy isolation, fresh metadata baselines, source changes during either
read, missing files, cancellation of a hung stat or stream, deadlines, newer
intent invalidation, final executable/source/digest checks, failed launches,
retained-session admission, disposal during delayed launch acknowledgement,
restart without replay, explicit cleanup, and native private-stage persistence.

Widget coverage includes separate review before launch, cancel/close behavior,
retained cleanup confirmation, real panel source capture, source/grant changes,
and enlarged German and Arabic layouts. The host context-menu suite separately
checks popup capture and ownership handoff. These automated tests use a
controlled launcher. Acceptance with installed GUI comparison tools on each
supported desktop OS remains a separate integration check; the workflow does
not claim that every external tool accepts every template or lifecycle option.

Focused test files:

```text
test/external_comparison_test.dart
test/widget/external_comparison_dialog_test.dart
test/widget/external_comparison_context_test.dart
test/widget/external_comparison_menu_action_test.dart
```
