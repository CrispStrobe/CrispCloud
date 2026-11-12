# Legacy Word parser development integration

The current continuation uses canonical standalone parser
`730812534e8dc045d6d97f600218228f05c51b97` through the guarded standalone
mirror. The existing Quds source remains
`74960237cea7c560f3db7ee96ca37641c4438567`; its engine/editor bytes are unchanged.
The Git dependency, path override, upstream metadata and all 823 managed Office
file hashes agree. The exact pins remain authoritative in
`packages/legacy_doc_parser/UPSTREAM.json` and
`tool/office_fidelity_manifest.json`.

This parser checkpoint recovers bounded native header/footer stories ending in
closed tables, with an explicit warning. It adds lossless per-page native raster
storage, 24 textbox table-context schema controls and four retained native
header/footer inputs. The independent Open XML SDK accepts all 196 required
outputs with zero errors. Native geometry disproved a proposed textbox-depth
reset, which was retracted before this integration; the counterexample remains
retained with the source artifacts. These validity and scoped geometry checks
do not establish universal Word pagination or editing fidelity.

CrispCloud now requires actual header/footer, note/comment and embedded-object
anchors before clearing the corresponding conversion-loss warnings. Unused
parts, unused definitions and references inside comment content remain
inventory evidence rather than proof of preservation. The
[conversion guide](legacy-word-conversion.md) records these bounds.

The [previous continuation receipt](evidence/legacy-doc-parser-continuation-20261112/README.md)
remains attributed to parser `ba5f5b0` and Quds `a9f7c1a`; it does not certify
this changed tree. The earlier evidence below likewise retains its original
source identity. This is a development checkpoint and does not requalify a
frozen release.

# Earlier development checkpoint

