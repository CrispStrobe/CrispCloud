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

**Native large-file continuation (2026-11-13):** Eligible unencrypted top-level
ZIP/CBZ, 7z/CB7, TAR/CBT and TGZ/TAR.GZ workspaces use private input/import/review
spools, streamed member hashes and exact streamed publication with an 8 GiB
member/container/expanded budget. The reader, writer and publisher retain
metadata, path, protection and source-authority checks. Buffered editors,
protected/nested profiles and directory-to-archive synchronization retain their
separate smaller bounds. The [parity report](../archive-parity-large-continuation.md)
records the independently measured codec results and blocked Flutter runtime
gate; native app acceptance is still open.

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
and broader archive transfer remain G19/G20; reviewed copy and native top-level
moves are delivered below. Native release acceptance
continues under G50. The implementation and its observed gates are preserved in
[draft PR 81](https://github.com/CrispStrobe/CrispCloud/pull/81) and the
[continuation record](continuation-tools-archives-20261112.md).

## G19

### Directory-to-archive synchronization

**Status:** Partially implemented: reviewed native one-way folder-to-archive synchronization; two-way baselines, nested destinations and remote/browser publication remain. **Dependencies:** G18.

**Scope:** Compare and synchronize a directory and a writable archive using reviewed plans.

**Implementation:** Adapt directory comparison/sync planning to G18 endpoints. Display archive members as candidates with explicit creation, update and deletion actions; support one-way first and two-way only with reliable baseline state.

**Boundary:** Compare content and logical paths, not packed-byte equality. Password handling, filename normalization and metadata loss must be explicit. A ZIP endpoint is only writable when its capability contract is proven.

**Acceptance:**

- Directory/archive comparisons distinguish equal, new, changed and deleted members, including nested folders and empty entries.
- Review cancellation and container/source replacement cannot commit a stale plan.
- Verified sync output reopens and matches the selected plan; two-way conflict/deletion semantics have independent fixtures before being enabled.

**Starting points:** Directory comparison/sync engine; G18 archive endpoints.

**Delivered native one-way increment (2026-11-12):** With a native folder in
one pane and an eligible top-level archive directory in the other, **Compare
directories** captures both locations and compares logical paths and complete
file SHA-256 values. Equal, new, changed, archive-only and type-conflict rows are
explicit. Selected updates form one private atomic draft. Removal requires a
separate opt-in plus selected archive-only rows; a directory cannot silently
remove unchecked children. Empty entries are included, destination protection
is retained, and the complete candidate is decoded and reviewed before saving.
The source folder is never mutated.

The complete source namespace, captured native metadata and contents are rechecked before
staging and publication, including unselected/equal entries. Version-3 journal
records retain this dependency across restart and backup cleanup. Changed source
evidence blocks finishing and preserves verified restoration when available;
ordinary workspace Save cannot bypass the synchronization owner. Existing
64 MiB/member and 256 MiB source/container limits remain. See the
[endpoint contract](../archive-endpoints.md) and
[verification record](../archive-sync-large-tar-verification.md).

**Remaining:** Two-way baselines and deletion/conflict semantics, nested archive
destinations, remote/browser publication and native release acceptance. This
increment does not close all of G19.

## G20

### Archive-to-archive transfer

**Status:** Partially implemented: reviewed copy and native top-level two-container moves delivered; nested cross-container routes, remote/browser publication and full native acceptance remain. **Dependencies:** G18.

**Scope:** Copy or move members between captured archives with commit-before-delete ordering.

**Implementation:** Connect two captured archive endpoints to the transfer planner. Stage and verify destination member changes before a move may delete source members, and preserve independent passwords and container versions.

**Boundary:** Do not treat two members in the same container as unrelated writes. Group transactions per container, reject unsupported cross-format metadata/encryption changes and report partial publication honestly.

**Acceptance:**

- Copies and moves between supported formats preserve content, hierarchy and expected protection.
- Same-container overlap, collisions, source/destination replacement and failures between commits cannot delete the only good copy.
- Large/remote members obey limits and cancellation; recovery identifies each original container and member.

**Delivered copy increment (2026-11-12):** Captured clean source/destination
workspaces, independent nested passwords, recursive and empty-directory copy,
supported time/mode preservation, keep-both/replace/skip, private staged
verification and existing physical publication. Source fingerprints are checked
before staging and before final destination verification/installation. Same
outer containers and native hard-link aliases are refused. Pane F5/context Copy
and clean workspace Copy out are connected. At that checkpoint F6/Move out were
refused for archive targets; the later native move continuation below enables
its narrower scope. Copy source bytes are never written or deleted. A changed source
or late failure retains/restores the original destination through the existing
journal. Bounds remain 64 MiB/member and 256 MiB/container/aggregate.

The 2026-11-13 continuation replaces those bounds for eligible native streamed
common-format workspaces with their individual 8 GiB budgets. Imports use sealed
private spools; transfer checks and source-removal hashes consume bounded
streams. A streamed pair's combined candidate budget is the sum of its two
workspace limits, while each archive retains its own limit. Two buffered
workspaces retain the earlier 256 MiB combined budget. The new integration
tests are authored and statically checked; the Flutter runtime gate remains.

**Delivered same-workspace continuation (2026-11-12):** **Move within archive…**
preflights a selected group, supports recursive/implicit/empty directories and
stages one metadata-preserving rename group. Stop, keep-both and skip policies
retain existing destination trees. Captured revisions, self/descendant refusal,
path bounds and the existing whole-container review/publication protect the
original. This is one workspace, including an eligible nested route; it does
not coordinate separately opened aliases or different nested routes.

**Delivered native move continuation (2026-11-12):** F6/Move and clean workspace
Move out prepare and verify both complete archive candidates, then publish the
destination before source removal. A privately guarded source draft cannot be
saved without its coordinator and verified destination dependency. Version-2
source-publication records retain that dependency across restart; older apps
refuse the record. Source installation, lost-acknowledgement confirmation and
backup deletion recheck the exact destination. Explicit recovery can restore a
verified source backup after retaining its installed removal candidate. Results
distinguish completed members, skipped paths, destination-only publication and
unconfirmed source state requiring recovery. Original source permissions and
content are rechecked between publications. Both paths appear in recovery UI.

**Remaining:** Nested cross-container moves, grouped operations across separately
opened inner routes, backend-specific remote/browser publication and native
release acceptance. These publications are ordered, not atomic across two files;
external changes after final observations remain an explicit boundary. This
increment does not close the broader G20 scope.

**Starting points:** G18; FileOperationService transfer/recovery planning.

## G21

### Large background archive jobs

**Status:** Partially implemented: native foreground ZIP/7z/TGZ creation and common-format editing now stream, alongside TAR/CBT and data-image creation; durable queued packing, restart and app runtime qualification remain. **Dependencies:** G18; transfer queue.

**Scope:** Add worker/streaming packing, durable recovery and bounded validation.

**Implementation:** Move packing and verification into a cancellable worker or bounded streaming spool with durable job metadata. Extend the operation queue to report scan/read/pack/verify/commit phases and recover conservatively after interruption.

**Boundary:** Increasing size limits alone is insufficient. Passwords stay outside ordinary job records. A stopped job must not be reported complete or replace a valid container with partial output.

**Acceptance:**

- Measured large fixtures demonstrate bounded memory, responsive UI and accurate progress throughout verification.
- Stop/restart, disk exhaustion, provider failure and process interruption preserve original files and expose recoverable staging.
- Every advertised format reopens with independently verified member hashes and supported encryption/metadata.

**Starting points:** archive_creation_service.dart; archive_workspace.dart; transfer queue and worker infrastructure.

**Delivered streaming foundation (2026-11-12):** Fresh native plain TAR/CBT
creation uses bounded source/output chunks, a private output spool, complete
streamed member verification and verified no-overwrite destination staging up
to 2 GiB including format overhead. Real fixtures exceed both the former
64 MiB member and 256 MiB aggregate limits. Byte progress, event-loop yields,
cancellation, source revalidation, late collision and cleanup have dedicated
tests; independent readers check content and supported metadata. Native
ISO/HFSX/DMG already have their separate streamed creation profiles. Ordinary
buffered/compressed formats and existing archive edits retain their bounds.

**Native common-format continuation (2026-11-13):** ZIP/ZIP64, 7z Copy/LZMA2
and TGZ creation use an 8 GiB native budget; existing common-format workspaces
stream snapshots, imports, repacking and publication. Each requested format has
passed complete >2 GiB member codec checks and independent decoding. ZIP64 also
passed a >4 GiB member and 65,536-entry case. Codec processes yielded to the
event loop; this is not a Flutter UI responsiveness measurement. Receipts are
linked from the [parity report](../archive-parity-large-continuation.md).

**Remaining:** Durable queue/job records, worker lifecycle, stop/restart and
process-interruption recovery for packing, large protected/nested profiles,
and provider/platform acceptance. Automatic approval review blocked the local
Flutter runner, so authored application integration tests are not runtime
passes. Foreground streaming does not close the durable background-job scope.

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
records per-format limits and signature/metadata boundaries. G18 publication rules are unchanged. The package continuation below adds CAB/RPM/PBZX and portable CPIO;
UDF/APFS, ARJ/LZH/ACE/UC2 and additional ZIPX methods remain; bounded raw LZMA is delivered in the continuation below.

**Delivered writer increment (2026-11-12):** Comic and eligible unsigned Java
aliases, KMZ, additional compressed TAR and single-file streams, inspected
AR/CPIO/XAR and data ISO rewrites, and a narrow prebuilt DEB payload workflow.
Fresh ISO/HFSX/UDIF creation uses streamed private output, complete readback
verification and verified destination staging; native disk images can exceed
64 MiB members up to the 2 GiB output bound. Existing HFS/DMG images, signed
packages and static-library indexes remain read-only. The creator does not
provide durable background job restart or larger existing-container editing,
so G21 retains the durable-job work described above. Remote/browser creation UI
(G23) remains scoped.

**Delivered package-reader continuation (2026-11-12):** Portable ASCII/odc CPIO;
classic RPM v3/v4 newc/CRC payloads with gzip/bzip2/XZ/Zstandard/no compression;
single-cabinet stored/MSZIP with cross-block dictionary history; and positional
PBZX stored/XZ chunks feeding the normal inner-container readers. Shared
recognition connects panes, F3, search and extraction; extensionless F3
`Payload`/`Content` previews open supported Apple package payload trees. New
families and odc remain read-only. Package signatures are not authenticated and
no installation scripts run.

Native MakeCAB/rpmbuild/libarchive fixtures and independent PBZX readback
supplement malformed-input, traversal, limits, checksum, ownership and close-race
tests. RPM packed/decoded payloads and CAB decoded folders retain 64 MiB default
bounds. PBZX indexes up to 2 GiB logical data with one bounded 16 MiB chunk cache;
the existing 64 MiB member and nested XAR preview limits remain. CAB
Quantum/LZX/spanning, RPM v6/stripped payloads and Apple Archive/YAA are outside
this profile. Exact boundaries and provenance are in the capability matrix.

**Delivered workflow/codec continuation (2026-11-12):** LZ4 frames and
LZMA-alone support reading, verified creation and eligible rewriting, including
wrapped TAR; the creation picker now has 28 choices. Lzip v1, UNIX compress
`.Z`/`.tar.Z`/`.taz`, and modern binary CPIO in both byte orders are readable.
At that checkpoint Lzip/UNIX compress/binary CPIO were read-only; the following
CPIO writer continuation enables eligible CPIO profiles. Exact wrapper shape prevents
same-codec nested streams being flattened by a single-payload save. F3 adds a
cancellable integrity/readability report with SHA-256 and explicit failures,
skips and unchecked members. It does not repair archives or authenticate a
publisher; formats lacking checksums retain that limitation. Primary specs and
independent native fixtures/readback establish codec behavior, with Dart2JS/Node
portability checks. See the [continuation record](../archive-workflows-codecs-continuation.md).

**Starting points:** archive_viewer_service.dart; archive_workspace.dart; archive_creation_service.dart; codec capability registry.

**Delivered CPIO writer continuation (2026-11-12):** Three explicit creation
choices bring the picker to **31**: portable ASCII/odc and modern binary LE/BE.
Eligible rewrites retain their original profile, raw device/inode/ownership
fields, supported root/trailer metadata and padding. Field overflow, mixed
layouts, inode aliases, hard links and special records are refused. Independent
libarchive fresh/edited readback and byte-identical unchanged rewrites supplement
the malformed/preservation tests. No runtime dependency is added. See the
[continuation record](../archive-rearrange-cpio-continuation.md).

**Delivered UNIX compress writer continuation (2026-11-12):** `.Z` and TAR.Z
bring the picker to **33** choices. The bounded original LZW writer provides
12/14/16-bit block profiles, and eligible existing 9–16-bit block/nonblock
streams rewrite with the normal 14-bit profile. Immediate payload and physical
wrapper checks prevent losing nested layers. All 23 independent gzip/libarchive
readback cases and 18 actual JavaScript profiles pass, including dictionary
resets and external TAR metadata preservation. The format's missing checksum
and decoded length remain explicit. See the
[writer evidence](../../test/fixtures/archives/UNIX_COMPRESS_WRITER_PROFILES.md).

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
