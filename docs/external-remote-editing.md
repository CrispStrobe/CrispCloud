# External remote editing

## Scope

External editing creates a private, retained working copy of one captured remote
file, opens that copy in a configured desktop application after review, and
watches completed local saves. Conditional upload to the original is currently
supported for Dropbox files that satisfy the publication contract below. Other
sources with an explicit bounded-download capability support local editing,
retention and independent export. They never report that the remote original
was saved.

The application owns sessions independently of the dialog. Closing a dialog or
observing an external application's exit does not remove its files. Startup and
reopening the settings dialog only discover retained records. They never launch
an application, start a watcher or send an upload automatically.

The service, launcher, export and recovery contracts are implemented together
with focused tests. The host/UI checkpoint connects them to the captured remote
file actions and the external-editing settings and retained-session dialog.

The publication contract is intentionally independent of streaming, rename and
transfer capability flags. Existing editor save methods perform useful conflict
checks but do not promise an atomic revision condition at the original-write
request. External editing must use the stronger contract below.

## Reviewed editor workflow

Configure an absolute installed executable path and an argument template. The
dialog uses the same literal-argument parser as command entry: separate arguments
with whitespace, quote an argument containing spaces as a JSON string, and use
`{file}` exactly once as an entire argument. The generated working filename is
safe and keeps a short alphanumeric extension where possible. The remote name,
original path and account remain visible in the review and recovery record.

For example, the template `--wait {file}` produces two arguments; the full local
working-file path is one argument. Quotes, spaces, Unicode and metacharacters in
other literal arguments stay data. There is no shell expansion, shell command
string, current-directory program lookup or implicit executable fallback.
Saving or loading an operating-system-specific preference does not run it.

The launch review displays the resolved executable, literal argument list,
working directory and captured original. It offers separate, initially
unchecked consent to upload watched saves when the captured source supports
conditional publication. Opening a local working copy does not by itself enable
automatic original writes.

Immediately before launch, the service rechecks the reviewed executable's
resolved path, type, executable mode and available size/timestamp identity;
existing access to its original and resolved paths; the exact local file hash
and size; the private working directory; and the captured review lifetime. A
changed form, closed review, changed initial source, changed executable, changed
working file or revoked access prevents launch. The immutable review is
single-use. The OS API does not provide an atomic open-and-execute handle, so
these checks are not presented as an executable sandbox or a complete defense
against a hostile same-user race.

Launch intent is flushed before starting the process. The session holds its
lease until the detached start acknowledgement settles. Explicit deletion is
refused while that start is pending. Application disposal waits for the
acknowledgement and retains the directory. Neither a launcher process exiting
nor an editor window appearing proves that the file is no longer in use.

## Watched generations and conflict review

A directory watcher observes writes and atomic-rename saves. A periodic content
inspection provides a fallback for missed platform events. Normal save bursts
are debounced for 700 ms; the fallback interval is three seconds. Each changed
content hash becomes a numbered local generation. Upload uses a separately
named immutable snapshot, and only one publication operation can run per
session.

Before the commit request, the service verifies that the working file still
matches the snapshot, checks watch-generation events, flushes the generation's
publication intent, and checks the working content again. A newer local save
before commit prevents that stale generation from being published. If a save
arrives after commit has begun, the in-flight revision may finish; the newer
generation remains pending and is serialized after its acknowledgement. A
completed older upload can never mark newer local contents as saved.

Provider failures, disconnected sources, unknown completion, conflicts and
oversized edited files disable automatic upload. Local saves continue to be
retained. Only ordinary local-save races are coalesced for another automatic
attempt. The user can pause watching, inspect retained work, export a copy, or
explicitly reconcile/retry the captured original.

A changed remote revision requires a new review that shows the current remote
identity/revision/hash and the local generation/hash. Confirming replacement
authorizes only that reviewed remote revision with those reviewed local bytes.
Both are revalidated at publication. Cancelling review changes no remote data;
editing again or another remote revision change invalidates the approval. A
different file ID, path or immutable account can never be approved as the old
original through this review.

## Retention, restart recovery and export

Retained directories live in per-user application data. They use the shared
[private tool staging lifetime](private-tool-staging.md), a native session lease,
bounded checksummed manifests, flushed files and explicit cleanup. POSIX stages
use owner-only directory/file permissions. Windows stages inherit the user's
application-data ACL; Windows ACL and detached-editor acceptance remain native
release checks.

