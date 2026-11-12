# Standalone legacy Word package

CrispCloud consumes the portable Dart package
[`legacy_doc_parser`](https://github.com/CrispStrobe/legacy-doc-parser) from the
user-created repository. The current reviewed runtime is pinned to
`72da6223832c3cbc41929064c8f160cec10016f7` in both `pubspec.yaml` and
`pubspec.lock`. It is version `0.1.0-dev.1`; no pub.dev release has been made.
Later adoption of a hosted release is an explicit dependency update.

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
notice. The app imports the public `legacy_doc_parser.dart` library through
thin compatibility exports. It no longer contains a private copy of the Word
parser or a `packages/legacy_doc_parser` mirror.

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
and a publication dry run. Package publishing remains a separate release step.
The app's existing crypto evidence tracks the changed manifest and lockfile;
the parser extraction introduces no encryption implementation or new crypto
dependency, and does not change the recorded Apple questionnaire status.

## Verified integration

- **54 app tests passed** across conversion, binary preview, source/name guards,
  localized controls, structured/native dialogs and viewer integration.
- **13 installed-LibreOffice acceptance checks passed** for the built-in
  converter's real DOC fixture, including PDF text and a rendered image,
  actual headers/footers/footnote, and unchanged source/prepared bytes.
- The app's production portable DOC/RTF/PPT/MSG code compiled to JavaScript and
  passed its Node regression after the dependency switch.

Package test counts, independent JavaScript CFB metadata checks and their
scope are recorded in the conversion guide and the package pull request.
These results do not certify arbitrary Word pagination, full OOXML schema
conformance, Windows Word behavior or a complete Flutter browser build.
