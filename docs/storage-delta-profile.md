# Bounded native delta downloads

Status: the explicit reviewed-copy integration is qualified on Linux at
`832d3a26e004cf5268928d093841d3df61a3c5ea`: **981 tests passed across 52 native
suites**, with no failures or skips. Strict analysis passed all 23 changed Dart
files. The [complete qualification](evidence/storage-delta-queue-20261114/qualification/README.md)
and [saved checkpoints](evidence/storage-delta-queue-20261114/PROGRESS.md)
bind the results to their exact source and transport/platform scope.

The earlier standalone implementation was qualified on Linux at
`331981649872e363253aef13f57a638e5747b8e5`: 790 native tests passed across 43
suites, with no failures or skips. Its S3 evidence includes mocks and a real
loopback HTTP server. The later Word-only refresh at
`b98cd70e6dae21ba486a0704e7946cf35ab6575a` passed 60 focused host cases without
changing that delta implementation. These
[earlier receipts](evidence/storage-delta-20261114/PROGRESS.md) keep their source
pins and do not qualify the new queue integration.

The current profile validates fixed-block maps and reconstructs native local
files through the existing staged publication backend. It now also offers
**Copy method → Reuse verified S3 blocks** in an eligible Copy dialog. This is
an explicitly reviewed copy method, independent of the disabled global Delta
Sync preference. **Automatic delta selection remains unavailable.** Ordinary
transfers continue through their existing paths. No new runtime dependency is
introduced.

## Available operations

| Operation | Current boundary |
| --- | --- |
| Compute, compare and plan block maps | Native regular files; validated geometry, lengths and block hashes; source and baseline snapshots are retained in plans. |
| Reviewed `verifiedDelta` copy method | Supported native S3 source to captured native local storage, regular files with known sizes and strong reviewed ETags. Uses the ordinary queue, journal and staged writer. A conditional full copy learns a map when no trusted reusable map is available. |
| Execute a download plan | A current `LocalOperationBackend` with staged verification; an existing regular local destination; source provenance and final verification as described below. |
| S3 `seedDeltaBlockMap` | An explicit full read of one captured remote revision. It creates a persisted map and a private receipt on the current adapter instance. |
| S3 `deltaDownload` | An explicitly enabled standalone adapter API, a matching cache and a retained receipt from that adapter's verified seed or acknowledged copy; the account, object, length and remote validator must still match. |
| Recovery of a reviewed verified-block copy | Rebind and review the original source/destination, then use ordinary streaming with the existing prefix/hash reconciliation and retained-stage rules. Saved options and maps do not recreate a live reuse capability. |
| Execute an upload plan | Refused before callbacks or staging. A raw remote block-write callback does not establish safe remote publication. |
| Legacy S3/pCloud/Nextcloud delta orchestration | S3 and pCloud delta uploads, and Nextcloud delta uploads/downloads, return the existing `null` decline signal. Nextcloud's direct `uploadDeltaBlocks` method throws `UnsupportedError` before authentication or I/O. |
| Automatic delta selection | Unavailable. Saved experimental preferences do not select the reviewed method or activate the standalone APIs. |
| Browser and S3 SSE-C | Outside this new delta profile. Ordinary provider capabilities are separate. |

The pCloud random-access helpers and Nextcloud server-map inspection helpers
remain separate APIs. Their existence, a saved enable flag, or discovery of a
companion server app does not admit a delta transfer. The separate Nextcloud and
ownCloud desktop forks have their own repositories and qualification; this
increment makes no acceptance claim for their clients or servers.

## Resource limits

The [core implementation](../lib/services/delta_sync_service.dart) enforces
these limits at runtime, including when loading serialized maps:

| Quantity | Admitted limit |
| --- | --- |
| Block size | 64 KiB through 64 MiB, inclusive; default 4 MiB |
| File length | 0 through 8 GiB, inclusive |
| Signature count | At most 131,072, and exactly the count required by the file length and block size |
| Serialized cache | At most 32 MiB of UTF-8 JSON; loading also bounds actual reads if the file grows after its initial stat |
| S3 map receipts | At most 128 retained receipts per adapter instance |

Each block has its expected index, contiguous offset, exact length, unsigned
Adler-32 value and lowercase 64-character SHA-256 digest. The last block may be
shorter; an empty file has no signatures. Contradictory counts, spans, hashes,
identity lengths and unsupported schema versions are rejected. Comparisons
require equal block sizes. Plans are reconstructed and checked against their
captured maps before execution, rather than trusting caller-owned operation
lists or changed-block indices.

The reviewed method and explicit S3 APIs do not apply the older 10 MiB
heuristic. Small and empty files can be admitted when the remaining
requirements hold. A reviewed copy starts with 4 MiB blocks or uses the block
size of its authenticated current-revision map. The retained global block-size
preference does not configure this method. The separate
`shouldUseDeltaSync` helper still offers a default 10 MiB cost heuristic; it does
not enable the queue or prove that a transfer is eligible.

