# Standalone legacy Word package

CrispCloud consumes the portable Dart package
[`legacy_doc_parser`](https://github.com/CrispStrobe/legacy-doc-parser) from the
user-created repository. The exact development source is recorded in
[`packages/legacy_doc_parser/UPSTREAM.json`](../packages/legacy_doc_parser/UPSTREAM.json)
and the Git dependency in `pubspec.yaml`. A path override selects the exact
vendored mirror, so `pubspec.lock` records that path and package version rather
than a Git checkout. No pub.dev release is selected. Later adoption of a hosted
release is an explicit dependency update.

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
library. The mirror retains the complete tracked standalone source, tests,
fixtures, tools and license notices, with no local source patches. The
shared Quds engine retains its existing legacy APIs for other consumers;
CrispCloud's document previews and conversion use the standalone package.

The Office manifest has a separate `standalone_sources` entry for this package.
Its files are not attributed to the older Quds suite commit. The Quds source
identity and independently maintained parser identity are verified separately;
a later Quds sync cannot replace the parser with the suite's older copy.

To review an update from a local checkout containing both pinned commits:

```sh
python3 tool/sync_legacy_doc_parser.py --source /path/to/legacy-doc-parser --ref FULL_COMMIT_SHA
```

The default is read-only. After reviewing the plan, repeat with `--apply`, then
resolve dependencies and run the gates. The tool validates the entire current
mirror against its original Git commit before writing, bounds the source tree,
rejects symlinks and unexplained source files, updates the Git pin and mirror
metadata together, and writes the new Office inventory last. It leaves Quds
bytes and historical release evidence unchanged. Generated local test outputs
are not treated as source patches. Verify the exact result with:

```sh
python3 tool/verify_office_fidelity.py --legacy-source /path/to/legacy-doc-parser
```

## App behavior

F3 keeps its main-story formatted preview and explicit text view. The richer
package model also supplies referenced auxiliary stories, fields, numbering,
media, object/VBA storage and signature evidence for conversion and inspection.
The HTML preview is a bounded approximation of document layout. Supported
embedded raster images and complete supported EMF/WMF record sets can appear as
self-contained images at their referenced positions. Generated metafile SVG
uses the app's existing SVG renderer in both F3 and the side pane. It does not
activate objects, evaluate fields, or load linked resources. Unsupported
metafile records do not acquire a guessed visual preview.

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
[development README](https://github.com/CrispStrobe/legacy-doc-parser#readme).
[Legacy Word conversion](legacy-word-conversion.md) records the app workflow,
supported feature families and remaining platform/layout limits.

## Licensing and release preparation

The extracted package-authored source uses **MPL-2.0**, with its full license
and source notice in the new repository. MIT compound-file source and selected
0BSD JSDoc adaptations retain their exact third-party notices and pinned
provenance. CrispCloud's existing application license is unchanged.

The package includes a changelog, command-line example, standalone regression
tests, JavaScript/Node acceptance and CI checks for formatting, analysis, tests
and a publication dry run. Package publishing remains a separate release step;
the earlier extraction's successful dry run is not a publication of this
development revision.
The app's existing crypto evidence tracks the changed manifest and lockfile;
the parser extraction introduces no encryption implementation or new crypto
dependency, and does not change the recorded Apple questionnaire status.

## Development and frozen release evidence

The `v1.2.0` freeze at app commit
`9a81d68c7cb27f35e4707267206ef6ea8e3de33d` used parser
`fa9abdb5c1436d46eba9c7a2a35ea13497f5ff20`. Its source-bound receipts and native
rendering reports retain that historical meaning. Updating the development
mirror does not revalidate those receipts or change the frozen release claims.
The current source pin, package version and focused integration checks are
recorded in [the development integration note](legacy-doc-parser-development.md).

New coverage collections bind the actual parser files, dependency resolution,
Office manifest, source-sync tools, test inputs and runtime. A local test run
with optional native hooks disabled is not a matching receipt for the restored
release configuration. Native artifact integrity alone does not establish
current-source rendering acceptance.

## Historical extraction integration

The following results describe the earlier `80e9683c0d60553f7198ca89a64aa927d619c684`
extraction/integration checkpoint, not automatic acceptance of a later pin:

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

The extraction follow-ups were [CrispCloud PR #82](https://github.com/CrispStrobe/CrispCloud/pull/82)
and [package PR #2](https://github.com/CrispStrobe/legacy-doc-parser/pull/2);
the earlier PRs merged before these continuation commits.

Package test counts, independent JavaScript CFB metadata checks and their
scope are recorded in the conversion guide and the package pull request.
These results do not certify arbitrary Word pagination, full OOXML schema
conformance, Windows Word behavior or a complete Flutter browser build.