The manifest stores the hashed storage reference, original path and file ID,
provider revision/account/content evidence, local generation counters, relative
working/snapshot names, SHA-256 content identities, phase and bounded failure
codes. It stores no access/refresh tokens, passwords, connection configuration,
provider upload-session IDs or executable launch command.

After a restart, the retained local file may contain edits made while the app
was closed. Recovery inspects that actual content rather than trusting a prior
generation hash. Reopening a retained local copy or exporting it does not need
remote access. Re-enabling original upload requires an explicit reconnect to the
same captured storage route and path, plus the provider's immutable account and
file ID. A matching email address alone is insufficient. Reconnect leaves
watching and automatic-upload consent off.

For an uncertain commit, recovery compares the exact original's current native
content hash and size with the durable attempted generation. A matching result
can be acknowledged without uploading the bytes again. An unchanged expected
revision permits an explicit later retry. Any other same-object revision needs
conflict review; another object/account/path is refused. A corrupted or
unreadable manifest never supplies launch or upload authority. Its private
directory remains visible for manual recovery and explicit cleanup.

**Export copy** streams the verified retained content through the existing
staged local-write contract to exactly the destination confirmed by the save
dialog. It does not append an extension or substitute another path. A changed
source during selection/read prevents replacement of an existing destination.
Cancelling export preserves all retained work. Successful export is an
independent local copy and never advances the saved-original generation.

Explicit cleanup requires confirmation that every external editor using the
session has been closed. It removes only that owned private directory, after
pending publication or launch work has settled. Closing the dialog, pausing,
failed launch, network error and application shutdown all retain the files.
If explicit deletion fails, any surviving directory is reopened as a fresh,
unbound session so a failed handle cannot conceal retained edits. Shutdown waits
for all session closes even when one fails or a concurrent discard changes the
catalog. Quiet native directory watchers forward cancellation immediately.

## Conditional original publication

Dropbox is the initial supported publication provider. An operation captures one
access token, asks Dropbox for its immutable `account_id`, hashes that identity,
and pins it together with the exact path, file ID, revision, length and native
content hash. Email addresses are display/account-routing information; they do
not establish the durable identity of a Dropbox account.

The initial download addresses the exact revision (`rev:...`). Its response must
match the captured account, file ID, path, revision and size, and the completed
stream must match Dropbox's content hash. The read does not follow redirects.

Publication proceeds as follows:

1. Revalidate the exact original and account before creating an upload session.
2. Send the immutable local generation in sequential requests of at most 4 MiB.
   Verify the entire stream, including its final length and any late read error,
   before any commit request. Each append includes its own request content hash.
3. Revalidate the exact original again and flush the caller's durable pending
   generation and provider-content-hash evidence through `prepareCommit`.
4. Finish the session with an empty body, `mode: {".tag":"update", "update":rev}`,
   `strict_conflict: true`, `autorename: false`, and the empty-body content hash.
   Check the captured source immediately before this request.
5. Require the response to retain the original account, path and file ID, and to
   report the expected size and whole-file content hash plus a valid revision.

`strict_conflict` is essential: it rejects a mismatched revision even if the
original was deleted or the other file has identical contents. There is no
unconditional overwrite, conflicted-copy fallback, credential-switching retry,
path fallback, original deletion or rollback mutation.

Only the exact `path/conflict` finish error is classified as a definite conflict.
Lost acknowledgements, unexpected identity/hash responses, malformed errors,
unknown errors and `properties_error` remain uncertain. Some provider errors
can follow a successful content upload. A status code alone is therefore not
evidence that the original stayed unchanged. The caller must retain its pending
generation and reconcile the exact account/object/path/revision/content hash
before any later publication.

Uncommitted Dropbox upload sessions expire under the provider's lifetime policy.
Their opaque session IDs and access tokens are not written into local retained
records. Recovery uses the retained bytes and original evidence. It does not
depend on resuming that temporary server session.

## Scope and metadata

Each original and edited generation is limited to **64 MiB** for preparation and
conditional publication. Each external-edit kind admits at most **256 retained
sessions**; its manifest payload is limited to **64 KiB**. An external editor can
enlarge a working file or create sidecars, so these are not a total retained-disk
quota. Files above the upload limit remain retained and can be independently
exported through a bounded-memory stream.

