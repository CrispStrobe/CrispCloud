# Create archives

Select local files or folders, open the context menu and choose **Create
archive…**. The dialog captures the selection and the original parent folder
before review. It shows the destination, archive name, format and available
compression choices. Choose a new name if an output already exists. The picker
has **33 explicit choices**; the [format matrix](archive-format-coverage.md)
separates creation from reading and editing existing containers.

| Format | Compression choices | Password protection |
| --- | --- | --- |
| ZIP / CBZ | Store, Fast (1), Normal (6), Maximum (9) | AES-256 for file contents; filenames remain visible |
| 7z / CB7 | Store, Deflate, LZMA2 | AES-256, with an optional encrypted header to hide filenames |
| TAR / CBT | Store | Unavailable |
| TAR.GZ / gzip | Store (0), Fast (1), Normal (6), Maximum (9) | Unavailable |
| TAR.BZ2 / TAR.XZ / TAR.ZST / TAR.LZMA; bzip2 / XZ / Zstandard / LZMA-alone | Fast, Normal, Maximum | Unavailable |
| TAR.LZ4 / LZ4 | Store, Normal | Unavailable |
| TAR.Z / UNIX compress | Fast (12-bit), Normal (14-bit), Maximum (16-bit dictionary) | Unavailable |
| AR | Store; flat regular files | Unavailable |
| CPIO newc / odc / binary LE / binary BE | Store; four distinct creation profiles | Unavailable |
| XAR | Normal | Unavailable |
| JAR / WAR / EAR / KMZ | Store, Fast, Normal, Maximum | Unavailable; Java packages must be unsigned |
| ISO / HFSX data image | Store | Unavailable |
| DMG (HFSX data volume) | Store, Normal | Unavailable |

ZIP and GZIP levels are passed to the existing codec. The 7z writer exposes
compression methods, so its choices name those methods instead of promising
numeric levels it cannot implement. TAR.GZ with Store still has a GZIP wrapper.
Password fields require matching confirmation and are cleared after an attempted
operation. Passwords are not persisted in settings, operation logs or history.

Single-file compression choices take exactly one regular file; its decompressed
name comes from the output filename. AR takes flat regular files. KMZ requires
a top-level KML document. The picker explains codec-specific dictionary and
checksum limits and clears password fields when switching to a format without
protection support.

UNIX compress creates one `.Z` payload or a `.tar.Z` tree with real block-mode
LZW compression. Full dictionaries reset when another phrase must be added.
The three settings bound the dictionary; a larger dictionary does not guarantee
a smaller file for every input. Neither Store nor password protection is
available. The format stores no payload checksum or decoded length; verification
of newly created output compares its complete decoded bytes with the captured
source. Existing eligible streams are rewritten using the normal 14-bit profile.
See the [independent writer profile evidence](../test/fixtures/archives/UNIX_COMPRESS_WRITER_PROFILES.md).

CPIO defaults to newc. Select odc or binary LE/BE explicitly when compatibility
requires the older layout. All four use `.cpio`; the selected profile controls
the physical header. Legacy CPIO has no encryption or stored payload checksum.
Names, timestamps, sizes and metadata must fit the profile's fields; overflow
fails before publication. Fresh creation captures supported times/permissions
and uses default ownership, while eligible existing-container rewrites preserve
the inspected original metadata and profile. See the
[CPIO profile contract](../test/fixtures/archives/CPIO_WRITER_PROFILES.md).

Folders retain their hierarchy and empty subfolders. Overlapping parent/child
selections are included once. Selected items with colliding archive names,
symbolic links, unsupported filesystem entries or unsafe member paths stop the
operation. The destination must be outside selected folders.

The workflow uses the existing native local backend and its access scopes.
Source metadata is checked during traversal and reads; source contents are
hashed and checked again before publication. Changes to selected folders or
their children also invalidate the operation. The created archive is decoded
and every file is compared with the recorded source hash. Requested encryption
is verified on nonempty file entries. A temporary output is then checked byte
for byte and committed through the backend's exclusive, no-overwrite operation.
Switching panes cannot redirect a captured source or destination.

Progress covers scanning, packing, verification and saving. Cancel prevents
publication at the next cancellation check; a codec may need to finish its
current block first. A commit that already completed is reported as successful.
Keep the dialog open until it reports completion or cancellation.

Ordinary archive creation is bounded to 64 MiB per source file, 256 MiB of total
source content and packed output, 200,000 entries, 200 folder levels and 8 MiB
of member-path text. Format headers also count toward packed limits. All
compressed TAR choices have a 64 MiB decoded TAR limit, including headers.
Single-file compressors and compressed TAR also cap encoded output at 64 MiB.
Fresh native ISO/HFSX/DMG creation has a separate streamed 2 GiB image-output
bound; it does not increase existing-container editing limits. HFSX/DMG are
data volumes without copied resource forks, extended attributes or symlinks.
Fresh native uncompressed TAR/CBT creation also has a streamed **2 GiB packed
output limit**, including headers, extended names, alignment and the trailer.
It accepts regular files larger than 64 MiB and source totals above 256 MiB
when the complete output fits. Both captured endpoints must provide bounded
native-local reads; the destination must also provide bounded, verified staged
writes. Other TAR compression choices,
browser/fallback creation and existing TAR editing retain their ordinary limits.
The format picker displays the larger bound only for eligible TAR/CBT endpoints.

The TAR path streams source reads, temporary output, decoded member checks and
destination readback. Packing, verification and saving report byte progress;
verification includes another complete source read, and saving includes staged
readback and a final source check. These phases deliberately perform more I/O
than the final archive size. Cancellation is checked between bounded chunks and
the event loop yields during large loops. TAR has no stored payload checksum;
creation verifies every member against the captured source SHA-256. Temporary
output and destination staging require additional disk space. Disk exhaustion,
source changes and late output collisions must fail without replacing an
existing destination. The [large TAR verification record](archive-sync-large-tar-verification.md)
distinguishes actual measured fixtures from the configured upper bound.

Large durable background jobs remain separate work. The current creation entry
point accepts native local selections. Other archive browsing and editing
workflows are described in [file operations](commander-file-operations.md).

## Validation

`test/archive_creation_service_test.dart` covers format roundtrips, Unicode and
empty entries, real compression choices, encrypted content and headers, wrong
passwords, source replacement, added children, output collisions, cancellation,
account loss, traversal and resource limits.
`test/widget/archive_creation_dialog_test.dart` covers format transitions,
password confirmation, invalid filenames and all eight translated narrow layouts.
`test/archive_cpio_creation_test.dart` checks the actual selected physical CPIO
layout and refusal of encryption or unrepresentable timestamps before output.
`test/archive_cpio_writer_profiles_test.dart` and the native reference emitter/
checker cover preserved profiles and exact metadata/content readback.
UNIX compress writer/workflow tests cover physical settings, independent input
profiles and wrapper preservation; gzip/libarchive readback and actual Node
execution independently check the produced streams.
`test/archive_large_tar_creation_test.dart` exercises real native files above
the former member and aggregate limits, header-inclusive preflight, bounded
readback, phase progress, cancellation, source mutation and late collisions.
Its optional reference output is checked by Python's TAR reader and GNU tar
using `test/support/check_archive_large_tar.py`.
These tests are evidence only when run against the branch being reviewed.
