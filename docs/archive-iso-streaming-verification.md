# Native streamed ISO rewrite verification

This records direct Dart verification of the native ISO reader, strict rewrite
inspector, writer and output spool. The final probe was executed with Dart
3.13.7 on Linux, followed by a full read using the installed system libarchive.
It establishes a complete codec rewrite of an ISO larger than 2 GiB. It does
not establish that the Flutter workspace, UI or publication tests have run.

## Profile and bounds

`inspectIsoRewriteSource` inspects an immutable `ByteSource` without collecting
the image or reading retained file payloads. The caller retains ownership of
that source. Native streaming callers may request up to **8 GiB** for both
input and candidate images. `writeIsoArchive` writes to an asynchronous sink;
its existing 2 GiB default remains for callers that do not explicitly opt in
to the larger bound.

The writable profile remains a data-only ISO 9660 image, with its supported
Rock Ridge and Joliet metadata. Boot records, nonzero system areas, hybrid
images, UDF, unmodeled descriptors or application metadata, ambiguous alternate
hierarchies, links, special files, interleaving and multiple extents remain
outside that profile. Rewriting is refused when inspection cannot account for
all content and metadata. Unclaimed gaps and trailing bytes are checked in
bounded chunks, so data beyond the declared volume is not silently discarded.

The aggregate image budget is independent of the ISO directory record's
32-bit single-extent file length. **One member may contain at most
4,294,967,295 bytes (4 GiB minus one byte)**; larger individual files require
multi-extent support, which this profile does not claim. Headers, path tables,
directories and alignment count toward the total image budget.

The returned viewer advertises the streaming member budget. Buffered member
reads retain their smaller existing limit, preventing a large member from
being collected just because it can be streamed.

## Executed rewrite and independent read

`test/support/verify_archive_streamed_iso.dart --large --oracle` creates an ISO
in the production `ArchiveOutputSpool`, opens and inspects it, rewrites it to a
second production spool, reopens and inspects the candidate, and consumes its
complete large member. The fixture starts with `large.bin`, `remove.txt` and
an empty directory. The rewrite moves and renames the large file to
`folder/renamed.bin`, adds `added.txt`, removes `remove.txt` and retains the
empty directory. Size, content, modification times and permission modes are
checked after the rewrite.

The final run passed with these measurements:

| Measurement | Observed value |
| --- | ---: |
| Large member length | 2,147,483,665 bytes (2 GiB + 17) |
| Original ISO length | 2,147,543,040 bytes |
| Replacement ISO length | 2,147,547,136 bytes |
| Initial creation | 18,356 ms |
| Rewrite | 22,991 ms |
| Complete production reader payload check | 15,275 ms |
| Largest writer chunk | 262,144 bytes |
| Largest reader chunk | 262,144 bytes |
| Independent oracle copy's allocated blocks | 262,144 bytes |

The probe exports the exact candidate spool stream to a sparse file for
`test/support/check_archive_streamed_iso.py`. That independent checker uses
libarchive's ISO reader, checks namespace and metadata, reads all
**2,147,483,665 bytes** of the renamed member, checks every byte is zero, and
computes this SHA-256:

```text
d9378e43c0e666027848e63668ba0a821b4726843e366626946e3823b477299e
```

It also checks the five-byte added file and reports 2,147,483,670 total file
payload bytes. Its added-file SHA-256 is
`279b8a60f444fa8b6275687ce7e44363d97f72f88e4a3285baf0d9ed812e4061`.

The archive is larger than 2 GiB in logical file length. Sparse zero runs explain
the much smaller allocated-block count (`st_blocks * 512` on this filesystem).
The check exercises large offsets, extents, lengths, metadata and complete
payload reads; it does not claim that more than 2 GiB of physical disk blocks
were allocated or that an app destination was published. Ordinary user content
can require storage proportional to the full image size. Both production
spools and the independent oracle copy are removed when the probe finishes.
Timings are observations from one concurrent development session, not
performance or mobile resource guarantees. No RSS measurement was recorded.

## Auxiliary metadata proof

`verifyIsoRewritePreservation` derives the expected candidate metadata from the
same writer plan used for the retained source. In addition to the workspace's
ordinary namespace, size, time, mode and payload checks, it compares primary
and Joliet volume metadata, root metadata and per-entry attributes. These
include UID/GID, calculated link counts, serial values, flags, directory dates,
Rock Ridge time records, names and alternate hierarchy metadata. Intentional
name, mode and modification-time edits remain supported.

The standalone probe first uses an independently constructed small ISO fixture
with UID/GID 1000, a long Unicode rename containing a supplementary-plane
character, and intentional mode and modification-time changes. The generated
candidate passes the proof. Altered ownership, flags, serial values, time
records and Joliet metadata are each rejected. The proof receives payload
callbacks that throw if called, establishing that it does not reread member
content. This small check and the complete large rewrite both passed with the
helper enabled.

## Authored regression coverage

`test/archive_iso_streamed_test.dart` adds regression cases for source-backed
and buffered inspection agreement, a virtual image and member over 2 GiB,
bounded metadata reads, large buffered-read refusal, the old 2 GiB inspection
bound, nonzero high-offset trailing data, boot/hybrid/UDF/application guards,
cancellation and borrowed-source ownership, truncated reads, planning before
payload reads, the per-member and aggregate limits, and auxiliary metadata
proofs including altered volume and root fields.

These tests and the ISO reader, writer and standalone probe passed direct Dart
static analysis with no issues. `git diff --check` passed for the owned ISO
files. The Flutter regression file was **not run locally**: the environment's
automatic approval review had previously rejected Flutter test execution over
a possible metadata-service request. Hosted CI remains the runtime gate for
the Flutter tests. No additional Flutter launch or metadata-service request
was made for this ISO verification.

## Reproduction

Use the repository's resolved package configuration with a native Dart SDK:

```sh
dart --packages=.dart_tool/package_config.json \
  test/support/verify_archive_streamed_iso.dart --large --oracle
```

Without `--large`, the same operations use a 1 MiB + 17 byte member. Without
`--oracle`, the production writer, source inspector, metadata proof and full
production reader still run; independent Python verification is omitted.
The oracle requires Python 3 and a system libarchive with ISO support. These
are verification dependencies, not application requirements. Set `TMPDIR` to
an existing writable location when the environment has no usable system
temporary directory. Allow room for both spools and the optional oracle copy;
sparse allocation must not be assumed on every filesystem.
