# VeraCrypt / TrueCrypt local qualification — 15 November 2026

## Integrated baseline

The initial audit fetched every visible remote branch and pull-request head.
[`incoming-branches.json`](incoming-branches.json) records 18 branch heads and
110 pull-request refs. Main was `686318626e209220011f7da194cfe4e41ca4adeb`.
The implementation started from the combined storage/Office baseline
`7d0de79eeb5932e355e66af0be073d58f9fcf3c4`, which includes open drafts #110 and
#111, plus the evidence-only head
`6a5603236c9f3f9e186c5eb3ba5fd76a085b1df6`.
The published merge checkpoint `7c1c925028d66f8109c628b8c17a0d4f1d70cb73`
preserves both parents.

Two historical source branches were already superseded by the combined
implementation: `fix/excel-legacy-xls` and `integrate/consistency-20261115`.
The audit verified all 52 and 20 retained historical import blobs respectively,
and recorded the combined/replaced paths instead of restoring obsolete files.

The final refresh found subsequent spreadsheet-comments work and local acceptance
receipts. Their read-only delta review is in
[`branch-refresh-audit.json`](branch-refresh-audit.json). Both refreshed heads,
`3e9560c9b4bd617b5346bacd8b5039493f0f2dc1` and
`22c4f42acc575bee8f5119a4803af13b57ef7cbc`, are preserved by the later merge
checkpoints `0c621a1f48e2c28075ef4f2813460e2a33bfcc9b` and
`2f8a5cc1a0b1058377b503c02ba21d44458d7f62`. The two provenance conflicts retain
the newer Quds `4e8c8f80` manifest and both branches' evidence. Imported receipts
retain their original qualification scope.

Implementation checkpoints were saved remotely during development. GitHub
Actions was neither polled nor awaited. Each GitHub-created checkpoint tree
was compared with the corresponding local Git tree before advancing the branch.

## Final result

- **316/316 focused Flutter tests passed**, plus both completed compiled-JavaScript
  probes in the same local command.
- **27 focused Dart files passed strict analysis** with no issues. The separately
  reviewed `panel_provider.dart` integration has no errors or warnings and retains
  13 pre-existing style infos outside the changed lines.
- The source inventory gate passed with **756 reviewed paths** and the unchanged
  dependency lock. The Office manifest verified **2,336 managed files**.
- **92/92 fresh ODS/comments tests passed** against the incoming source, using an
  offline-resolved scratch dev graph and the package's own fixture directory.
- **8/8 JavaScript runner controls passed**, including false-success, delayed
  error and timeout cases.

See [`validation.json`](validation.json) for exact commands and hashes,
[`source-sha256.json`](source-sha256.json) for the tested feature bytes and
[`focused-tests.log`](focused-tests.log) for the completed main run. The tested
code checkpoint is `b55ce4e1db97be88b5e9df200e9b0c9feaba1e50`; the subsequent
publication checkpoint adds documentation, source-hash bindings and future
workflow test entries.

## Reproduce the focused checks

Use the repository's resolved dependency graph with Flutter 3.47.8 / Dart 3.13.7,
Python 3 and Node.js available, then run:

```sh
tool/check_veracrypt.sh
```

The script runs the focused crypto, encrypted-container reader, worker,
panel/session, mount and viewer/widget cohorts. It then compiles and executes
both JavaScript probes. Its Node runner provides the browser-style global used
by Dart's async scheduler and requires an explicit completion marker; a silent
zero exit is a failure.

The existing `tool/with_ci_system_sqlite.py` wrapper uses a separately probed
system SQLite library for native hooks and restores the original pubspec on
exit. The local SQLite 3.46.1 probe verified foreign keys, transactions and FTS5.
No dependency override, changed lockfile, disabled hook or skipped checksum was
used as an application change. The Flutter archive and locked package archives
were checksum-verified during setup.

The final machine-readable receipt and retained logs in this directory record
the exact source hashes and outcomes. The strict analyzer is run over the Dart
files changed by this feature, rather than treating unrelated historical
warnings as this feature's results.

## Coverage and limits

The crypto corpus was assembled independently with Python cryptography/OpenSSL,
hashlib and zlib. It includes current Argon2id with the production PIM-1 cost
(64 MiB, three passes, 192 derived bytes), all supported PBKDF2/TrueCrypt PRFs,
custom PIM, short/long/keyfile-only credentials, malformed header CRC/geometry,
4096-byte logical sectors and XTS unit indices beyond 32 bits. Parameter tests
cover the default Argon2 cost and policy boundaries without allocating its full
416 MiB working set.

Complete encrypted FAT fixtures qualify primary/hidden/backup slots, file and
nested-directory listing, cross-sector/unaligned file reads, credential retries,
source mutation, cancellation, locking and pane ownership. The running-worker
cancellation test starts an admitted 19,015,000-iteration PBKDF2 job and verifies
that cancellation releases the slot for a subsequent valid unlock. It does not
substitute a trivial derivation for the expensive running job.

The new complete encrypted-image fixtures use FAT12. NTFS and ext2/3/4 browsing
reuse the already documented bounded readers; this receipt does not claim new
upstream-generated encrypted NTFS/ext corpus coverage. Likewise, no container
created by an upstream VeraCrypt/TrueCrypt executable, signed Apple/Android app,
live cloud account or physical device was qualified in this run.

JavaScript crypto and full-reader probes cover the admitted browser PBKDF2 and
TrueCrypt paths and verify that Argon2 is refused before allocation. They are
compiled-JavaScript runtime checks, not a claim of interactive browser/device
acceptance. The widget tests execute Flutter's headless Linux test runtime.

The supported product profile, dependency decision and inherited project-license
boundary are in [veracrypt-support.md](../../veracrypt-support.md).
