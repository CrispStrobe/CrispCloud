# Writable archive endpoints

Archive edits need two distinct outcomes: an editable draft and a verified
container published at its captured original path. A staged member write is
never a published transfer and never authorizes deleting a move source.

## Endpoint workflow

`ArchiveEndpoint` owns a captured `ArchiveWorkspace`, its container authority,
and one import transaction. An ordinary source selection is planned by the
existing copy planner into a private archive overlay. The internal operation
is always **copy**, even when the requested final operation is move. The
writable overlay is never exposed as a general transfer destination.

The public sequence is `prepareImport`, `stageImport`, a concrete
`ArchiveWorkspaceReview`, then `commit`. Staging independently verifies every
copied member against a fresh source snapshot and full SHA-256, reads declared
source permission bits, and adopts the entire successful import in one draft
mutation. A failed or cancelled copy does not adopt a partial overlay. The
import refuses setuid/setgid source files because source ownership is not
captured. Existing privileged records can be retained only by a format profile
that preserves their ownership and original privilege bits. Review repacks and
independently decodes the archive, compares member bytes, types, modification
times and permission bits, then revalidates the format/protection profile. It
lists add/replace/rename/remove/directory
changes. Changing the draft or a parent generation invalidates that review.

The dialog supports explicit keep-both, replace and skip policies. Its result
is `ArchiveEndpointTransferResult` only after an outer physical publication
receipt exists. Closing a staged review returns no successful transfer result.
Existing workspace Save uses the same review/publisher path. Existing editing,
renaming and member removal remain staged; creating an empty directory is also
available. Adding from the other pane uses the private verified copy path.

Nested routes retain separate original passwords and captured generations for
each level. Updating an inner archive stages its bytes in its parent; only the
outermost physical publication completes the transaction. A failed outer
publication retains the verified nested draft for an explicit retry. Passwords
are not persisted in the publication journal.

The import UI entry point is
`showArchiveEndpointImportDialog(context, source: ..., files: ...,
containerBackend: ..., containerFile: ..., nestedMembers: ..., directory: ...,
expectedOuterFingerprint: ..., moveSources: ..., journal: ...)`.
General pane/clipboard routing captures account, navigation, listing and local
grant authority before awaiting the dialog. Ordinary import remains separate
from the explicit archive-source transaction described below. Mixed-account
ordinary selections are outside one import transaction's scope.

## Reviewed archive-to-archive copy

`prepareArchiveCopy(source: ArchiveWorkspace, files: ..., directory: ...,
conflict: ...)` captures a clean source and every enclosing workspace revision,
physical storage identity and outer SHA-256. It uses the same verified overlay,
review and destination publication machinery, with no source mutation/deletion.
The UI captures both pane routes/selections before awaiting independent nested
password prompts. Pane F5/context Copy and a clean workspace's Copy out action
enter this workflow. F6/Move out explicitly refuse an archive destination.

Supported regular-member content, hierarchy, empty directories, modification
times and permission bits are imported. Protection follows the destination.
Ownership, ACLs, resource forks and signatures are not copied; setuid/setgid
inputs are refused. Same physical outer containers are rejected, including
separate nested routes and native hard-link aliases under both captured grants.
Source and destination workspaces retain 64 MiB per-member and 256 MiB
aggregate/container bounds; the larger spooled browsing path does not raise them.

The source's authority, captured revisions, physical identity and complete outer
bytes are rechecked before staging and after destination staging. The latter
check occurs immediately before the publisher's final candidate/backup checks
and exclusive installation, so the potentially long source hash does not weaken
destination verification. A late failure restores a vacant original and retains
the existing reviewable recovery evidence. Source guards/passwords are transient;
explicitly reviewed destination recovery operates on its verified candidate and
never deletes the source. This is a one-destination copy transaction, not an
atomic two-container move. Source changes after the final observation cannot be
made atomic across independent storage; copied member bytes remain the captured,
verified snapshot.

