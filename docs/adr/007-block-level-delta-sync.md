# ADR-007: Block-Level Delta Sync

## Status

Historical decision accepted on 2026-06-08; execution and admission details
superseded on 2026-11-14 by the
[bounded native delta-download profile](../storage-delta-profile.md).

The sections below preserve the original design and historical observations.
Their in-place pCloud/Nextcloud mutation strategies, automatic opt-in behavior,
and old live-test, timing and bandwidth-savings claims are not current
CrispCloud acceptance. Automatic delta queue transfers are unavailable;
Settings shows that status and retains saved preferences without activating
execution. Upload execution and legacy provider orchestration decline.

The continuation adds validated maps/plans, private native reconstruction and
an explicit S3 seed/download API. S3 seeding reads a complete captured remote
revision; a private receipt on the same adapter instance is also required for
cache reuse. Restart or adapter recreation requires a fresh seed. The new
profile does not inherit the old 10 MiB activation description, provide durable
resume/path reservations, or claim an atomic compare-and-swap against external
local writers. Runtime qualification remains pending in the
[continuation receipt](../evidence/storage-delta-20261114/PROGRESS.md).

The separate Nextcloud/ownCloud desktop clients and companion server retain
their own scope and evidence; they are not certified by this continuation.

## Context

CrispCloud users often sync large files that change incrementally: VeraCrypt containers, SQLite databases, VM disk images, PST archives, disk backups. A 500 MB VeraCrypt container with 8 MB of changed sectors was being re-uploaded in full on every sync — wasting bandwidth and time.

We needed block-level delta sync: detect which parts of a file changed, transfer only those parts.

## Decision

### Algorithm

We implemented an rsync-inspired algorithm with two hash levels:

1. **Adler-32 rolling hash** (weak, fast) — O(1) per byte for sliding window, used as pre-filter
2. **SHA-256** (strong, collision-resistant) — computed per block, used for confirmation

Files are split into fixed 4 MB blocks. A `BlockMap` stores both hashes for each block. Comparing local vs remote block maps yields a `DeltaResult` listing changed block indices.

### Architecture

```
DeltaSyncService (provider-agnostic engine)
  ├── computeBlockMap()     — scan file into BlockSignatures
  ├── compareBlockMaps()    — find changed blocks
  ├── createTransferPlan()  — schedule upload/download/skip per block
  └── applyDelta()          — execute plan via provider callbacks

Provider adapters wire the callbacks:
  ├── Nextcloud  — Range GET + server app block PUT (or chunked upload fallback)
  ├── pCloud     — file_pread / file_pwrite (native random-access API)
  └── S3         — Range GET for downloads, full upload for writes (S3 limitation)
```

### Provider-specific strategies

| Provider | Read Block | Write Block | Block Map Source |
|----------|-----------|-------------|-----------------|
| **Nextcloud** (with server app) | Range GET | POST to `/api/blocks/{path}` | Server computes + caches |
| **Nextcloud** (without app) | Range GET | Chunked upload v2 (full file) | Client-cached, ETag-validated |
| **pCloud** | `file_pread(fd, offset, count)` | `file_pwrite(fd, offset, data)` | Client-cached or computed via pread |
| **S3** | `GET` with `Range` header | Full upload (no partial write) | Client-cached, ETag-validated |

### Server-side component (Nextcloud/ownCloud)

A companion Nextcloud app (`crispcloud_delta`) was built to provide server-side block map computation and partial block writes. Without it, the client falls back to client-cached block maps with ETag validation.

The app uses the same Adler-32 + SHA-256 algorithm as the Dart implementation, verified by cross-platform hash matching tests.

### Opt-in design

Delta sync is disabled by default (`deltaSyncEnabled = false`) and only activates for files above a configurable threshold (default 10 MB). This avoids overhead on small files where full transfer is faster than computing block maps.

## Consequences

### Positive
- 500 MB file with 8 MB changes: 98.4% bandwidth savings
- 12 MB file with 4 MB changes: 66.7% savings (verified in live tests)
- Provider-agnostic core engine — adding new providers requires only callback wiring
- Server app is optional — graceful fallback to cached block maps

### Negative
- Block map computation has CPU cost (~250 ms for 100 MB on modern hardware)
- Cache storage required for block maps (~1 KB per 4 MB of file)
- pCloud's pread/pwrite makes one HTTP request per block (latency for many small changes)
- S3 can't do partial writes — delta sync only helps downloads and skip-if-unchanged decisions

### Risks
- Cached block maps can become stale if another client modifies the file between syncs (mitigated by ETag validation)
- Server app requires PHP 8.0+ and Nextcloud 25+ (documented in compatibility matrix)
- Adler-32 has collision risk (mitigated by SHA-256 confirmation step)

## Alternatives Considered

1. **rsync over SSH** — requires SSH access, not available for most cloud providers
2. **Seafile's block-level storage** — requires Seafile server, not compatible with WebDAV/S3
3. **bsdiff/xdelta binary diff** — more space-efficient but requires both versions in memory
4. **Variable-size chunking (content-defined)** — better dedup but more complex, harder to implement server-side