These are parser and execution ceilings, not claims that an 8 GiB fixture or
every target platform has passed qualification. The JSON byte limit is not a
total heap-memory bound. Other archive, browser, transfer and operation budgets
remain separate.

## Identity, provenance and cache handling

`BlockMapIdentity` records the storage namespace, object path, opaque revision
validator and exact length. S3 binds its cache namespace to the captured
endpoint/account/bucket identity as well as the object key. Changing any of
those values prevents reuse. **An ETag is a revision validator, not a content
hash.** Block contents are checked independently with SHA-256 and Adler-32.

Maps use schema version 2; identity records use version 1. Structurally valid
legacy maps without identity may still be read for local planning, but do not
acquire remote authority. A serialized or manually constructed map's `filePath`
does not authorize reopening that host path. Only a local map produced by
`computeBlockMap` in this process retains the private local-source provenance
needed for implicit source revalidation. A remotely identified source requires
an awaited `revalidateSource` callback.

For S3, persisted JSON and an apparently matching identity are insufficient on
their own. Successful `seedDeltaBlockMap` reads and acknowledged verified full
copies register a private receipt for the map contents on that adapter
instance. A loaded map must match both the current remote identity and a
retained receipt. Forged or changed map contents never authorize local reuse,
even when their JSON and signature geometry are valid. The receipt registry is
bounded and is cleared during login, logout and credential restoration.

**Restart, adapter recreation, authentication changes or loss of a receipt
require fresh remote reads before local blocks can be reused.** The standalone
`deltaDownload` API declines without a trusted map; its caller can deliberately
seed again. The reviewed copy method instead performs a conditional full copy
and learns the new map in that same transfer. A changed remote revision also
requires a full read of that revision. The persisted cache is not a resume
token, an import authorization or a durable trust record.

Cache filenames are derived from the provider, storage namespace and object
path. A cache save writes and flushes a private candidate in the destination
directory before renaming it into place; it does not truncate the previous
cache in place. Loading refuses malformed, oversized, changed or non-regular
cache files. No credentials or file payload are added to the map format.

## Explicit reviewed copy workflow

In the Copy dialog, choose **Copy method → Reuse verified S3 blocks**. The
choice is enabled only for a currently supported source/destination pair and
regular selected files with known sizes. Execution separately requires a
strong reviewed S3 ETag, exact object and destination paths, captured access
and a source length within the profile. S3 SSE-C and browser destinations are
excluded. Moves, append, explicit partial resume and preallocation are not
admitted; required cloning is a separate copy method. The existing conflict
review can replace an existing file, select a new incoming name or keep both.
New destinations use the native writer's exclusive creation behavior.

The [file-operation service](../lib/services/file_operation_service.dart) obtains
live prepared contents through a provider capability distinct from generic
range support. It retains the captured `LocalOperationBackend` and its local
access scope. Merely restoring a `verifiedDelta` enum value or a cache file
does not provide that capability.

1. **Review and queue.** The existing transfer owner persists the reviewed plan
   before queue execution. The scheduler applies provider limits and reserves
   source reads plus the destination directory and its dynamically chosen
   sibling names. The operation does not use the legacy direct-download path
   or enable the experimental global preference.
2. **Choose authenticated contents.** If the adapter has a trusted map for the
   reviewed remote revision and an existing local baseline, it reads and
   verifies reusable local blocks and downloads only differing blocks. Without
   that combination, one conditional full transfer both supplies the file and
   builds its remote block map. There is no extra seed-then-download pass.
3. **Use the ordinary writer.** Complete logical file contents pass through the
   existing control binding, per-job stream limiter, SHA-256 accounting and
   private staged writer. The service verifies the candidate's whole-file
   digest; the prepared strategy additionally checks its source block hashes,
   local baseline and remote revision.
4. **Revalidate after the journal checkpoint.** Publication proof is refreshed
   after the awaited `committing` checkpoint and pause gate. Captured account,
   destination and cancellation guards are checked again before entering the
   existing native publication boundary. A successful full copy can record
   its cache receipt after acknowledged publication; cache bookkeeping errors
   do not turn installed data into a failed copy.

The queue's logical progress includes reused bytes. The existing G29 bandwidth
context accounts for actual covered network response bytes. The separate
per-job streaming limit applies to the logical contents fed to the writer,
including reused blocks; it is not a new direct network-pacing contract.
Verification reads and metadata traffic are not represented by a changed-block
savings estimate. An all-reuse copy can download zero content bytes while still
doing complete local reconstruction and verification.

### Interruption and reviewed recovery

The existing journal records mutation phases, the completed logical stream's
SHA-256 and any owned retained stages. A prepublication failure preserves the
original destination under the staged writer's contract. Previously approved
conflict actions, such as renaming an existing file, retain their existing
journal and recovery behavior.

