# crisp_ebook

Pure Dart EPUB package editing for CrispCloud. The canonical document is the
original archive plus changed/deleted resources; an imported book is never
reconstructed from a rich-text editor's simplified document model.

## Usage

```dart
final book = EpubDocument.open(bytes);
final checkpoint = book.snapshot(); // undo, including invalid source drafts
book.updateMetadata(title: 'Revised title');
book.updateText(chapter.path, editedXhtml);
final issues = book.validate();
final revision = book.revision;
final savedBytes = book.toBytes();
await writeToHostStorage(savedBytes);
book.markSaved(revision: revision); // stale completion cannot clear newer edits
```

`EpubDocument.create` starts a new EPUB 3. `fromPublication` imports the reader's
normalized resource map into a **new EPUB**, including MOBI/AZW3/FB2/CBZ content
that the reader can export. It does not overwrite or serialize those formats.
`toPublication` produces the same version 1 JSON shape for the reading engine.

Metadata, cover, resource replacement/addition, XHTML/CSS source changes,
chapter addition/removal/reordering, EPUB 3 navigation and EPUB 2 NCX updates
are supported. Reordering the spine deliberately preserves a custom/nested
TOC; call `updateToc()` to explicitly regenerate it. Removing a chapter retains
its XHTML resource by default to preserve existing links. Explicit resource
deletion is rejected while other resources still refer to it.

`readProse` / `updateProseBlock` implement bounded visual correction of simple
text blocks. A block with inline markup or embedded content is read-only in
that mode and remains editable in source mode. Fixed-layout books use source
mode. The visual helper never silently flattens formatting, IDs or classes.

## Preservation and validation

- An unchanged `toBytes()` returns a copy of the exact original archive bytes.
- Edited saves copy untouched compressed streams, resource paths, ZIP comments
  and extra fields; the container's real OPF path and unknown resources survive.
- Changed XML is serialized as XML and keeps unknown nodes/attributes. Changes
  to metadata preserve the publication identifier and unrelated refinements.
  Structural edits retain the surrounding OPF, XHTML and NCX namespace prefixes.
- Literal percent signs in resource names and encoded Unicode fragment IDs are
  preserved through navigation, editing and normalized-publication round trips.
  Import also keeps nested contents groups and omits empty optional metadata.
- The saved `mimetype` entry is first, stored, extra-free and has the exact EPUB
  media type. ZIP64 and split/password-encrypted ZIP containers are unsupported.
- ZIP headers, duplicate/unsafe paths, alternate Unicode names, overlapping
  entries, size limits, bounded Deflate inflation and CRCs are checked. XML has
  text/node/depth limits and does not accept custom entity declarations.
- `validate()` checks this editor's structural invariants, XML, manifest/spine,
  common local XHTML/CSS references and fragment targets. **It is not a complete
  EPUB conformance checker.** Run EPUBCheck for a release or publishing gate.
- Standard IDPF/Adobe font obfuscation is distinguished from DRM. Display copies
  can decode fonts while the original stored bytes and identifier stay intact.
  Unsupported encryption and signed publications are read-only. This package
  does not remove DRM or invalidate signatures to enable editing.

Default bounds: 128 MiB compressed archive, 256 MiB declared expanded size,
64 MiB per entry, 8 MiB per text/XML resource, 10,000 entries, XML depth 128 and
250,000 XML events per resource. Set `EpubLimits` explicitly for a host's memory
budget. Imported/generated resources are subject to the same limits.

All public byte reads return copies. Snapshots share only immutable original
archive data and independently own draft buffers/XML. Multi-step structural
mutations roll back if an operation fails. The host owns concurrency, provider
conflict checks, atomic writes, version history, and save/download acknowledgments.

## Verification

```sh
dart pub get
dart analyze
dart test
dart run tool/generate_fixtures.dart /path/to/fixtures
```

The generator emits a new book, a book with a nonstandard OPF path and opaque
extra resources, and an edited copy. It checks exact no-op and unchanged-resource
preservation before writing these fixtures for external EPUBCheck/reader tests.

The regression suite also checks that chapter deletion preserves landmarks and
NCX page-list targets, empty contents groups are pruned, and mixed or conflicting
encryption declarations cannot be mistaken for font obfuscation alone.

Dependencies: `archive`, `xml`, `html`, `path`, `crypto`. Their upstream licenses
are MIT (`archive`, `xml`, `html`) and BSD-3-Clause (`path`, `crypto`); retain
dependency notices when distributing a vendored application build.