This development update merges app main
`467c4a3deb31e18e33e558d3c08b19f2ddc7231c` and adopts standalone
[`legacy_doc_parser` at `c8848d2b7323636d922ed211dfc911534f3acc9f`](https://github.com/CrispStrobe/legacy-doc-parser/tree/c8848d2b7323636d922ed211dfc911534f3acc9f),
version `0.1.0-dev.2`. It retains main's CrisperBooks extraction, FLAC correction,
stricter native Office bounds checks and interrupted-run evidence.

The earlier `v1.2.0` freeze at app `9a81d68c7cb27f35e4707267206ef6ea8e3de33d`
and parser `fa9abdb5c1436d46eba9c7a2a35ea13497f5ff20` remains a historical
snapshot. Its receipts are not relabeled as acceptance of this development
tree. No release version, distribution classification, France decision or
TestFlight setting is changed by this integration.

## Source and runtime boundary

The declared Git pin, `packages/legacy_doc_parser/UPSTREAM.json` and the
Office manifest's `standalone_sources` entry all identify the same parser
commit. The existing path override selects its exact local mirror: **187
tracked source files**, plus app-owned upstream metadata. Generated dependency
and test outputs are excluded from that source inventory. `pubspec.lock`
records the path dependency at `0.1.0-dev.2`.

The Office inventory verifies **605 files** in total. Its Quds source remains
main's exact `35230d3862fbfc268ac7b5fa2a243e9f6a347057`, with every non-parser
file hash unchanged from main. Parser files are attributed to their own
repository instead of that Quds snapshot. Future updates use the guarded
[standalone sync tool](../tool/sync_legacy_doc_parser.py); the
[integration guide](legacy-doc-parser.md) explains the dry-run and verification
commands. CrisperBooks retains its independent source guard and pin.

The package supplies richer numbering, nested and conditional table properties,
note layout, revision metadata, OfficeArt output and supported metafile
playback. CrispCloud keeps its captured source target, reviewed create-only
copy workflow, localized controls and explicit limitations. Native output and
portable preview have different support boundaries; source bytes retained as
evidence are not represented as an active editable feature.

## Actual images in the app preview

Both F3 and the side pane use the new Office-only HTML image factory. The core
HTML package's raster decoder cannot display SVG data. The factory sends
bounded generated SVG data to the existing `flutter_svg` renderer, retains the
image dimensions and accessibility label, and refuses external image URLs.
It adds no dependency or network fetch path.

The current Office `safeHtml` producers are the fixed-tag RTF renderer and the
standalone DOC/DOT renderer. DOCX/Quds extraction does not pass original SVG
through this path. HTML-file and email viewing use separate unchanged HTML
widgets. The package regenerates metafile SVG from supported binary EMF/WMF
records; it does not trust an arbitrary SVG string in public model metadata.

The package's image count, encoded-data, dimension and aggregate decoded-pixel
limits apply before image markup is emitted. Repeated raster references are
charged separately, and the budget is shared across main and auxiliary story
previews. Images beyond the budget receive a placeholder while native asset
bytes remain in the model. Cropped content is not exposed as a complete
uncropped image. Unsupported metafile operations have no guessed SVG preview.

## Evidence and remaining limits

The package's broader native comparison is recorded in its
[immutable measured-results report](https://github.com/CrispStrobe/legacy-doc-parser/blob/2d490e5490f7d549deb36573a5ac26fc5f875cfa/doc/fidelity-results.md).
That report identifies its own inputs, code, renderer, fonts, exact matches and
remaining differences. It is not a claim of universal Word pagination or
Microsoft Word execution. This app update does not alter any existing
`docs/evidence` release or interrupted-run record.

The local Word widget gates use the existing system-SQLite test helper and the
ebook conversion package's documented `enabled: false` hook setting. The exact
root manifest is restored afterward. These runs validate Word behavior with
optional native ebook conversion unavailable; they do not validate that native
ebook engine or establish a production-configuration LCOV collection receipt.

The source inventory additionally binds nine new parser runtime modules and
the Office SVG factory. Existing main inventory entries remain intact. Only
the three technical policy fingerprints are refreshed for the merged source,
inventory and lockfile; all policy decisions and their references remain as
recorded by main. That fingerprint refresh does not replace the existing
release-artifact and distribution gates.

## Validation of this development integration

The following gates passed on the merged app source and exact parser pin.
The standalone package suite ran before the final app-main reconciliation;
exact Git-tree verification confirms that the reconciliation changed none of
its 187 mirrored source files.

| Gate | Result and scope |
| --- | --- |
| App Word tests | **134 tests in 18 suites passed** after merging main, including conversion, captured targets, routing, package inspection, native-adapter behavior and localized UI. |
| Actual metafile painting | **Four EMF/WMF cases passed** through the DOC parser into F3 and the side pane. Pixel assertions verify rendered color; two additional image-factory cases check dimensions, accessibility, malformed data and external-URL refusal. These six cases are included in the 134 tests. |
| Standalone parser | **406 tests passed**, with clean package analysis, on the exact mirrored source. |
| Source-sync controls | **19 tests passed**, covering independent source identity, bounded reads, unsafe paths, exact mirrors and preservation of Quds attribution. |
| Coverage provenance controls | **34 tests passed**. These test receipt validation; they do not create or relabel a release coverage receipt. |
| Portable execution | App DOC/RTF/PPT/MSG smoke compiled to JavaScript and passed under Node. A complete Flutter browser build was not performed. |
| Installed native rendering | **13 checks passed** using the installed Linux LibreOffice and Poppler on the authored DOC fixture. The [development native report](legacy-doc-parser-native-check.json) records the checks, executable identities, output hashes and an unchanged fingerprint of 1,222 source-input files. |
| Source inventories | **605 Office files** and **246 CrisperBooks files** verified; the parser mirror also matched the exact standalone Git tree. |
| Static checks | The new Office image factory and its widget/support tests analyzed cleanly; the crypto release-evidence preflight passed after the three technical fingerprint updates. |

The native report is a scoped sanity check of conversion, tables, text styles,
page dimensions, notes, headers/footers, an image and source/output immutability.
It does not bind every external font or shared library, certify exact
pagination, or replace a production-configuration coverage or release receipt.
Microsoft Word execution and Open XML SDK validation were **unavailable and
not run**. The recorded tree fingerprint remains meaningful when the remote
checkpoint has a different commit identifier from the local merge.
