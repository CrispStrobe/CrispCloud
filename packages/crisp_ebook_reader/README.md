# CrispCloud ebook reader

An offline reader and normalized-import adapter. The Flutter application owns
file access, cloud credentials, edits, annotations, external links, and saves.
The reader receives book bytes and exposes a small command/event bridge.

## Scope and hosts

| Format or platform | Behavior |
| --- | --- |
| EPUB 2/3 | Reflowable and fixed-layout reading, navigation, search, progress, highlights, and normalized export. |
| MOBI, AZW, AZW3 | Unencrypted MOBI/KF8 reading and normalized export for creating an editable EPUB copy. |
| FB2, FBZ, CBZ | Reading and normalized export; comic pages retain fixed-layout viewport dimensions. |
| Android, iOS, macOS, Windows | `flutter_inappwebview` renders bundled assets served from an instance-scoped loopback server. The platform's WebView runtime must be available. |
| Browser | A same-origin Flutter asset iframe, with a session-scoped message bridge. |
| Linux | Optional inline WebKitGTK 4.1 texture host, selected after `probeEbookLinuxHost()`. Missing build/runtime support leaves the portable Flutter EPUB reader available. See [Linux packaging and verification](../../linux/README.md). |

DRM and KFX are outside this package's support. EPUB font obfuscation recognized
by foliate-js is distinct from unsupported encryption. PDFs remain handled by
CrispCloud's existing PDF viewer. Native platform builds and device behavior
require their own smoke checks; a passing JavaScript suite is not a six-platform
certification.

Use `CrispEbookReader` with `CrispEbookController`. Controller commands cover
navigation, percentage seeking, real Back/Forward history, appearance, search,
highlighting, and `exportPublication()`. `EbookBookInfo` reports meaningful
per-publication capabilities. Appearance includes publisher styles, maximum
columns, margins and column width; fixed-layout content keeps its geometry.
`EbookNavigationHistory` exposes the current session's Back/Forward availability,
not a serializable history stack.
Persist `EbookLocation` and highlights in the host, bound to the precise file
version. An edited book can invalidate CFIs; the reader never rewrites the source
archive to store appearance or personal notes.

The normalized export is a **new publication**, with rewritten resource paths
and only supported offline structures. For an existing EPUB, use `crisp_ebook`
to preserve and edit its original archive. Do not replace the original EPUB or
Kindle file with a normalized export implicitly.

Kindle addressing attributes (`aid`, `filepos`, `recindex`, `mediarecindex`)
are consumed only after links and resources have been resolved. The converted
copy omits those format-specific fields, moves misplaced legacy head metadata
back into the XHTML head, and supplies missing chapter titles. Namespace-aware
serialization preserves EPUB attributes and SVG namespaces without duplicating
the default XHTML namespace. These are targeted Kindle/serialization changes;
the importer does not discard unknown attributes through a blanket schema filter.

## Security boundary

Publication frames allow same-origin DOM inspection but **do not allow scripts**.
Both renderer implementations retain that sandbox independently of the sanitizer
and content security policy. Active document elements, event handlers, remote
resources and unsafe CSS are removed from the display/import representation.
The original EPUB archive remains unchanged by display sanitation.

Only bundled reader assets are served from the native loopback endpoint. The
endpoint cannot read arbitrary files or proxy network requests. The web host
checks both message origin and exact frame source; all transports also check an
unpredictable per-reader session identifier. External links are reported to the
host, which decides whether to open them.

Input is capped at 128 MiB. ZIP inputs enforce 12,000 entries, 64 MiB per entry and
256 MiB expanded total, with actual decompressed-byte limits and CRC checks.
Normalized output is limited to 256 MiB and 12,000 resources. The runtime loads
no JavaScript, decompression worker or font from a CDN.

## Pinned sources and licenses

`UPSTREAM.json` records exact revisions, file hashes, archive hashes and notices.
The recovered vendored code was compared with the upstream source before those
records were written.

