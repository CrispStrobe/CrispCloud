# Archives and containers

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G18

### Writable archive endpoints

**Status:** Partially implemented: native local workflow delivered; remote/browser publication implementation and native acceptance remain. **Dependencies:** Existing archive workspace and verified publication journal.

**Scope:** Expose reviewed archive mutations as captured operation endpoints with verified container publication.

**Implementation:** Introduce captured archive-member backends and transaction plans over the existing archive workspace. Bind container source/version, member identity, passwords and staged changes until verified whole-container publication.

**Delivered native increment:** Ordinary captured selections can be copied or
moved into the other pane's current archive directory through F5, paste and
context-menu actions. A private copy overlay is verified and presented as a
whole-container review. Only a verified physical publication receipt completes
the import; a move then attempts exact, revalidated source-file removal and
reports retained files/directories. Cancellation preserves cut references.
Existing add/edit/rename/remove actions and new empty-directory creation share
the same reviewed publisher. Nested routes retain independent passwords and
container generations. Tools and overflow expose account-scoped recovery even
when the original archive name is temporarily absent.

ZIP, 7z, TAR and TAR.GZ/TGZ have separate writer/protection policies. Existing
supported member times and permission bits are verified after repacking, and
unsupported protection or timestamp policies are refused. The
[endpoint specification](../archive-endpoints.md) records byte, entry, path,
nesting, time, metadata and encryption boundaries.

**Boundary:** Capabilities are format-specific. Mutating one member may require repacking the container; declare cost and read/write/encryption support. Keep original containers recoverable until replacement is verified.

**Acceptance:**

- Add/edit/rename/delete/create-folder operations preserve unrelated members, supported metadata and original encryption policy.
- Concurrent container changes, collisions, symlinks/traversal, corrupt members and failed publication preserve the original.
- Local and supported remote targets maintain exact source identity, cancellation and interruption recovery.

**Starting points:** archive_workspace.dart; archive_viewer_service.dart; operation backend/capabilities.

