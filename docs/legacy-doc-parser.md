# Standalone legacy Word package

CrispCloud consumes the portable Dart package
[`legacy_doc_parser`](https://github.com/CrispStrobe/legacy-doc-parser) from the
user-created repository. The exact upstream revision is recorded in
`packages/legacy_doc_parser/UPSTREAM.json` and the Git dependency declaration
in `pubspec.yaml`. The active path override uses the reviewed local mirror;
`pubspec.lock` therefore records a path dependency. The mirror is synchronized
through the guarded Quds Office source manifest, rather than an unpinned copy.
It is version `0.1.0-dev.1`; no pub.dev release has been made. Later adoption
of a hosted release is an explicit dependency update.

## Ownership and dependency boundary

| Responsibility | Owner |
| --- | --- |
| Bounded Word binary parsing, immutable document/story/field/media models | `legacy_doc_parser` |
| Escaped text/table HTML and structured DOCX/DOCM serialization | `legacy_doc_parser` |
| File routing, localized UI, captured storage target, review and create-only save | CrispCloud |
| Installed Word/LibreOffice discovery, conversion, PDF review and independent output inspection | CrispCloud |
| Email and other users of the original bounded CFB adapter | CrispCloud; those adapters remain in the app |

The package has no Flutter, platform process, network-service or native-library
dependency. Its only runtime package dependency is `archive`, which was already
resolved by CrispCloud. The small CFB implementation is included with its MIT
notice. The app's DOC/DOT routes import the public `legacy_doc_parser.dart`
library. `packages/legacy_doc_parser` supplies that package to both the app
and the shared Quds engine. The engine's legacy export adapters retain their
existing API surface; parser and converter source come from the same reviewed
standalone revision.

## App behavior

F3 keeps its main-story formatted preview and explicit text view. The richer
package model also supplies referenced auxiliary stories, fields, numbering,
media, object/VBA storage and signature evidence for conversion and inspection.
The HTML preview remains a bounded text/table preview; it does not activate
objects or load linked resources.

**Structured Word (built in)** creates DOCX by default or DOCM after an explicit
format choice. The app verifies the actual output extension and independently
inspects the resulting package. Changing format discards the prepared copy and
its acknowledgement. The user reviews limitations before saving a separate
copy beside the captured original file. Collision retries reuse those exact
reviewed bytes.

DOCX has no active VBA relationship, but original project bytes may remain as
inert evidence. DOCM can attach one structurally complete supported project.
Neither route executes VBA during conversion. Signature evidence does not
authenticate the converted document, and reconstructed object/VBA containers
preserve stream bytes and metadata rather than original sector allocation.
The localized notices distinguish active output from retained source evidence.

The package's source comparison and preservation contracts are linked from its
[development README](https://github.com/CrispStrobe/legacy-doc-parser/blob/feature/structured-doc-preservation-20261112/README.md).
[Legacy Word conversion](legacy-word-conversion.md) records the app workflow,
supported feature families and remaining platform/layout limits.

## Licensing and release preparation

The extracted package-authored source uses **MPL-2.0**, with its full license
and source notice in the new repository. MIT compound-file source and selected
0BSD JSDoc adaptations retain their exact third-party notices and pinned
provenance. CrispCloud's existing application license is unchanged.

The package includes a changelog, command-line example, standalone regression
tests, JavaScript/Node acceptance and CI checks for formatting, analysis, tests
and a publication dry run. The extraction's publication dry run passed with
zero warnings; each subsequent release still needs its own release validation.
Package publishing remains a separate release step.
The app's existing crypto evidence tracks the changed manifest and lockfile;
the parser extraction introduces no encryption implementation or new crypto
dependency, and does not change the recorded Apple questionnaire status.

## Earlier extraction integration

The following results describe the earlier extraction at
`80e9683c0d60553f7198ca89a64aa927d619c684`. They are retained as historical
evidence and are not reused as a test receipt for a newer parser pin.

- **100 app tests passed across 16 suites** after reconciling current main:
  binary parsing/rendering, actual DOC/DOT routing, source/name guards,
  captured create-only saves, localized controls, structured/native dialogs
  and viewer/editor handoffs. A heavy-dotted-underline regression distinguishes
  the standalone parser from the older shared-engine implementation.
- **13 installed-LibreOffice acceptance checks passed** for the built-in
  converter's real DOC fixture, including PDF text and a rendered image,
  actual headers/footers/footnote, and unchanged source/prepared bytes.
- The app's production portable DOC/RTF/PPT/MSG code compiled to JavaScript and
  passed its Node regression after the dependency switch.

The focused Flutter run used the existing system-SQLite test helper and the
ebook package's documented `enabled: false` hook setting because this local
environment lacks its Rust toolchain. The app manifest was restored byte for
byte afterward. This tests Word behavior with optional ebook conversion
unavailable; it is not validation of the native ebook engine. Normal release
configuration and native CI remain enabled. The exact locked package source
is also checked by the app's standalone-parser CI contract step.

That extraction continued in [CrispCloud PR #82](https://github.com/CrispStrobe/CrispCloud/pull/82)
and [package PR #2](https://github.com/CrispStrobe/legacy-doc-parser/pull/2).

Package test counts, independent JavaScript CFB metadata checks and their
scope are recorded in the conversion guide and the package pull request.
These results do not certify arbitrary Word pagination, full OOXML schema
conformance, Windows Word behavior or a complete Flutter browser build.

## Fidelity continuation

The current parser work adds independently checked native row origins,
conditional table cells and text, editable bounded OfficeArt geometry,
compound EMF/WMF previews, note layout, linked-textbox reflow checks, supported
list continuation and revision history. Ink payloads are retained as bounded
inert evidence; nonempty ink-stroke rendering is not claimed.

The upstream [fidelity status](https://github.com/CrispStrobe/legacy-doc-parser/blob/feature/structured-doc-preservation-20261112/doc/fidelity-status.md)
separates supported contracts from the remaining gaps in all eight feature
families. Its native reports distinguish producer round-trip changes, parser
changes, structural differences, renderer coordinates and raster equality.
Successful measurement and equal page counts do not establish exact fidelity.

### Saved integration checkpoint: parser b295a3c

The first continuation checkpoint pins parser
`b295a3c1ddb542b0f161ecafdcdaba3762dc7535` through Quds
`9fb8bf12703f32a487609a673f342a5ae0003de1`. All 169 upstream files match their
source revision, and the host manifest verifies 559 shared Office files.

- 99 app tests pass across the 16 legacy Word/native-conversion suites,
  including routing, localized disclosures, separate-copy saves, and both
  conversion dialogs. The revision timestamp test now checks the inserted
  text and its independently preserved inserted paragraph mark.
- The actual production DOC/RTF/PPT/MSG JavaScript build and Node acceptance pass.
- 67 guarded-sync/native-render harness tests pass. Deliberate native failures
  in the harness controls are expected and must be rejected.
- Installed LibreOffice acceptance passes for the built-in DOCX conversion,
  native DOCX/DOCM conversion, PDF text, note/header/footer content and images.
  Source and prepared-copy bytes remain unchanged.

These app tests used the documented optional-ebook-disabled hook, the retained
Clang 19.1.7 compiler and system SQLite 3.46.1. The test wrapper restored the
release pubspec byte for byte. These results do not validate native ebook
conversion or certify arbitrary Word pagination.