| Component | Exact source | License |
| --- | --- | --- |
| foliate-js | [78914aef4466eb960965702401634c2cb348e9b1](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1) | MIT |
| zip.js | `vendor/zip.js` from that foliate revision, whose lockfile records `@zip.js/zip.js` 2.8.22 | BSD-3-Clause |
| SJCL subset in zip.js | The bundled zip.js artifact above | BSD-2-Clause option of its dual license |
| fflate | [`fflate` 0.8.2, `package/esm/browser.js`](https://registry.npmjs.org/fflate/-/fflate-0.8.2.tgz), byte-for-byte | MIT |
| flutter_inappwebview | [6.1.5](https://pub.dev/packages/flutter_inappwebview/versions/6.1.5), pinned in `pubspec.yaml` | Apache-2.0 |

All bundled notices are in `assets/licenses/`. No Anx Reader application code or
Foliate desktop application code is vendored by this package. The Dart host and
reader adapter are CrispCloud integration code. The broader application's
license is separate from the dependency licenses listed here.

`patches/foliate.patch` records the complete changes against the pinned foliate
source:

- `view.js`: offline raw-DEFLATE fallback through fflate, archive limits,
  encrypted/duplicate-entry rejection, CRC and inflated-size checks.
- `epub.js`: explicit unsupported-encryption errors, SVG 2 resource `href`
  handling, and preservation of SVG/image fragments during blob substitution.
- `mobi.js`: encrypted-book rejection and declared text-size preflight.
- `paginator.js`, `fixed-layout.js`: script-disabled publication frame sandbox.

The original minimized fflate subset was replaced by the exact 0.8.2 browser ESM
distribution, which also supplies streaming `Inflate`. The integration uses its
synchronous/streaming APIs; worker-based APIs are not enabled. Reader sanitation,
normalization and UI bridge code live outside the upstream module directory.

To update the vendor, review an exact new revision, reapply and review these
patches, refresh notices and `UPSTREAM.json`, and run the checks below. Do not
refresh hashes merely to make a failing integrity check pass.

## Verification

From this package directory:

```sh
npm ci --ignore-scripts
python3 tool/check_vendor.py
npm run test:parser
CRISP_TEST_RAW_INFLATE_FALLBACK=1 npm run test:parser
CHROMIUM_PATH=/usr/bin/chromium npm run test:browser
flutter pub get
flutter test
```

`python3 tool/check_vendor.py --upstream /path/to/foliate-js` additionally verifies
the source revision and every original module hash. The JavaScript dependency
versions are pinned by `package-lock.json`; they are development tools only.

The parser suite exercises authored EPUB/FB2/CBZ fixtures, Unicode, nested TOC
groups, cross-chapter anchors, imported CSS, SVG 2 resources and fragments,
normalization, scripted-content sanitation and DRM rejection. It runs without a
layout engine. The browser suite additionally exercises actual frames, search,
navigation, themes, highlights and independent sandbox execution probes. Both
suites accept extra MOBI/AZW3 paths as arguments, including the fixtures generated
by `crisp_ebook_conversion`.

Fixtures in `test/browser/make_fixtures.py` are self-authored CC0/public-domain
test data. Generated books are temporary and are not downloaded from publishers.

During the 2026-11-12 recovery session, `npm run test:parser` passed. Running
`npm run test:browser` with `/usr/bin/chromium` stopped before a browser was
created because the execution environment denied `socket()` with
`Operation not permitted` in `process_singleton_posix.cc`. That result is an
environment limitation, not a passing renderer check. Run the browser suite in
CI or an ordinary development environment before claiming browser verification.

The forced fflate decompression variant, reader controller tests (8 tests),
`flutter analyze`, and the vendor integrity check also passed locally. Independent
foliate parsing of Kindling-generated AZW3, dual MOBI, legacy MOBI6 and
metadata-rewritten AZW3/MOBI verified Unicode, authors/title, images, cross-chapter
links and nested TOC targets. These are conversion/parser checks, not native
rendering checks. On Apple targets, explicitly exercise text selection and links
with the script-disabled publication sandbox during the device smoke test.

The conversion package's `tool/verify_import_chain.py` also exercises the actual
Foliate normalization → `EpubDocument.fromPublication` → save/reopen → EPUBCheck
pipeline. The source and AZW3, dual-MOBI and legacy-MOBI imported EPUBs passed
EPUBCheck 5.4.0 with zero errors and warnings. It verifies source hashes and the
payload hashes of unchanged non-XHTML resources, plus metadata, Unicode, nested
navigation and cross-chapter links. Its reproducible output is under
`packages/crisp_ebook_conversion/build/import-chain/`, including
`verification.json`, the imported EPUBs and separate EPUBCheck JSON reports.


### Shared controls and older browser features

The adapter preserves content nodes when applying appearance settings and
serializes host navigation commands. A lifecycle guard avoids calling the
paginator's public render method before its new iframe has a document/body or
after detachment. The browser harness retains uncaught errors with their stack
and last bridge command; it does not suppress the error gate.

`reader_compat.js` supplies the two grouping APIs required by the pinned EPUB
parser only when the host lacks them. Existing browser implementations are
preserved. The parser gate deliberately removes both APIs and also forces raw
DEFLATE fallback to exercise the actual publication load/export path on that
feature combination. This is targeted compatibility support, not a claim that
arbitrary old browser versions meet the full runtime requirement.

Run the combination with:

```sh
CRISP_TEST_GROUPING_FALLBACK=1 CRISP_TEST_RAW_INFLATE_FALLBACK=1 npm run test:parser
```
