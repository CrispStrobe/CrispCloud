# Native streamed archive reader verification

This records direct, offline Dart verification of the ZIP, 7z and TAR.GZ reader
path. These results establish that the native reader can decode complete members
larger than 2 GiB without collecting their contents into one byte array. They do
not establish that Flutter UI or workspace publication tests have executed.

## Executed large-payload checks

The companion streaming writer generated one `large.bin` per format containing
exactly **2,147,483,665 zero bytes (2 GiB + 17)**, mode `0644` and modification time
`2026-11-12T01:02:03Z`. Each reader ran in a fresh Dart VM process, opened the
physical archive, checked the rewrite policy, consumed the complete member,
checked every decoded byte against zero, and checked the exact decoded length.
All three checks passed.

| Container | Compressed archive bytes | Decoded member bytes | Elapsed milliseconds | Largest emitted chunk | Sampled RSS growth | Sampled peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ZIP | 2,087,412 | 2,147,483,665 | 14,259 | 65,536 | 127,442,944 | 464,060,416 |
| TAR.GZ | 2,087,347 | 2,147,483,665 | 16,961 | 65,536 | 71,036,928 | 404,619,264 |
| 7z, LZMA2 | 925,824 | 2,147,483,665 | 23,339 | 65,536 | 215,236,608 | 551,333,888 |

RSS is process resident memory in bytes, including the JIT compiler, Dart heap
and loaded libraries. Growth is relative to the process before archive opening;
the peak is sampled, not an allocation bound. These are observations on one
Linux environment with Dart 3.13.7, not mobile memory budgets or performance
guarantees. The very compressible fixtures in this table exercise decoded size
and long-lived decoder state; their compressed container lengths are below
2 GiB. The stored-container checks below separately exercise archive offsets
and logical file lengths above 2 GiB. Neither fixture class represents arbitrary
high-entropy data.

A 20 millisecond timer also ran throughout each check. It fired 33, 842 and 228
times respectively. This confirms that the asynchronous stream yielded to the
event loop during each operation; it does not measure or guarantee frame
latency. No whole-payload SHA-256 was recorded by this probe: content was checked
byte by byte, and container/member CRC checks remained enabled.

The TAR.GZ reader expands its TAR to an owned temporary spool before listing.
That requires temporary logical storage proportional to the expanded archive.
The native spool can represent zero runs sparsely on filesystems that support
sparse files. Memory use is bounded separately from disk capacity. Closing the
returned archive closes its byte sources and disposes its expanded TAR spool.

## Stored containers larger than 2 GiB

`test/support/verify_archive_streamed_large_container.dart` passed the additional
large-container acceptance check. It supplies **2 GiB + 17 zero bytes** to the
production streaming writer at level 0, writes into the production
`ArchiveOutputSpool`, seals that output, and opens the same spool with the
production streamed reader. Store/Copy compression means the container itself,
not only its expanded member, is larger than 2 GiB. The reader consumes every
member byte and checks content, exact size, modification time and permissions.

| Format | Logical container length | Complete member bytes | Sparse oracle file allocation | Write time | Production read time | Largest reader chunk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ZIP Store | 2,147,483,815 | 2,147,483,665 | 266,240 bytes | 18,369 ms | 11,616 ms | 65,536 bytes |
| 7z Copy, final implementation | 2,147,483,779 | 2,147,483,665 | 266,240 bytes | 29,803 ms | 9,429 ms | 65,536 bytes |

The probe exports the exact public spool stream to another sparse file for
independent verification. Python's `zipfile` reader and the installed system
`libarchive` reader respectively consumed all **2,147,483,665** member bytes,
verified the metadata, and checked every byte was zero. Both independently
reported this SHA-256:

```text
d9378e43c0e666027848e63668ba0a821b4726843e366626946e3823b477299e
```

The allocated-byte column is the independent oracle copy's `st_blocks * 512`
on this Linux filesystem. Its logical size is over 2 GiB while zero runs are
represented by holes. This verifies large container offsets, source lengths,
end metadata and full Store/Copy reads; it does **not** claim that more than
2 GiB of disk blocks were allocated or that an app publication occurred.
The production spool and exported files are removed when the probe finishes.

This check exposed unnecessary small positional reads for 7z Copy. The original
implementation used 4 KiB input chunks for compressed and uncompressed coders
alike. The completed initial Copy run passed production and independent reads
but took 38,010 ms for the production read, requiring 524,289 payload reads.
Copy now uses 64 KiB source chunks, requiring 32,769 payload reads, while
compressed codecs retain their 4 KiB expansion budget. The final code passed
the same complete fixture and independent oracle with a 9,429 ms read.
These timings came from separate runs under different concurrent load, so
they are observations rather than a controlled speedup benchmark.