Acknowledged data publication and overall job completion are distinct. Late
cancellation can stop remaining verification, cleanup or metadata work after
the file has been installed. The committed data record remains available for
review; the job can remain cancelled or incomplete instead of being reported
as fully completed. A lost journal acknowledgement also requires recovery
review rather than blind replay.

Recovery never recreates the private map receipt or prepared-content object
from serialized data. **Retry remaining** and **Restart incomplete** build a
reviewed plan using ordinary `stream` copying and explicitly announce that
change in the recovery actions. Other saved options are preserved, with the
existing restart rule requiring a fresh conflict decision. Source/account
checks, verified-prefix reconciliation, confirmed-copy reconciliation and
retained-stage ownership checks remain in force. This is ordinary journaled
recovery, not durable block-level resume. Restored jobs do not start
automatically.

## Standalone S3 seed/download API

The [S3 adapter](../lib/services/s3_client_adapter.dart) exposes this sequence:

1. **Capture the object.** An authenticated native adapter obtains an exact
   length and a strong, quoted ETag from `HEAD`. SSE-C is refused for this
   profile. The admitted object path must have an unambiguous spelling;
   repeated leading slashes, empty or dot/dot-dot segments, backslashes and
   percent-containing keys are rejected instead of being normalized into
   another object's identity. Percent-containing keys need a separately
   reviewed URI representation before this profile can admit them.
2. **Seed deliberately.** `seedDeltaBlockMap` reads every block through
   conditional ranges and computes its hashes. It rechecks the remote identity
   before persisting the map and recording its private receipt. Seeding costs
   one complete remote read; caller-supplied local bytes are not substituted as
   proof of the remote contents.
3. **Admit a subsequent reconstruction.** The caller explicitly enables the
   adapter API and supplies the cache directory and an existing regular local
   file to `deltaDownload`. The cached map, retained seed receipt and current
   remote identity must agree. The local file is scanned using the same block
   size, then compared with the seeded remote map.
4. **Read changed blocks.** Every requested remote block uses the captured
   `If-Match` validator and exact range. Matching blocks are read from the
   captured local baseline. Both kinds of bytes are validated during private
   candidate construction.
5. **Verify and publish.** The complete candidate, original local destination
   and remote identity are rechecked before the existing native backend enters
   its replacement boundary.

This standalone workflow reuses one seeded remote revision against local baselines.
It does not discover the hashes of a newly changed remote object without
reading that revision to seed it again. Reported changed-block savings exclude
the initial seed, local verification reads, metadata requests and protocol
overhead; they are not a measured end-to-end bandwidth benchmark.

### Exact range contract and bandwidth context

A delta range requires HTTP `206`, an exact `Content-Range` start/end/total,
the expected content length when supplied, and the exact requested body length.
Ignored ranges, mismatched metadata, non-identity content encoding, short or
overlong bodies and conflicting returned ETags fail. Requested ranges are
bounded to one block, and the source length must remain within the profile.
Account/authentication changes and cooperative cancellation are checked around
requests and response consumption.

Requests and bounded response streams reuse the existing
[G29 foreground HTTP helpers](file-manager-gaps/transfer-bandwidth-http-profile.md).
When a `TransferBandwidthContext` is present, the range's actual admitted
response bytes use its download pool. Merely calling an explicit adapter API
does not create a queue identity or enable a bandwidth policy. The existing
HTTP profile's platform and transport boundaries remain unchanged.

### Decline and failure are different results

For standalone `deltaDownload`, disabled adapter admission, a missing cache
directory, an absent/invalid/stale
cache, a missing or mismatched private seed receipt, or a non-regular local
destination produces the existing `null` decline result where applicable.
The caller may then choose an ordinary transfer. Unsupported profiles, failed
metadata/range reads, source changes, cancellation and verification failures
are errors; an admitted error is not silently converted into a full transfer.
The reviewed copy method has a different explicit contract: a fresh conditional
full copy is its declared behavior when there is no trusted reusable map. An
error after that method has begun reading or preparing a candidate is not a
reason to repeat the transfer through another path.

## Native reconstruction and publication

The core first freezes and validates the complete plan, then verifies the
existing destination against its baseline map. Changed download blocks must
have their exact lengths and hashes. Reused local blocks are also read and
hashed; a matching map entry alone is not enough. The implementation owns
returned bytes across asynchronous staging so a provider cannot change them
by reusing a response buffer.

The local staged writer receives the reconstructed stream and the exact final
length (`writePreparedFile` for the standalone API, the normal configured
writer for a reviewed copy). The private candidate is read back in full and checked
against every source-map signature. The original destination is re-read and
compared with its captured baseline; source revision, access and file stamps
are checked again before publication. Shrink-only, empty and all-skip results
still pass these checks and apply the final length. An empty changed-block list
does not make a size change disappear.