Preparation and Dropbox operations have a two-minute whole-flow deadline checked
at I/O boundaries, so a source that continues dripping bytes cannot run
indefinitely. Individual remote metadata/content waits are bounded to 30 seconds.
A request already in progress can take that remaining request timeout to settle;
an unacknowledged commit remains uncertain. Input and response metadata are also
bounded. Unsupported or unavailable metadata fails closed. Export-only cloud
documents, symlinks, read-only shared-file metadata,
missing revisions, unknown immutable accounts and path/ID mismatches are refused
by this publication contract.

This is a native update of an existing Dropbox file, not a replacement made by
copying a temporary object's properties. The request does not set custom
property groups, sharing membership, tags, `client_modified`, or storage/security
properties. Dropbox manages native metadata and modification times. The verified
result covers file identity, revision, size and bytes; it does not claim to
independently audit every provider-managed property. Native acceptance should
include files with custom properties, shared membership and existing history.

Other providers currently have **no automatic original-publication capability**
through this interface. In particular, an S3 or Azure transfer conditional-copy
flag is not taken as proof of complete original-preserving publication. No S3 or
Azure adapter behavior was changed for this feature. Retained local editing and
export remain distinct from saving an original.

## Platforms, access and acceptance

| Environment | External editor model |
| --- | --- |
| Linux | Absolute executable or installed executable wrapper; literal argv; detached start |
| macOS desktop | Absolute executable inside an installed application or another executable; existing access only; no implicit application-bundle conversion |
| Windows desktop | Absolute `.exe`; literal argv; detached start |
| Web, Android, iOS, macOS App Store build | External application launch unavailable |

Known shell and inline-code interpreter names, Windows batch/command scripts,
PowerShell scripts, relative executable paths and ambiguous `{file}` substitution
are refused by the editor configuration model. Arbitrarily renamed executable
behavior cannot be inferred from a path: users still review and choose installed
software. External editors are not bundled or downloaded by this feature.

The original source is captured before the first asynchronous operation, using
the real remote source behind the row rather than a pane position. Existing
source/account availability and access grants remain attached to that origin.
The opening context is checked through the initial review. Once a reviewed
editor is running, ordinary navigation does not silently redirect its saves to
another pane or account. Reconnect is explicit, and launch cannot manufacture
additional original-file access.

The dialog owns its editor text input. Literal argument entry and its local
buttons do not remap document/editor/terminal shortcuts. Nine application
locales contain the new workflow and failure messages; the widget gate includes
narrow translated layouts and cancellation/review behavior.

Native acceptance remains required for real Dropbox revision/conflict and lost
connection behavior, provider-managed custom metadata, each target desktop's
external editors, atomic-save variants, Windows application-data ACL/lease
behavior, macOS existing grants, and keeping files after an editor detaches or
the application restarts. Unit/native-filesystem fixtures establish the stated
application contracts; they do not substitute for those platform/provider runs.

## Evidence and primary references

The provider fixture suite covers exact account/path/ID/revision capture,
revision downloads, bounded Unicode-safe literal requests, durable commit order,
late input failure, stale review cancellation, revision races, lost
acknowledgements and ambiguous finish errors. It does not replace acceptance
against a real Dropbox account or desktop external editor.

- [Dropbox API schema: write modes and commit information](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesWriteMode)
- [Dropbox API schema: strict conflict and commit fields](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesCommitInfo)
- [Dropbox API schema: finish errors, including properties errors](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesUploadSessionFinishError)
- [Get file metadata](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/get-metadata)
- [Finish an upload session](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/upload-session-finish)
- [Start an upload session and its retention limit](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/upload-session-start)
- [Dropbox content hash algorithm](https://www.dropbox.com/developers/reference/content-hash)
- [Dropbox account information](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/users/get-current-account)

Relevant implementation: `conditional_file_publication.dart`,
`dropbox_file_publication.dart`, `external_remote_editing_service.dart`,
`external_editor_service.dart`, `external_edit_copy_export.dart`, and
`private_tool_staging.dart`. Focused gates are:

```text
test/dropbox_file_publication_test.dart
test/external_remote_editing_service_test.dart
test/external_editor_service_test.dart
test/external_edit_copy_export_test.dart
test/external_editing_lifecycle_test.dart
test/private_tool_staging_test.dart
test/widget/external_editing_dialog_test.dart
test/widget/external_editing_context_test.dart
```