**Remaining implementation:** No remote backend currently supplies the
required original access-policy contract. Browser publication also needs an
operation-lifetime lease. Generic upload/move capabilities do not enable either
path. Native publication uses two exclusive moves with a temporary original-name
absence window. Durable packing drafts remain G21; directory synchronization
and direct archive-to-archive transfers remain G19/G20. Native release acceptance
continues under G50. The implementation and its observed gates are preserved in
[draft PR 81](https://github.com/CrispStrobe/CrispCloud/pull/81) and the
[continuation record](continuation-tools-archives-20261112.md).

## G19

### Directory-to-archive synchronization

**Status:** Scoped. **Dependencies:** G18.

**Scope:** Compare and synchronize a directory and a writable archive using reviewed plans.

**Implementation:** Adapt directory comparison/sync planning to G18 endpoints. Display archive members as candidates with explicit creation, update and deletion actions; support one-way first and two-way only with reliable baseline state.

**Boundary:** Compare content and logical paths, not packed-byte equality. Password handling, filename normalization and metadata loss must be explicit. A ZIP endpoint is only writable when its capability contract is proven.

**Acceptance:**

- Directory/archive comparisons distinguish equal, new, changed and deleted members, including nested folders and empty entries.
- Review cancellation and container/source replacement cannot commit a stale plan.
- Verified sync output reopens and matches the selected plan; two-way conflict/deletion semantics have independent fixtures before being enabled.

**Starting points:** Directory comparison/sync engine; G18 archive endpoints.

## G20

### Archive-to-archive transfer

**Status:** Scoped. **Dependencies:** G18.

**Scope:** Copy or move members between captured archives with commit-before-delete ordering.

**Implementation:** Connect two captured archive endpoints to the transfer planner. Stage and verify destination member changes before a move may delete source members, and preserve independent passwords and container versions.

**Boundary:** Do not treat two members in the same container as unrelated writes. Group transactions per container, reject unsupported cross-format metadata/encryption changes and report partial publication honestly.

**Acceptance:**

- Copies and moves between supported formats preserve content, hierarchy and expected protection.
- Same-container overlap, collisions, source/destination replacement and failures between commits cannot delete the only good copy.
- Large/remote members obey limits and cancellation; recovery identifies each original container and member.

**Starting points:** G18; FileOperationService transfer/recovery planning.

## G21

### Large background archive jobs

**Status:** Scoped. **Dependencies:** G18; transfer queue.

**Scope:** Add worker/streaming packing, durable recovery and bounded validation.

**Implementation:** Move packing and verification into a cancellable worker or bounded streaming spool with durable job metadata. Extend the operation queue to report scan/read/pack/verify/commit phases and recover conservatively after interruption.

**Boundary:** Increasing size limits alone is insufficient. Passwords stay outside ordinary job records. A stopped job must not be reported complete or replace a valid container with partial output.

**Acceptance:**

- Measured large fixtures demonstrate bounded memory, responsive UI and accurate progress throughout verification.
- Stop/restart, disk exhaustion, provider failure and process interruption preserve original files and expose recoverable staging.
- Every advertised format reopens with independently verified member hashes and supported encryption/metadata.

**Starting points:** archive_creation_service.dart; archive_workspace.dart; transfer queue and worker infrastructure.

## G22

### Archive format coverage

**Status:** Partially implemented: shared reader/writer routing, additional archive writers and streamed data-image creation delivered; uncommon codecs, existing disk filesystem rewrites and signed package builders remain. **Dependencies:** License and format review per codec.

**Scope:** Add each missing reader/writer/alias independently with a tested capability matrix.

**Implementation:** Maintain a format-by-operation matrix and add dispatch, readers, writers and aliases independently. Prioritize compatible ZIP aliases, then package/container readers and additional compression streams before uncommon writers.

**Boundary:** Scope includes ARJ/LZH/CAB/ACE/UC2; RPM/CPIO/DEB; ISO/XAR/XIP; ZIP-derived aliases and ZIPX methods; raw LZMA and legacy compressed TAR aliases. A recognized extension does not establish decoding, signature verification or editing support.

**Acceptance:**

- Each enabled format has independent valid, truncated, malformed, traversal and resource-expansion fixtures.
- Advertised read/extract/create/modify/encryption/compression capabilities match actual codec support on each target.
- Record exact dependency versions, permissive licenses and provenance before enabling a codec; signed containers retain explicit verification limits.

**Delivered reader increment (2026-11-12):** Shared registry across panes, F3,
search and extraction; ISO9660/Joliet/Rock Ridge, unencrypted supported UDIF DMG
partitions with HFS+/HFSX/ISO file views, ordinary/GNU/BSD AR and DEB, CPIO
newc/CRC, XAR/PKG/XIP container members, CRX2/3 and compatible ZIP aliases.
Compressed streams now request strict integrity checks. Independent GNU
ar/libarchive and native HFS+/UDIF fixtures supplement malformed, traversal,
range, ownership and resource-bound tests. The [capability matrix](../archive-format-coverage.md)
records per-format limits and signature/metadata boundaries. G18 publication rules are unchanged. UDF/APFS, CAB/RPM,
ARJ/LZH/ACE/UC2, raw LZMA, PBZX and additional ZIPX methods remain.

**Delivered writer increment (2026-11-12):** Comic and eligible unsigned Java
aliases, KMZ, additional compressed TAR and single-file streams, inspected
AR/CPIO/XAR and data ISO rewrites, and a narrow prebuilt DEB payload workflow.
Fresh ISO/HFSX/UDIF creation uses streamed private output, complete readback
verification and verified destination staging; native disk images can exceed
64 MiB members up to the 2 GiB output bound. Existing HFS/DMG images, signed
packages and static-library indexes remain read-only. The creator does not
provide durable background job restart or larger existing-container editing,
so G21 remains scoped. Remote/browser creation UI (G23) remains scoped.

**Starting points:** archive_viewer_service.dart; archive_workspace.dart; archive_creation_service.dart; codec capability registry.

## G23

### Remote and browser archive creation

**Status:** Scoped. **Dependencies:** G18; G21 where streaming is required.

**Scope:** Extend creation to supported captured remote and browser destinations.

**Implementation:** Expose creation through captured supported remote backends and browser grants, using verified staging/commit semantics and the same format/security options. Support streamed/spooled input as G21 becomes available.

**Boundary:** Browser download handoff is distinct from writing a granted destination. Provider lack of exclusive or atomic publication must be visible and handled conservatively. Do not use current pane/account after review.

**Acceptance:**

- Local-to-remote, remote-to-local, remote-to-remote and supported browser-grant fixtures preserve source/destination identity.
- Cancellation, quota errors, collisions, reconnects and revocation cannot publish corrupt archives or overwrite unreviewed objects.
- Created archives reopen through the normal viewer; unsupported platforms and limits are shown before expensive work.

**Starting points:** G18/G21; archive_creation_service.dart; LocalFileSaveReporter and remote backends.

## G24

### External packer adapters

**Status:** Scoped. **Dependencies:** G17 extension isolation.

**Scope:** Add reviewed external packer commands with advertised read/write/encryption capabilities.

**Implementation:** Add a manifest-driven adapter for approved external packer commands, capabilities and parameter templates. Run tools in controlled staging with explicit user review, bounded output and verified container results.

**Boundary:** Never infer support from an executable name. Keep package licensing separate from user-configured external tools. Passwords must not leak in logs, ordinary persisted arguments or process listings where avoidable.

**Acceptance:**

- Read/create/modify/encryption claims are checked with independent format fixtures and failed-tool cases.
- Paths and member names are passed safely; tool output cannot escape staging or replace unrelated files.
- Cancellation, child-process cleanup, output limits and container verification complete before publication.

**Starting points:** G17; existing extension/custom-command service; archive endpoints.