## Format and member policy

The filename and detected format must agree. Writer eligibility is narrower
than reader recognition; an unsupported writer never silently converts the
container or falls back to a direct provider upload.

| Container | Writable policy | Imported modification time | Important boundary |
| --- | --- | --- | --- |
| ZIP | Plain or the supported AES-256 policy | UTC whole seconds in the supported signed timestamp range; otherwise DOS wall-time fields at two-second resolution | Mixed protected/plain files, legacy or other AES strengths, and encrypted directory entries are refused. |
| 7z | Plain or original AES password, retaining original header visibility | Millisecond resolution | Header encryption is detected independently of file data, including containers with no ordinary files. |
| TAR / CBT | Inspected regular-file profiles | Whole seconds for imports | Known ownership and PAX metadata are retained; unsupported extensions, links and special entries are refused. |
| Compressed TAR | Supported TAR inside gzip/bzip2/XZ/Zstandard/LZ4/LZMA | Whole seconds for imports | Decoded TAR is limited to 64 MiB, including headers. Wrapper/profile inspection precedes writes. |
| CBZ / CB7 / unsigned JAR/WAR/EAR / KMZ | Corresponding ZIP/7z policy | Corresponding underlying format | Java signatures/digests block editing; KMZ needs a top-level KML; original member order is retained. |
| gzip / bzip2 / XZ / Zstandard / LZ4 / LZMA | Exactly one immediate ordinary payload | Not applicable | Replace its bytes; name/count/permissions cannot be changed. Recursive inner-container views cannot be flattened, including same-codec nested streams. |
| AR / CPIO / XAR | Inspected regular-file profiles | Whole seconds for imports | Known ownership, package metadata and integrity/compression policies are retained. Unknown fields and unsupported structures remain read-only. |
| DEB / UDEB | Coordinated prebuilt control/data payload replacement | Whole seconds for outer members | Exact three-member wrapper; required control fields and present md5sums checked. In-app nested payload editing is disabled. |
| ISO | Inspected data-only ISO 9660/Rock Ridge/Joliet | Whole seconds for imports | Known volume/member metadata retained. Boot/hybrid/UDF/unknown structures block rewriting. |
| Lzip / UNIX compress | Browsing and extraction only | Not applicable | Includes TAR.LZ, TAR.Z and TAZ. Reader support does not grant a writer or authorize conversion to another wrapper. |
| Existing HFS / DMG and other packages | Browsing and extraction only | Not applicable | Separate fresh HFSX/DMG creation does not grant existing filesystem rewrite access. |

LZ4 editing requires one complete data frame without skippable extension
metadata. Accepted linked or independent frames are rewritten as independent
256 KiB blocks with block and content checksums; original block sizes and
optional checksum flags are not retained. Frame collections remain read-only.
LZMA editing requires one strictly decoded stream with exact input consumption,
supported properties and dictionary distances. Known-size streams may have an
end marker; unknown-size streams must have one. Rewrites use a known size, no
end marker, `lc=3, lp=0, pb=2`, and the default 8 MiB dictionary. These changes
preserve the decoded content rather than the original encoder parameters.
LZMA-alone has no stored content checksum. Both wrappers keep their 64 MiB
compressed/decoded limits, including TAR headers, and a recursively opened
inner container is not eligible for a single-payload rewrite.

A bounded ZIP metadata finalizer writes explicit UTC-second fields to both
local and central headers while copying compressed/encrypted payloads unchanged.
It rebuilds every local offset and ordinary/ZIP64 footer, including the
65,535-entry transition. UTC fields are emitted only from 1970 through
2038-01-19 03:14:07 UTC. Outside that range, only already representable DOS
wall-time fields can be kept; DOS fields have two-second resolution and no time
zone, so that fallback does not promise an exact UTC instant in another time
zone. An existing timestamp that cannot be preserved is refused rather than
rounded during rewrite. ZIPs with signed-negative extended UTC timestamps are
read-only with the pinned reader: it interprets the high bit as an unsigned
future date. The capability policy checks bounded local/central timestamp
extras and refuses that input, malformed timestamp fields, and inconsistent
local/central declared modification times before any edit is allowed.
Local headers must have distinct, nonoverlapping metadata regions and matching
local/central names. The policy bounds aggregate local metadata scanning to the
input byte length, preventing central records from repeatedly scanning shared
extra fields. ZIP encryption markers are classified consistently with the
reader; inconsistent flags, methods or AES descriptors refuse editing.

