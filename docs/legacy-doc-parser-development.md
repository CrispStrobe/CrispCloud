# Legacy Word parser development integration

The integration pins are recorded in `packages/legacy_doc_parser/UPSTREAM.json` and `tool/office_fidelity_manifest.json`; historical receipts retain their original source identities.

## Current continuation checkpoint

The [qualified ink/textbox receipt](evidence/word-final-c5ff75e7-20261113/README.md)
records clean published app `86d5a218` with parser
`c5ff75e76163d9abbdd44a9f2a7c5ad210929289`. All 1,679 managed Office files verify:
1,258 exact parser files and 421 unchanged other files. Version `1.2.9+22`,
the root lockfile, Quds and all other dependency pins remain unchanged.

The runtime adds bounded nonempty ink inspection, qualified gradient and
embedded bitmap fills, and coupled default-line/frame handling for resolved
textboxes. Original ink remains preserved; no native Word ink or guessed
placement is emitted. Unresolved Word14 textbox properties and native bridge
paint/layout differences remain explicitly outside exactness claims.

All 107 data-only Word tests, 13 actual native assertions, four-format JavaScript
checks and source/release controls pass on that exact runtime. All 7,573 tracked
file hashes, 1,182 cohort input hashes and production package configuration
remain unchanged. The hosted provider run also passes on `86d5a218`; the
retained hosted Office success belongs to the earlier `6f2e3245` app checkpoint.
The receipt keeps the command/event logs, exact source review, independent
projection check and fetched remote-checkout verification. Its verifier binds
the inner cohort command, exact eight suites and per-suite event associations
and rejects 22 resealed semantic corruptions.

## Earlier first layout follow-up at 74420eb2

The [first layout follow-up receipt](evidence/word-layout-74420eb2-20261113/README.md)
records clean published app `e3eaaa32` with parser
`74420eb2e0ec14401a0db5bcbb30ab6d202a2340`. It integrates explicit Line Number
styles, exact integer picture sizing, supported textbox paint and a visible
generated placeholder for unavailable OLE previews. All 1,369 managed Office
files verify: 948 exact parser files and 421 unchanged other files. Version
`1.2.9+22`, the root lockfile, Quds and other dependency pins remain unchanged.

The exact app runtime passes 107 data tests, 13 actual native assertions,
four-format JavaScript acceptance and the source/release controls. All 7,257
tracked file hashes and 1,180 cohort input hashes remain unchanged across
execution. The receipt retains the source review, guarded sync, complete
command results and independent remote-checkout verification. It preserves
each upstream feature's measured scope and the known remaining native bridge
differences. The later textbox fill and ink roll is recorded separately above.

## Earlier continuation at 48bf3a

The [13 November continuation receipt](evidence/word-gaps-48bf3a-20261113/README.md)
records acceptance of clean published app `0233ed8e` with canonical parser
`48bf3a84e822b960e369f0134d597e025c775a41`. It preserves current main's build 22,
archive integrations, Quds pin and dependency lock. All 1,226 managed Office
files verify: 805 exact parser files and 421 unchanged other files.

The continuation restores six upstream evidence logs omitted from main by the
app's general log ignore rule. The stricter Git-index gate checks source bytes,
executable modes, pin declarations, new files and deleted files before publication;
Office CI runs it before temporary SQLite hooks. The parser update also retains
unsupported disabled-line fallback appearance explicitly and adds independent
note-source attribution without changing the note story to match native loss.

All 107 data-only Word tests, four-format JavaScript acceptance, 13 actual native
assertions and 27 synchronization controls pass on the exact app runtime. All
7,108 tracked app-file hashes and 1,179 captured cohort inputs are unchanged
across execution. Existing Apple, crypto and ebook controls and actual source
verification also pass. The receipt retains complete execution records and an
independent checkout check of the published Git tree. It does not claim Flutter
widget execution, exact native pagination or a release build.

