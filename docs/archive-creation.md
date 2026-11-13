# Create archives

Select local files or folders, open the context menu and choose **Create
archive…**. The dialog captures the selection and the original parent folder
before review. It shows the destination, archive name, format and available
compression choices. Choose a new name if an output already exists. The picker
has **35 explicit choices**; the [format matrix](archive-format-coverage.md)
separates creation from reading and editing existing containers.

| Format | Compression choices | Password protection |
| --- | --- | --- |
| ZIP / CBZ | Store, Fast (1), Normal (6), Maximum (9) | AES-256 for file contents; filenames remain visible |
| 7z / CB7 | Store, Deflate, LZMA2 | AES-256, with an optional encrypted header to hide filenames |
| RAR / CBR | RAR5 Store, without compression | Unavailable |
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
RAR5 Store is an independent implementation of the public container format.
It writes files without proprietary RAR compression and does not bundle an
external packer. It checks CRC-32 and SHA-256 across two captured source passes
before accepting each output payload. Compressed/encrypted RAR archives remain
on the existing read-only path. The separate **Use installed packer…** workflow
can create verified compressed RAR5 outputs with a checked, user-installed RAR
tool. It does not change the policy for editing existing compressed RAR files.

Password fields require matching confirmation and are cleared after an attempted
operation. Passwords are not persisted in settings, operation logs or history.
The installed-packer action is unavailable while password protection is selected;
its initial profiles create unencrypted outputs only.

On native desktop, **Start** keeps the progress dialog attached to a job in the
shared Operations queue. **Queue in background** saves the job and returns to
the file manager; **Run in background** detaches an already running dialog.
**Archive jobs** in Tools opens the same Operations panel and history used by
normal transfers. Pause/resume, stop, priority, ordering and scheduling follow
the [shared archive queue contract](archive-operation-queue.md). Protected
creation recipes require their password again after an application restart.

**One archive per selected item** previews a separate output for each selection.
All output names are checked first, and live dispatch waits until every job is
durably saved. History records are saved individually: a failed append or
interruption may leave a partial batch for review without starting its jobs.
Source files are retained and each admitted output has its own result. The
[Commander workflow guide](archive-commander-workflows.md) also describes checked
installed packers and their separate compression options.

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
For foreground creation, keep the dialog open until it reports completion or
cancellation. Queued work continues independently of the dialog.

Eligible native local **ZIP/CBZ, 7z/CB7, RAR5 Store/CBR and TAR.GZ/TGZ creation streams up to
8 GiB** per source file, total source content and packed output. For TGZ the
decoded TAR, including its headers and padding, must also fit 8 GiB. The large
7z path supports Store and LZMA2; choosing Deflate or password protection uses
the existing buffered path. ZIP encryption also uses that smaller path. The
dialog displays the applicable limit for the captured endpoints and options.

Buffered archive creation remains bounded to 64 MiB per source file and
256 MiB of total source content and packed output. Buffered compressed TAR
choices have a 64 MiB decoded TAR limit, including headers; single-file
compressors and buffered compressed TAR also cap encoded output at 64 MiB.
All creation paths retain entry, path and depth bounds: at most 200,000 entries,
200 folder levels and 8 MiB of member-path text, with format-specific metadata
limits where smaller. Format headers count toward packed limits.
Fresh ISO/HFSX/DMG creation on bounded native local storage streams within an
**8 GiB image-output budget**. ISO uses single-extent files, each smaller than
4 GiB. HFSX/DMG data volumes have an 8 GiB decoded budget including filesystem
metadata and free space; UDIF zero runs may keep a sparse DMG physically small
even with Store selected. Other creation backends retain the 2 GiB image bound.
HFSX/DMG creation does not copy resource forks, extended attributes or symlinks.
Eligible existing data ISO and verified canonical HFSX data-volume DMG images
now use streamed reviewed editing, with their preservation checks described in
[the ISO/RAR/DMG continuation](archive-iso-rar-dmg.md).
Fresh native uncompressed TAR/CBT creation also has a streamed **2 GiB packed
output limit**, including headers, extended names, alignment and the trailer.
It accepts regular files larger than 64 MiB and source totals above 256 MiB
when the complete output fits. Both captured endpoints must provide bounded
native-local reads; the destination must also provide bounded, verified staged
writes. Existing eligible native TAR/CBT workspaces use the separate 8 GiB
streamed editing path. Browser/fallback creation and other TAR compression
choices retain their ordinary limits. The format picker shows the larger limits
only when the captured endpoints and chosen options support them.

The native streaming paths stream source reads, temporary output, decoded member checks and
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

ZIP, TGZ and 7z have each processed a member larger than 2 GiB through the
standalone writer and independent readers. ZIP64 has also processed a member
larger than 4 GiB and an archive with 65,536 entries. The original compressed
fixtures are physically small. A completed hosted application gate now also
creates and publishes actual ZIP, 7z and TGZ containers above 2 GiB and edits
and republishes a TGZ containing a member above 2 GiB. None of these fixtures
qualifies the complete 8 GiB ceiling. See the
[writer evidence](archive-streaming-codec-verification.md),
[reader evidence](archive-streaming-reader-verification.md),
[completed hosted gate](archive-containers-runtime-verification.md) and
[ISO/RAR/DMG evidence](archive-iso-rar-dmg.md).

Native background creation and workspace saves use the shared operation queue
and cooperative writer bridge within the existing format bounds. The
[queue qualification](archive-operation-queue.md) separately records three
logical worker payloads above 2 GiB; those results remain attributed to their
tested source revision. The merged Commander continuation awaits its final
regression gate. Larger protected/nested profiles and broader device acceptance
remain separate work. The creation entry point accepts native local selections;
other archive browsing and editing workflows are described in
[file operations](commander-file-operations.md).

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
`test/archive_streamed_creation_test.dart` covers the new native ZIP, default
7z LZMA2 and TGZ creation paths, metadata, cancellation and source/output changes.
These Flutter suites now have a completed hosted regression result at
`f1a03e807b1261361a17f66a37fa94858481e1e7`: 1,856 archive tests passed, with ten
large opt-ins skipped in that normal run. The dedicated ISO, RAR5 Store and DMG
creation/editing/publication cases above 2 GiB also passed, as did the separate
large RAR creation case. All five common-format large cases passed again on
the integrated candidate. The complete workflow finished with ten successful
jobs: the normal suite and nine separately enabled large cases. Each large
case passed with zero failures or skips. Exact tested revisions, completed
receipts and hashes are in
[hosted runtime verification](archive-containers-runtime-verification.md).
Direct codec and independent Python/libarchive checks remain separate evidence.