Supported existing modification times and POSIX permission bits are compared
after repacking; inability to preserve them refuses publication. Imported times
are normalized to the chosen format's supported precision. Empty directories
are retained. Merging an existing explicit archive directory preserves its
original mode and modification time; new directories import supported metadata.
The legacy ZIP/7z member model does not promise arbitrary comments, ownership,
ACLs or opaque extras. Format-specific TAR/AR/CPIO/XAR/ISO inspectors separately
capture supported metadata and refuse structures their writers cannot preserve.
This member policy is separate from the stricter outer-container access policy
below. See the complete [format matrix](archive-format-coverage.md) for each
creation/editing boundary.

The original password must successfully decode and authenticate every original
protected file before editing, within the decoded-content limits. Replacing or
removing a later member cannot bypass its password or authentication check. A supplied
password on an empty container whose protection cannot be established does not
authorize an unencrypted rewrite. Removing all protected file data is refused
when it would erase a data-only encryption policy. The writer never silently
enables or disables 7z header protection.

Paths are validated before they become members: no traversal, absolute paths,
links or special entries, duplicate paths, or file/directory collisions.
Limits are 200,000 explicit entries, 200 path components, 4,096 UTF-8 bytes per
member path and 8 MiB of member names. Each decoded member is limited to
64 MiB; total decoded content and packed output are each limited to 256 MiB.
Nested routes are limited to eight levels. An import has a ten-minute overall
staging deadline and 30-second source-call/read inactivity limits. Digest
streams also have a five-minute whole-read bound and cancel their source
subscription when cancelled or timed out.

## Move source disposition

After the receipt is durable, each copied source is checked again against its
captured identity, every recognized revision field (including `versionId`),
length and full content hash. The published receipt and member bytes must still
match. Native file identity evidence (path, regular-file type, size, modification
and change times, and mode) is captured during preview, checked around staging,
and required again after publication. It remains private to this transaction.
Native files use an exact, nonrecursive unlink after bounded re-reading and
final no-follow parent/file snapshots; the receipt is reverified immediately
before those final checks. Remote file removal requires a nonempty captured
string revision and a provider conditional-delete capability. Empty, whitespace-only
or malformed recognized revision values are refused, including an earlier
field that would shadow a valid later field. There is no unguarded
source-delete fallback. Preview, staging and cleanup snapshots copy provider
metadata into immutable maps, so later provider reads cannot rewrite the
captured revision evidence in place.

Source directories are retained in this increment. The shared empty-directory
API accepts a path without an expected object identity, so it cannot authorize
removing a directory that may have been replaced after inspection. A directory
move can therefore publish its contents and remove verified source files while
reporting remaining directory paths explicitly.

A changed source, cancellation, unsupported exact removal, timeout or missing
acknowledgement produces a published copy with a partial move result. It never
claims rollback of the published archive. Cleanup has a ten-minute overall
budget and 30-second acknowledgement limits; timeout revokes that cleanup
attempt's authority. Retained/unconfirmed source paths are returned separately
from the bounded detailed warning list. Sources are never deleted during
packing, virtual member staging or restart recovery. A restart recovery record
contains no source-deletion authority.

## Container publication foundation

