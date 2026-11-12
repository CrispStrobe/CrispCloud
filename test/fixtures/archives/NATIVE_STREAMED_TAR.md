# Native streamed TAR / CBT acceptance

This increment extends **fresh native plain TAR and CBT creation** to an
explicit 2 GiB output ceiling, including headers, extension records and
alignment padding. It uses CrispCloud's original TAR writer, the existing
native output spool and the locked `koni_tar` 0.9.0 reader. No runtime
dependency or native codec was added.

The writer's default and existing-archive rewrite ceiling remain 256 MiB.
Normal member reads still default to 64 MiB. Compressed TAR, ZIP, 7z, buffered
creation backends and existing-archive editing retain their separate limits.
`ArchiveCreationService.supportsStreamedTarCreation` is shared by the service
and creation-dialog guidance: both endpoints must identify native local
storage and advertise the required bounded reads, bounded writes and staged
verification. Browser builds cannot take this path.

## Producer and independent readers

The native producer is
[`archive_large_tar_creation_test.dart`](../../archive_large_tar_creation_test.dart).
Its acceptance case creates real source files and exercises the complete
`ArchiveCreationService` and `LocalOperationBackend` path: spool, reopened TAR
verification, source revalidation, staged write, complete staged SHA-256,
final source revalidation and exclusive publication. The original input
files remain present throughout their creation operation.

The generated cases are:

| Output | Members | Payload bytes | Complete output bytes |
| --- | --- | ---: | ---: |
| `native-large.tar` | Six records: a directory tree, empty file/directory, 65 MiB + 333-byte file and 192 MiB + 777-byte file | 269,485,142 | 269,489,664 |
| `native-large.cbt` | One 65 MiB + 333-byte file | 68,157,773 | 68,159,488 |

Both large inputs consist of repeated 65,536-byte blocks. Within each block,
byte `i` is `(i + seed) % 251`; the two seeds are 7 and 19. The final partial
block follows the same rule. Empty-file content is empty. File modification
times are fixed at `2026-01-02T03:04:05Z`; directory times and supported modes
are captured from the native filesystem and recorded in each run's manifest.
Consequently, regenerated archive digests may differ while the input content
digests remain deterministic.

[`check_archive_large_tar.py`](../../support/check_archive_large_tar.py)
independently regenerates each expected content digest, checks the complete
archive digest and size, reads every regular member through Python's
`tarfile` module, and separately extracts each regular member through GNU
tar's standard-output interface. Both readers are drained in at most 1 MiB
chunks; the checker never accumulates a full file or archive. Python also
checks the exact namespace, regular-file/directory type, size, modification
time and mode. GNU tar also lists both complete archives successfully.

Primary reference documentation:

- [GNU tar: Basic Tar Format](https://www.gnu.org/software/tar/manual/html_node/Standard.html)
  describes 512-byte records, header checksums and the terminal zero records.
  The TAR header checksum does not authenticate file payloads; creation
  verification therefore compares freshly reopened payload hashes with the
  captured source hashes.
- [GNU tar: Writing to Standard Output](https://www.gnu.org/software/tar/manual/html_node/Writing-to-Standard-Output.html)
  documents extraction through `--extract --to-stdout`.
- [Python 3.12: tarfile](https://docs.python.org/3.12/library/tarfile.html)
  documents uncompressed `r:` reads and the file object returned by
  `extractfile`.

These tools are used only for validation. No implementation from GNU tar or
VaultExplorer was copied or imported. Existing permitted Dart reader code
was inspected to verify its streaming behavior.

## Measured native acceptance

The saved
[`native-streamed-tar-acceptance.json`](native-streamed-tar-acceptance.json)
records the successful Linux run on 2026-11-12, using Flutter 3.47.8 /
Dart 3.13.7, Python 3.12.14 and GNU tar 1.35.

| Check | Result |
| --- | --- |
| Focused writer/reader/native-creation gate | 24 tests passed |
| Existing TAR writer, creation and extended creation regression | 112 tests passed |
| Fatal-info analysis of the three implementation files and focused test | Clean |
| Independent Python/GNU readback | Both complete output cases passed |
| Largest observed source or staged-file read chunk | 65,536 bytes |
| Largest observed output-transfer chunk | 262,144 bytes |
| Source-content passes in each complete creation | Three: packing, pre-staging recheck and final staged-verification recheck |
| TAR sampled process RSS | 280.36 MiB baseline; 323.74 MiB peak; 43.38 MiB increase |
| CBT sampled process RSS | 300.05 MiB baseline; 331.78 MiB peak; 31.73 MiB increase |

RSS is sampled on progress callbacks and a 5 ms periodic timer inside the
Flutter test process. It includes the test runner, JIT and other process
state; these observed increases are **not** a universal memory ceiling. The
payload path does not retain full members or output. Namespace/header indexes
still use memory proportional to the bounded entry and metadata counts.

The synthetic reader tests cap positional reads and confirm that taking only
two 16 KiB output chunks fetches one 64 KiB TAR payload range. Format detection
can make a separate 65,557-byte ZIP-tail probe before identifying TAR. Creation
verification caps any individual positional request at 1 MiB, including
extension metadata, and checks cancellation before and after each request.
Closing the archive, cancelling a stream, passing a foreign member or asking
to exceed the opening member cap cannot continue a valid read.

Progress reports actual bytes across every substantial pass. For `N` source
bytes and `S` output bytes, packing reports `N`, verification reports
`2N + S`, and saving reports `N + 2S`. Each phase reached its exact total.
The 5 ms timer ran during every packing, verification and saving phase,
demonstrating that these paths yielded to the event loop. Source rechecks and
hashing explicitly yield after 1 MiB or 16 ms between chunk boundaries.

Failure regressions cancel during all seven payload passes, mutate source
content while preserving size and modification time, corrupt staged bytes,
introduce a destination immediately before native publication, and cancel
after a completed exclusive commit. Failures before commit leave no published
archive and remove their staging directory; a late existing destination is
preserved. A completed exclusive publication remains successful if
cancellation arrives afterward.

An earlier acceptance attempt encountered a real disk-full error while
starting the CBT stage after TAR had succeeded. The service disposed its
private spool/stage; test teardown removed only its generated source fixtures.
After disposable build artifacts were removed, the complete
24-test gate and both independent checks passed. The writer preflights the
2 GiB boundary, including a payload that fits exactly once its 512-byte header
and 1,024-byte ending are included. The acceptance run does **not** claim to
have written a full 2 GiB payload or to establish native release acceptance
on macOS or Windows.

## Reproduction

Use the project's pinned Flutter/Dart SDK and resolved locked dependencies.
Choose a new output directory and allow at least about 0.8 GiB of extra free
space for the generated source, private spool and destination stage, beyond
normal build/test caches:

```sh
CRISP_LARGE_TAR_REFERENCE_DIR=/tmp/crisp-large-tar-reference \
  flutter test --no-pub --reporter expanded --concurrency=1 \
  test/archive_large_tar_creation_test.dart
python3 test/support/check_archive_large_tar.py /tmp/crisp-large-tar-reference
```

The producer refuses to replace an existing output. The manifest preserves
exact sizes, content digests, metadata and measured progress/memory evidence;
large generated files are deliberately excluded from the repository. In the
agent environment, validation used the serialized wrapper that temporarily
disables the unrelated optional ebook hook and selects system SQLite, then
restores `pubspec.yaml` without changing the lockfile.

This is cancellable foreground creation. It does not add a durable packing
queue, process-restart resume, general larger editing, or remote/browser
publication guarantees; the durable-background-packing gap remains partial.