The final ZIP and 7z probes observed sampled Dart-process RSS growth of
67,665,920 and 64,598,016 bytes respectively, with sampled peaks of 389,242,880
and 397,099,008 bytes. Output writer chunks never exceeded 262,144 bytes.
The same JIT/process-memory caveats as the compressed-fixture measurements
apply. No Flutter engine, UI, provider publication or native app build was
executed by these probes.

## Executed codec and compatibility checks

`test/support/verify_archive_streamed_reader.dart` passed the following direct
Dart checks:

- LZMA and LZMA2 decoded a 1 MiB nontrivial payload with a 4 KiB ring dictionary,
  using input fragments of 13 and 17 bytes respectively. The LZMA2 stream retained
  history across successive 8 KiB chunks.
- Native streaming writer/reader round trips passed for ZIP, 7z, TAR and TAR.GZ
  at compression levels 0 and 6. Fixtures included a 1 MiB regular file, an empty
  file and a directory, with modification times and POSIX modes. The opening
  operation's cancellation flag was set after opening; later member reads still
  succeeded, confirming that a completed job cannot invalidate its reader.
- Independently supplied `koni_sevenz` fixture archives for Copy, Deflate,
  LZMA1, non-solid LZMA2 and solid LZMA2 were read through the new reader. Every
  regular member's decoded bytes matched the existing reader.
- A gzip payload that was not TAR was refused when presented as a `.tgz` file.

The current profile supports ZIP, TAR/TAR.GZ and 7z with single-codec Copy,
Deflate, LZMA or LZMA2 folders, including solid folders. The 7z reader uses a
maximum 64 MiB dictionary and a 16 MiB metadata budget. Filtered or multi-stream
7z codec chains and protected archives return an unsupported-profile result so
small inputs can retain the existing bounded workflow. An unsupported profile
is not permission to load a large source into memory.

7z solid folders are decoded from their start for each requested member; memory
does not scale with the folder's expanded size, but repeatedly reading many
members from the same solid folder can repeat substantial decompression work.

## Workspace integration coverage authored

`test/archive_streamed_workspace_test.dart` contains native filesystem
regressions for:

- ZIP, 7z, TAR and TAR.GZ: open, capture an imported file, preserve that snapshot
  after the external input changes, rename a directory, remove a member, create
  an empty directory, replace a member, review, save and reopen.
- Stream-backed review ownership: buffered `review.bytes` is unavailable,
  streamed digest matches the review digest, the published file matches that
  digest, stale review spools retire, and workspace close disposes its spool.
- Password-required and wrong-password behavior for small encrypted ZIP and
  7z, followed by the bounded password-preserving save workflow.
- Refusal to replace an externally changed original, with the reviewed draft
  and externally written file retained.
- Cancelled review/save before publication, retry, and continued reading after
  the cancellation callback of an already completed save later returns true.
- An opt-in TAR.GZ test that generates a member larger than 2 GiB, opens it,
  refuses a buffered editor read, renames it, reviews, publishes, reopens and
  streams every decoded byte.

These Flutter regression tests were authored and statically analyzed only in
this session. The environment's automatic approval review rejected Flutter
test execution because of a possible metadata-service request. No additional
Flutter test command, request to that service, or workaround was attempted.
Flutter runtime validation remains outstanding.

## Reproduction

Use the repository's already resolved package configuration and a native Dart
SDK. The standalone probes have no Flutter runtime or network requirement:

```sh
dart --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streamed_reader.dart \
  /path/to/koni_sevenz-0.9.0/test/fixtures/sevenz

dart --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streamed_large_reader.dart \
  /path/to/large.zip
```

Repeat the second command for `large.tgz` and `large.7z` generated by the
companion writer probe. The large reader probe expects precisely the fixture
described above. Set `TMPDIR` to an existing writable directory if the runtime
does not supply a usable system temporary directory.

Generate, read and independently verify the actual stored containers with:

```sh
dart --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streamed_large_container.dart zip --oracle

dart --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streamed_large_container.dart 7z --oracle
```

The `--oracle` option requires Python 3 and system `libarchive` for the 7z case;
these are verification dependencies only. The sparse allocation measurement
uses Linux file statistics. Without `--oracle`, the probe still runs the
production writer, spool and complete production reader verification.

In a normal Flutter development environment, run the new workspace tests with:

```sh
flutter test --no-pub test/archive_streamed_workspace_test.dart
```

The expensive workspace regression is disabled by default. Enable it with
`CRISP_RUN_LARGE_ARCHIVE_TESTS=1`, allow up to 20 minutes, and provide temporary
storage for the original, staged and decoded representations. Sparse support
reduces allocation for this zero-filled fixture but must not be assumed for
ordinary user files.