`ArchiveContainerPublisher` publishes an already verified, bounded candidate
through the captured `FileOperationBackend`. Its durable
`ArchivePublicationJournal` records the original account, exact container path,
original and candidate SHA-256 digests, candidate length, generated recovery
paths, access-policy digest, and acknowledged phase. It stores no passwords,
tokens, grants or archive member content.

The journal is bounded to 256 records and 4 MiB. It uses the existing
`FileCollectionStorage` atomic compare-and-swap contract. Native records are
flushed before replacement. Every intent must be acknowledged before its
following mutation; a write error is accepted only if the exact proposed
catalog can be read back. Otherwise mutation authority is revoked, including
automatic restoration. An earlier durable record retains the possible original,
candidate and backup locations for explicit recovery.

An OS-held lease spans each publication or recovery, including all physical
mutations. It excludes another owner across native processes/isolates and is
released when the owner exits. Expected-record comparison additionally rejects
a stale update within a shared journal instance. Catalog CAS alone would not
provide this operation ownership.

The publication sequence is:

1. Validate the original identity and whole-container digest. Persist the
   candidate and backup paths before creating recovery data.
2. Write a new candidate through verified private staging. Preserve and read
   back the outer file's declared access metadata before the candidate becomes
   visible at its sibling path. Record its verified identity and access-policy
   hash.
3. Revalidate the original bytes, identity and access policy. Record backup
   intent, then move the original to its generated backup path with exact
   no-replace semantics. Read and verify that backup.
4. Record installation intent. Revalidate the candidate, backup and vacant
   original name, then move the candidate into that name without replacement.
5. Read back the complete published container and its access policy. Persist
   the confirmed published snapshot before returning a publication receipt.
6. Record cleanup intent and remove only verified, unchanged recovery objects.
   Failure to confirm cleanup retains its record and reports `cleanupPending`.

These are **two exclusive moves, not atomic replacement**. There is an interval
when the original name is absent and the verified original is held at its
backup path. A concurrently created original name is never overwritten. An
ambiguous installation retains the backup and requires reconciliation; it is
not reported as a successful transfer or as a completed rollback.

## Publication and metadata boundaries

Native local publication requires the platform's exclusive rename primitive,
captured access scopes, a persistent installation identity, and the native
publication lease. Browser publication is unavailable until an equivalent
operation-lifetime lease is implemented.

A non-native backend must explicitly implement
`ArchivePublicationAccessPolicy`, in addition to advertising verified staging
and exact atomic no-replace moves. That contract must cover original sharing,
ACLs, inherited access and provider-specific properties throughout staging and
replacement. No current remote adapter opts in. A provider's generic move or
upload capability is insufficient, and there is no direct-write or unchecked
rename fallback.

Outer-container access metadata is separate from archive member metadata.
Native preservation covers the backend's declared permissions, ownership,
ACLs, extended attributes and Windows attributes, with bounded metadata reads
and verification. Changes to that policy refuse publication. A content edit
can change the outer file's object identity and modification time. Provider
sharing/custom properties are not inferred from member metadata or generic
filesystem permissions.

Native cleanup checks exact generated paths, ordinary parent directories,
regular files, full hashes and final file snapshots before synchronous exact
deletion. Reads stop at the captured length plus one byte; growth, truncation
or a changed snapshot refuses cleanup. No recursive deletion is used. Remote
cleanup requires conditional deletion with a captured revision; absent that
capability, the old backup and its durable reference remain intact. A confirmed
published record with pending cleanup does not authorize deleting a changed
backup. Retained records continue to count toward the recovery budget.

## Retry and restart

The publication journal is durable; an unpacked editable draft is not. This
distinction is intentional: durable packing jobs and reconstruction of partly
packed drafts remain a separate workflow.

After interruption, recovery must reconnect the exact original storage and
inspect all recorded paths. A fully written, durably verified candidate can
finish publication; a candidate already present at the original name can be
confirmed by its complete digest and access policy. Otherwise an intact
original backup can be restored only into a vacant original name. A candidate
that was not durably verified cannot be promoted merely because a file exists
at its path. The original must be retained/restored and the editable draft
recreated.

