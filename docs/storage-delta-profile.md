# Bounded native delta downloads

Status: implemented on `integration/storage-delta-20261114` and qualified on
Linux at `331981649872e363253aef13f57a638e5747b8e5`: 790 native tests passed
across 43 suites, with no failures or skips. Strict scoped analysis passed.
S3 transport evidence includes mocks and a real loopback HTTP server. The
subsequent Word-only runtime refresh at
`b98cd70e6dae21ba486a0704e7946cf35ab6575a` passed 60 focused host cases while
leaving the delta implementation unchanged. The
[continuation receipt](evidence/storage-delta-20261114/PROGRESS.md) records the
saved checkpoints and subsequent validation. Earlier storage, bandwidth and
Office receipts retain their own source revisions and scopes.

This increment validates fixed-block maps and reconstructs a native local file
through the existing staged publication backend. It also provides an explicit
S3 API for reading and hashing a remote revision, then using that same revision
to reconstruct a local file. **Automatic delta transfers are unavailable in the
queue.** Ordinary transfers continue through their existing paths. This
increment introduces no new runtime dependency.

## Available operations

| Operation | Current boundary |
| --- | --- |
| Compute, compare and plan block maps | Native regular files; validated geometry, lengths and block hashes; source and baseline snapshots are retained in plans. |
| Execute a download plan | A current `LocalOperationBackend` with staged verification; an existing regular local destination; source provenance and final verification as described below. |
| S3 `seedDeltaBlockMap` | An explicit full read of one captured remote revision. It creates a persisted map and a private receipt on the current adapter instance. |
| S3 `deltaDownload` | An explicitly enabled adapter, a matching cache and a retained receipt from that adapter's own seed; the account, object, length and remote validator must still match. |
| Execute an upload plan | Refused before callbacks or staging. A raw remote block-write callback does not establish safe remote publication. |
| Legacy S3/pCloud/Nextcloud delta orchestration | S3 and pCloud delta uploads, and Nextcloud delta uploads/downloads, return the existing `null` decline signal. Nextcloud's direct `uploadDeltaBlocks` method throws `UnsupportedError` before authentication or I/O. |
| Automatic queue admission | Unavailable. Saved preferences do not activate these APIs. |
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
| S3 seed receipts | At most 128 retained receipts per adapter instance |

Each block has its expected index, contiguous offset, exact length, unsigned
Adler-32 value and lowercase 64-character SHA-256 digest. The last block may be
shorter; an empty file has no signatures. Contradictory counts, spans, hashes,
identity lengths and unsupported schema versions are rejected. Comparisons
require equal block sizes. Plans are reconstructed and checked against their
captured maps before execution, rather than trusting caller-owned operation
lists or changed-block indices.

The explicit S3 APIs do not apply the older 10 MiB heuristic. Small and empty
files can be admitted when the remaining requirements hold. The separate
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
their own. Successful `seedDeltaBlockMap` reads register a private receipt for
the map contents on that adapter instance. A loaded map must match both the
current remote identity and a retained receipt. Forged or changed map contents
decline admission even when their JSON and signature geometry are valid. The
receipt registry is bounded and is cleared during login, logout and credential
restoration. **Restart, adapter recreation, authentication changes or loss of a
receipt require an explicit fresh remote seed.** The persisted cache is not a
resume token, an import authorization or a durable trust record.

Cache filenames are derived from the provider, storage namespace and object
path. A cache save writes and flushes a private candidate in the destination
directory before renaming it into place; it does not truncate the previous
cache in place. Loading refuses malformed, oversized, changed or non-regular
cache files. No credentials or file payload are added to the map format.

## Explicit S3 workflow

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

This initial profile reuses one seeded remote revision against local baselines.
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

Disabled adapter admission, a missing cache directory, an absent/invalid/stale
cache, a missing or mismatched private seed receipt, or a non-regular local
destination produces the existing `null` decline result where applicable.
The caller may then choose an ordinary transfer. Unsupported profiles, failed
metadata/range reads, source changes, cancellation and verification failures
are errors; an admitted error is not silently converted into a full transfer.

## Native reconstruction and publication

The core first freezes and validates the complete plan, then verifies the
existing destination against its baseline map. Changed download blocks must
have their exact lengths and hashes. Reused local blocks are also read and
hashed; a matching map entry alone is not enough. The implementation owns
returned bytes across asynchronous staging so a provider cannot change them
by reusing a response buffer.

`LocalOperationBackend.writePreparedFile` receives the reconstructed stream and
the exact final length. The private candidate is read back in full and checked
against every source-map signature. The original destination is re-read and
compared with its captured baseline; source revision, access and file stamps
are checked again before publication. Shrink-only, empty and all-skip results
still pass these checks and apply the final length. An empty changed-block list
does not make a size change disappear.

Preparation, validation and cancellation failures before replacement preserve
the original through the existing staged-backend contract. Cancellation is
cooperative at read and verification boundaries; it is not a promise to
preempt an indefinitely blocked caller-supplied read. Once replacement is
acknowledged, a late cancellation does not turn the completed install into a
failure.

The local backend's final check/rename boundary is **not an atomic
compare-and-swap against an external writer**. This API does not add a durable
operation journal, restart/resume semantics, a destination path reservation or
cross-process exclusion. It reuses the existing native access and staging
facilities; exposing it through automatic queue operations requires a separate
admission and recovery integration.

Upload plans can be computed for inspection, but `applyDelta` refuses upload
execution before invoking a remote-write callback. Remote staging, base
revision checks, exact final-size verification and conditional publication
need a separately admitted provider contract.

## Settings and historical claims

Settings → Advanced → Delta Sync displays a disabled control and a localized
message that automatic delta transfers are unavailable and files use standard
transfers. Previously saved preferences remain stored for migration; they
neither enable queue execution nor bypass adapter admission.

[ADR-007](adr/007-block-level-delta-sync.md) is retained as a historical design
record. Its in-place remote mutation strategies, automatic opt-in description,
and old live-test or savings claims are superseded for this CrispCloud profile.
They are not repeated as current runtime acceptance. The
[original source investigation](evidence/storage-capabilities-20261114/delta-source-review.txt)
also keeps its original revision and observations.

## Qualification

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

Static analysis alone does not establish runtime behavior. This document makes
no browser, mobile packaging, live-S3 interoperability, external desktop-fork,
crash-recovery or general remote-write qualification claim.
