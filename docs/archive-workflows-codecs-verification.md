# Archive workflows and codec verification

Date: 12 November 2026. Implementation commit:
[`f273250199f7b2f1820ded5ed023f5c43f6435c4`](https://github.com/CrispStrobe/CrispCloud/commit/f273250199f7b2f1820ded5ed023f5c43f6435c4).
Baseline: `e103d8c6fd6dc8c8c3d73467a8a1eb15fb8471d4` (PR #90).
Review: [draft PR #92](https://github.com/CrispStrobe/CrispCloud/pull/92).

## Observed gates

| Gate | Observed result |
| --- | --- |
| Complete archive/viewer and affected file-operation regression | **1,636 tests passed across 66 files** |
| Static analysis | **All 55 changed Dart files clean**, `dart analyze --fatal-infos` |
| Formatting and whitespace | Changed Dart files formatted; `git diff --check` clean |
| Standard Flutter release web build | **Passed**, `flutter build web --release --no-pub --no-wasm-dry-run` |
| LZ4 fresh writer output | Independent liblz4 exact readback passed for 8 outputs, compressed and stored modes |
| LZMA-alone fresh writer output | Independent liblzma exact readback passed for 4 outputs, including empty data |
| Original LZ4/LZMA/Lzip fixtures | Native recheck passed all 13 fixtures / 17 size-mode checks |
| UNIX compress | Exact native ncompress/gzip comparisons, 9–16-bit growth/reset cases and documented reference-tool exceptions |
| Binary CPIO | libarchive exact content/name/mode/time readback passed in both byte orders |
| Lzip/UNIX-compress wrapped TAR fixtures | Exact independent 10,240-byte decoded TAR comparisons passed |
| Portable runtime | All four new codecs compiled with Dart2JS and passed actual Node runtime checks |

The full regression includes the new integrity, copy, codec, binary CPIO,
dispatch and creation tests together with existing archive editing, recovery,
disk creation, nested browsing and file-operation behavior. The standalone
new-codec tests include malformed/truncated streams, unsupported headers,
dictionary limits, output bounds and independent reference content.

Focused results are subsets of the full regression, not additional counts:

- 40 compression-shape tests cover all six writable compressors, recursive
  layers, misleading suffixes, read-only/skippable wrappers around 7z, LZMA
  name hints, TAR preservation, depth/output bounds and unchanged source bytes.
- 29 direct archive-copy service tests cover cross-format copies, recursive and
  empty directories, conflict rules, metadata, separate passwords, stale or
  changed sources, physical aliases and late publication failures. Four
  related service suites passed 105 tests during focused validation.
- 31 copy UI/action/localization checks cover captured pane routes, borrowed
  unlocked workspaces, dirty drafts, move refusal and narrow translated UI.
- 19 integrity service tests and 13 integrity widget tests cover checked,
  failed, skipped, unprocessed and cancelled results, namespace safety,
  password behavior, stale handles, streamed SHA-256 and narrow layouts.
- 42 TAR writer tests include LZ4/LZMA output with full inspected member and
  container metadata plus exact payload comparison after repacking.
- 65 registry tests and 29 creation-dialog tests cover the 28-choice picker,
  extension/MIME routing, format-specific controls and translated layouts.

## Integration issues found and fixed

Independent review found two ways a reader's inner view could previously be
mistaken for a writable outer stream. The policy now requires an immediate
decoded payload for single-file replacement and a physical raw 7z signature for
the 7z writer. Nested same-codec streams and read-only or skippable wrappers
therefore cannot disappear during save. The 40-case shape suite verifies these
boundaries across existing and new compressors.

The first full regression exposed a CPIO compatibility regression from treating
newc and CRC as different header layouts, and an exhaustive TAR test switch
missing the two new enum cases. The CPIO reader now groups the compatible
newc/CRC layout while preserving each record's checksum behavior. The TAR tests
exercise both new formats and pass the explicit filename hint needed for
signatureless LZMA-alone. All existing preservation assertions remain. The
complete 66-file gate was rerun successfully after these fixes.

## Environment and reproducibility

Validation used the repository-pinned **Flutter 3.47.8 / Dart 3.13.7** on Linux
with its existing dependency lockfile. No application dependency or lockfile was
changed. The existing MIT `archive` / `koni_codecs` public primitives are reused
where described in the codec provenance documents; no subprocess or native
library is needed by the new application codecs.

The local validation wrapper temporarily disabled the unrelated optional native
ebook conversion engine and selected system SQLite **3.46.1** for the existing
native test hook. It restored `pubspec.yaml` byte-for-byte after each command.
These local validation settings are not committed. Existing cached SMB/native
test dependencies were used. This does not establish the optional ebook
engine's own build or runtime behavior.

The exact regression file set is the archive service/widget globs plus the
affected viewers and file operations:

```sh
flutter test --no-pub --concurrency=4 --reporter expanded \
  test/archive*_test.dart test/widget/archive*_test.dart \
  test/internal_viewer_test.dart test/panel_source_test.dart \
  test/viewer_search_service_test.dart test/viewer_streaming_service_test.dart \
  test/viewer_spool_lifecycle_test.dart test/file_operation_service_test.dart \
  test/file_clipboard_test.dart test/widget/internal_viewer_widget_test.dart \
  test/widget/internal_viewer_localization_test.dart \
  test/widget/file_operation_dialog_test.dart \
  test/widget/file_operations_localization_test.dart \
  test/widget/screen_dialog_localization_test.dart

flutter build web --release --no-pub --no-wasm-dry-run
```

Analysis covered every Dart file changed from the stated baseline, including
the four portable verification entry points under `test/support`. The web build
is the standard JavaScript release target; Wasm acceptance is not claimed.

Native reference versions were **liblz4 1.10.0**, **liblzma 5.8.1**,
**libarchive 3.7.4**, **libxxhash 0.8.3**, **GNU gzip 1.13**, **ncompress 5.1**
and **Python 3.12.14**. Portable checks used **Node.js 24.22.1**. These are
validation tools, not app dependencies.

## Independent fixtures and portability

All payloads are original deterministic test data. The fixture documents record
generation commands, primary format references and SHA-256 identities:

- [LZ4](../test/fixtures/archives/LZ4-REFERENCE.md): liblz4 frames with linked
  and independent blocks, optional checksum combinations, stored blocks and
  empty data; fresh writer output is checked by liblz4 in the test suite.
- [LZMA-alone](../test/fixtures/archives/LZMA-REFERENCE.md): liblzma streams with
  alternate properties, long distances and end markers; fresh writer output
  uses the valid known-size/no-marker profile and is independently decoded.
- [Lzip](../test/fixtures/archives/LZIP-REFERENCE.md): libarchive-generated v1
  frames checked with liblzma plus independently calculated CRC32 and sizes.
- [UNIX compress](../test/fixtures/archives/UNIX_COMPRESS_REFERENCE.md): real
  libarchive and ncompress output, plus original literal-code fixtures checked
  by independent tools. The document records libarchive's empty-raw-output
  behavior and GNU gzip's fixed-nine-bit limitation; neither is copied into
  the application behavior.
- [Binary CPIO](../test/fixtures/archives/CPIO_BINARY.md): libarchive-generated
  modern binary records in both byte orders, including an odd-length file,
  empty file and 65,869-byte high-word-order case.

The original wrapped-TAR generator is
`test/support/generate_archive_codec_containers.py --check-only`. Python emits
the USTAR tree, libarchive emits the Lzip/UNIX-compress wrappers, and independent
liblzma/zlib or GNU gzip decoding must reproduce all 10,240 TAR bytes.

| Fixture | SHA-256 |
| --- | --- |
| `codec-container.tar.lz` | `cbcf39eff4af56e9d2ded83233c062a6154f4998bdc6e5ee87b709a003fe0af0` |
| `codec-container.tar.Z` | `70e55ce77eed7c5fc4395a2b224f7a605e1e8fab144a72cf18149b7bea327cc8` |

Each `test/support/verify_archive_*_portable.dart` entry point was compiled with
`dart compile js` and executed by Node. These checks exercise real decoding and
bounds, not just import compatibility. LZ4 additionally checks writer round
trips; LZMA/Lzip use independent fixture data. UNIX compress checks the exact
426,000-byte 16-bit dictionary-growth/reset fixture, fixed nine-bit saturation,
invalid flags/codes, empty streams and output bounds.

## Operational and integrity boundaries

Archive-to-archive copying stages a verified snapshot and preserves the source.
It captures each source workspace revision and physical outer identity, checks
source bytes before staging and again before final destination checks and
installation, and rejects the same physical outer container including native
hard-link aliases. The destination keeps its own supported password protection.
Ownership, ACLs, resource forks, links and signatures are not imported;
setuid/setgid inputs are refused. Supported modes/times and empty directories
are preserved. Source guards/passwords are transient; reviewed journal recovery
acts on the verified destination candidate and never deletes the source.

Independent source and destination storage cannot provide an atomic shared
snapshot. A source change after the last check does not alter the already
verified copied bytes. The journal protects destination publication according
to its existing backend contract. Two-container moves require a separate
transaction and remain unavailable.

Integrity reports cover readability, available format checks and newly computed
SHA-256 values. They do not authenticate a publisher or prove original contents
without an expected digest. LZMA-alone and UNIX compress have no stored payload
checksum; LZ4 checksums are optional on incoming files. Skipped, unsafe, special,
password-locked, over-budget and unprocessed members remain explicit. Cancellation
is cooperative between reads/chunks; a bounded buffered decoder may finish its
current decode first. No repair or resumable background job is introduced.

Interactive edits retain 64 MiB per-member and 256 MiB container/aggregate
limits. New buffered codecs cap both compressed input and decoded output at
64 MiB and recursive decompression at four layers. Metadata/header overhead
counts against relevant output limits. The prior 2 GiB fresh native image
creation path is separate and is not an increase to these limits.

Native macOS mounting, six-platform release acceptance, remote/browser
publication contracts and live backend/provider behavior are not established
by these Linux tests and the web compilation. The format matrix and endpoint
policy describe supported profiles; individual unsupported metadata can still
make an otherwise supported format read-only.

## Ideas-only reference

VaultExplorer review was restricted to its README, release descriptions and
high-level product documentation. No implementation source, tests, assets or
dependencies from that GPL project were read, copied or imported. Its product
ideas informed explicit verification and consistent container operations;
CrispCloud's copy and integrity implementations use its own reader/workspace/
publication architecture. The [continuation record](archive-workflows-codecs-continuation.md)
records the inspected README identity and what remains separate work.