Changed, unavailable or symbolic recovery paths require review. Missing files
are reconciled only through successful backend inspection. A lost provider or
journal acknowledgement never grants permission to remove an original or to
replay a mutation against a replacement account.

The user-facing recovery entry point is
`showArchivePublicationRecoveryDialog(context, backend: capturedBackend,
journal: ..., containerPath: optionalExactPath)`. It lists only unfinished
records for the captured account and exposes verified finish/restore actions.
The publisher reacquires the lease and reloads the record before mutation.
An attempted recovery tells the host to refresh and capture a new container
before another edit; it does not silently reuse a stale file snapshot. Import
and workspace opening detect recorded interruptions even when the original
name is temporarily absent. Detailed UI messages are available in English,
German, French, Spanish, Portuguese, Chinese, Japanese, Korean and Arabic.

## Verification

The independent filesystem in `test/support/archive_endpoint_backend.dart`
models exact moves, captured revisions, private modes and faults before or
after physical mutations. `test/archive_container_publisher_test.dart` covers
durable intent order, acknowledgement loss, cancellation, restoration, restart
reconciliation, concurrent writers, changed recovery revisions, access-policy
changes, bounded cleanup, and unsupported capabilities. It also exercises real
native files, permission preservation and native lease exclusion.

The endpoint and dialog suites cover private staging, collision policies,
copy/commit ordering, content and revision-only source mutations, native exact
source cleanup, source-directory retention, cancellation, stalled/dripping
reads, post-publication cleanup timeouts, review invalidation, nested passwords,
original-member authentication, invalid/mutated revision evidence, protection
policy boundaries, and explicit restart recovery UI. The malformed-policy
suite constructs shared and overlapping ZIP local metadata and inconsistent
AES/strong-encryption markers; each case must refuse edits and retain the
original container.

Focused gate:

```sh
flutter test test/archive_container_publisher_test.dart \
  test/archive_workspace_test.dart test/archive_endpoint_test.dart \
  test/archive_endpoint_dialog_test.dart test/archive_viewer_integration_test.dart \
  test/archive_browser_session_test.dart test/archive_zip_metadata_test.dart \
  test/archive_endpoint_policy_malformed_test.dart
```

Transaction and publication code is project-owned and adds no dependency.

## Format references and licensing

ZIP record offsets and footer handling follow the primary
[ZIP format specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
The signed UTC timestamp boundary and local/central timestamp layout are also
cross-checked against the primary
[Apache Commons Compress timestamp implementation](https://commons.apache.org/proper/commons-compress/xref/org/apache/commons/compress/archivers/zip/X5455_ExtendedTimestamp.html).
No implementation code was copied from those references.

The ZIP AES policy scan follows the primary
[AES ZIP format specification](https://www.winzip.com/en/support/aes-encryption/):
it checks the AES method marker and bounded extra-field descriptors, including
the declared 256-bit strength. The independent reader remains responsible for
actual data authentication and decoding. The
[7z format description](https://www.7-zip.org/7z.html) documents its extensible
format and AES-256 encryption; support here remains limited by the pinned
reader/writer and the verification above.

The implementation reuses the existing `koni_archive` 0.9.0 and `archive`
dependencies. `koni_codecs` 0.9.0, already present transitively, is an
explicit direct dependency for LZMA/LZMA2 encoding. The strict LZMA-alone packet
driver uses `archive`'s public range-decoder primitives to verify the exact
stream boundary; it does not modify the dependency cache. The pinned codec
packages use the MIT license. No native runtime, subprocess packer or external binary is
added to the app. Publication, policy, transaction, lifetime and recovery code
is project-owned.

The archive-copy and compression continuation is recorded in
[PR #92](https://github.com/CrispStrobe/CrispCloud/pull/92), with its observed
gates and platform boundaries in the [verification record](archive-workflows-codecs-verification.md).