The separate [hosted Office workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296083)
passed both host-roundtrip and external-schema jobs on that same runtime,
including the committed-source gate, app save workflow, complete host-export
inventory, invalid XML control, SDK validation and actual-host native repeated
saves. [Provider compatibility](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296067)
also passed. The receipt retains their exact run, head and step metadata separately
from the local artifacts.

## Earlier continuation at 0c3e596

The [0c3e596 continuation receipt](evidence/word-continuation-0c3e596/README.md)
records final acceptance on exact clean remote app checkpoint `5348fade`.
All 653 parser files match upstream; the 421 non-parser Office files and Quds
pin remain unchanged, and all 1,074 managed files verify. The app passes 107
data-only Word tests, 24 synchronization controls, the unchanged production
DOC/RTF/PPT/MSG JavaScript tool and 13 actual LibreOffice/Poppler checks.
Complete logs, all 1,176 unchanged cohort input hashes and 49 additional
source/tool/fixture hashes are retained. JavaScript and native acceptance use
the genuine production package configuration resolved offline with the
unchanged app lockfile.

The technical source audit adds the new bounded internal-link module to the
reviewed-files inventory and refreshes its two source fingerprints. All policy
decisions, dates, references, source plist declarations and lockfile identity
remain unchanged. Existing preflight controls and actual Office/ebook source
verification pass. The receipt preserves two expected macOS-only control skips
and the corrected missing-Node-path attempt. It does not claim Flutter widget
execution, exact native glyph/page rendering or a release build. The earlier
[d11fa0e receipt](evidence/word-continuation-d11fa0e/README.md) retains its original
measured local and same-tree remote identities.

The following sections retain earlier source-specific results. Current source
pins remain authoritative in the upstream record and Office manifest above;
historical counts do not automatically qualify a later parser revision.

## Earlier integrated fidelity checkpoint

The [d14f03f integration receipt](evidence/legacy-doc-parser-20261112/parser-d14f03f/README.md)
records the completed continuation after the historical development checks
below. That measured app runtime passes 142 Word conversion/UI tests across
17 suites, 101 Python harness tests, portable DOC/RTF/PPT/MSG JavaScript checks
and installed-Office acceptance with independent PDF checks. Source files and
prepared output remain unchanged by inspection/preview.

The canonical parser retains the full 24-input, three-cycle native run: all
24 initial imports and 72 repeat imports complete, all initial page counts
agree, six initial renders are exact, and both reviewed source goldens match.
Its integrated independent SDK gate accepts all 218 required outputs. Complete
reports, exact DOC/DOCX artifacts and the earlier failed receipts remain in the
mirrored package. The shared-header failure is closed for these exact inputs;
the separate native header/table controls remain unsupported.

The eight broader fidelity areas remain bounded contracts. Current limits and
attribution are recorded in the package's `doc/fidelity-status.md`; equal page
counts, valid schema and successful app checks do not establish full editing
semantics or exact pagination. Microsoft Word was not executed.

That earlier development continuation consumes canonical standalone parser
`ba5f5b0cdd540bd0c03f62aabc88faadd8660e0b` through Quds integration
`a9f7c1a3ee8e9ffea7d65f781fb5584540ebb41d`. The exact upstream parser passes
666 Dart tests, 110 Python oracle controls and the independent 153-output Open
XML SDK gate. The [corresponding app integration receipt](evidence/legacy-doc-parser-continuation-20261112/README.md)
records source verification, 32 inspection tests, 19 sync controls, JavaScript
acceptance and 13 actual installed-Office checks. Earlier results below retain
their original source identity; this development update does not requalify a
frozen release.

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

The [current app validation receipt](evidence/word-continuation-7308125/README.md)
retains complete records from clean app `5e1adcdb`: 107 data-only Word tests,
the four-format JavaScript smoke, 13 actual LibreOffice/Poppler checks and 24
source-sync controls. Its source/dependency hashes and adapter reproduction
helper preserve the execution boundary; the 13 fake-process tests within the
Word cohort are separate from the actual native checks. These checks do not
execute Flutter widgets or qualify a full application release.

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