Preparation, validation and cancellation failures before replacement preserve
the original through the existing staged-backend contract. Cancellation is
cooperative at read and verification boundaries; it is not a promise to
preempt an indefinitely blocked caller-supplied read. Once replacement is
acknowledged, auxiliary cache work does not invalidate the installed data.
For reviewed queued operations, late cancellation can still stop remaining
job work as described above; it does not erase the committed journal evidence.

The local backend's final check/rename boundary is **not an atomic
compare-and-swap against an external writer**. The standalone APIs do not add
an operation journal, path reservation or restart/resume semantics. The
explicit reviewed copy method uses the existing journal and scheduler path
claims. Those claims coordinate participating queued work in the current
process; they do not exclude external writers or other processes. Neither
entry point establishes durable delta authentication or atomic external-writer
comparison and replacement.

Upload plans can be computed for inspection, but `applyDelta` refuses upload
execution before invoking a remote-write callback. Remote staging, base
revision checks, exact final-size verification and conditional publication
need a separately admitted provider contract.

## Settings and historical claims

Settings → Advanced → Delta Sync displays a disabled control and a localized
message directing supported S3 copies to the explicit copy-dialog method.
Automatic delta selection remains unavailable. Previously saved enable and
block-size preferences remain stored for migration; they neither select the
new method, configure it, nor bypass adapter admission. The standalone
adapter's `deltaSyncEnabled` flag is also independent of the reviewed method.

[ADR-007](adr/007-block-level-delta-sync.md) is retained as a historical design
record. Its in-place remote mutation strategies, automatic opt-in description,
and old live-test or savings claims are superseded for this CrispCloud profile.
They are not repeated as current runtime acceptance. The
[original source investigation](evidence/storage-capabilities-20261114/delta-source-review.txt)
also keeps its original revision and observations.

## Qualification

The [reviewed-copy qualification](evidence/storage-delta-queue-20261114/qualification/README.md)
binds **981 passes across 52 native suites** to source
`832d3a26e004cf5268928d093841d3df61a3c5ea`, tree
`5b185bf4c52650cb64c0895f0c7c349f800c8808`. There were no failures, skips or
error events. All **8,390** recorded inputs and the clean HEAD/tree stayed
unchanged. Strict analysis passed all **23** changed Dart files. An independent
parse verified every suite count, input inventory and receipt artifact.

The three new runtime suites provide 68 prepared-content, provider and queued
copy cases. Coverage includes source/baseline/candidate changes after the
committing journal write, pause/cancel and abort races, captured connection
revocation, map provenance/tampering, first-copy cache creation, logical-stream
and HTTP-byte accounting, reviewed recovery, and a lost committed
acknowledgement. Real signed loopback HTTP executes a first journaled copy and
an all-reuse repeat. Fault-injected HTTP fixtures cover differing local blocks
and malformed or stalled responses. These results do not establish live S3
interoperability or another platform's execution behavior.

### Earlier standalone qualification

The [continuation receipt](evidence/storage-delta-20261114/PROGRESS.md) and
[complete qualification](evidence/storage-delta-20261114/qualification/README.md)
bind the run to source `331981649872e363253aef13f57a638e5747b8e5` and tree
`6ec8e483ff2c597c145dfcff4e3f75331ad9faae`. All 8,382 recorded tracked/generated
inputs and the clean Git state remained unchanged during the run.

The core suites passed 114 cases, the S3 profile 36, and provider admission 9.
The combined 790-case cohort also covers existing adapters, localized settings,
the imported bandwidth/queue behavior, local staging, Office host workflows
and portable mesh previews. These counts exclude hidden framework setup tests.
The S3 suite uses both mock failure injection and a real signed loopback HTTP
sequence with exact conditional ranges and complete output comparison.

The tests cover malformed plans/maps, length changes, range and hash failures,
cache provenance, source/account changes, staged-candidate verification,
cancellation timing and rejection of legacy remote mutations. Fifty Python
sync/evidence tests also passed. The latest guarded Office refresh verifies
2,187 managed hashes and passed 232 canonical cases plus 60 app host cases at
their exact source revisions; see its
[separate follow-up](evidence/storage-delta-20261114/office-refresh/README.md).

Ten historical Nextcloud/ownCloud live mutation scenarios remain explicitly
skipped in their opt-in suites; those suites were not part of this native
cohort. They are not counted among the 790 passes or treated as qualified.

The earlier tests retain their original scope; the 981-case cohort above
qualifies the reviewed provider strategy, queue/UI admission and ordinary
recovery downgrade on Linux. This document makes no browser/mobile packaging,
Windows/macOS execution, live-S3 interoperability, external desktop-fork,
process-crash injection or general remote-write qualification claim.
