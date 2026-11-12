# Writable archive endpoints

Archive edits need two distinct outcomes: an editable draft and a verified
container published at its captured original path. A staged member write is
never a published transfer and never authorizes deleting a move source.

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

## Verification

The independent filesystem in `test/support/archive_endpoint_backend.dart`
models exact moves, captured revisions, private modes and faults before or
after physical mutations. `test/archive_container_publisher_test.dart` covers
durable intent order, acknowledgement loss, cancellation, restoration, restart
reconciliation, concurrent writers, changed recovery revisions, access-policy
changes, bounded cleanup, and unsupported capabilities. It also exercises real
native files, permission preservation and native lease exclusion.

Focused foundation gate:

```sh
flutter test test/archive_container_publisher_test.dart
```

No dependency was added. Transaction and publication code is project-owned.
