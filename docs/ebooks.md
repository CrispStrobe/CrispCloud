# Ebook reading and editing

CrispCloud reads EPUB books and edits their original packages. Its enhanced
reader also opens unencrypted Kindle, FictionBook and comic archives and can
convert them into a separate editable EPUB. The former text viewer remains
available as a fallback.

## Open a book

Select a file and use **F3 / View** to read it or **F4 / Edit** to open its editor.
The preview pane also offers **Read ebook** and **Edit ebook**. Selecting an
ebook in the file list does not start a browser or unpack it automatically.

EPUB opens with **Read** and **Edit** modes. For another supported format, open
it in the enhanced reader, then choose **Convert to editable EPUB**. The
converted book needs a new filename; conversion never replaces the original
MOBI, AZW, AZW3, FB2, FBZ or CBZ file with EPUB bytes.

| Input | Reading and editing |
| --- | --- |
| EPUB 2 / EPUB 3 | Read; edit metadata, contents, source and resources; save to the original or a copy. |
| MOBI / AZW / AZW3 | Enhanced reader for unencrypted MOBI/KF8 content; convert to a new EPUB for content editing. Native builds with the converter also offer a title/author metadata-copy operation. |
| FB2 / FBZ | Enhanced FictionBook reader, including supported zipped input; convert to a new EPUB. |
| CBZ | Enhanced comic reader; conversion retains page images and fixed-layout dimensions in a new EPUB. |
| PDF | Uses CrispCloud's existing [PDF viewer and editor](pdf-editor.md). |
| KFX or DRM-protected purchases | Unsupported by this integration. A recognized filename extension does not imply support for encryption. |

## Reading controls and platform differences

The enhanced reader provides page navigation, nested contents, search,
bookmarks, highlights with notes, reading progress, and appearance settings.
Progress, annotations and appearance are stored on this device or browser
profile, separately from the ebook. They are tied to the source and its exact
content version; edits do not silently reuse highlights at changed positions.

| Platform | Reader | EPUB editor | Import into EPUB | Kindle export / metadata copy |
| --- | --- | --- | --- | --- |
| Android, iOS, macOS, Windows | Enhanced reader using the platform WebView; its runtime must be available. | Yes | Supported enhanced-reader formats | Available when the native converter is bundled and loads successfully. |
| Web | Enhanced reader in a Flutter asset iframe. | Yes | Supported enhanced-reader formats | Unavailable; EPUB export/download remains available. |
| Linux | Portable Flutter EPUB chapter reader with chapter navigation, text-size controls, local raster images and chapter-position restoration. | Yes | No MOBI/FB2/CBZ import through the enhanced reader on Linux. | Available with the native converter, including EPUB-to-Kindle export. |

Linux does not bundle CEF. Its chapter reader does not provide the enhanced
reader's pagination, full book CSS/fixed-layout fidelity, search, bookmarks or
highlight tools. EPUB editing and the legacy text fallback remain available.
The platform table describes the implemented paths; device rendering still
requires the platform smoke checks described below.

### Use the legacy text fallback

Open the ebook's overflow menu and choose **Open text fallback**. The same action
is offered when EPUB loading or enhanced reading fails. It opens the former
text/Markdown viewer directly, with search and readable text in the book's
declared chapter order where the package supplies one.

The fallback previews a valid snapshot of current edits without saving or
changing undo history. If an invalid draft cannot be previewed, it shows the
last readable version with a notice and retains the draft in the editor.
Untouched books with some pre-existing package defects can still reach this
viewer. Close it to return to the same editing session.

This view sacrifices book styling and layout. It can recover text from some
incomplete EPUBs; it does not repair the archive or make encrypted content
readable.

## Edit an EPUB

**Metadata** edits the title, authors, language and description. **Replace cover**
accepts PNG or JPEG images. **Apply** updates the editing session; it does not
write the file.

**Contents** adds chapters, changes reading order, removes chapters from that
order, and edits contents labels and archive-relative links. Removing a chapter
keeps its resource so existing links remain intact. Reordering preserves a
custom nested table of contents. **Rebuild contents from chapters** explicitly
replaces it with a list based on the current reading order.

**Resources** exposes the packaged XHTML, CSS and other text resources in
**Source** mode. For reflowable XHTML, **Text** mode corrects simple text blocks;
blocks containing inline formatting or embedded content remain protected there
and can be edited in Source. This is a bounded prose editor, without a general
word-processor formatting toolbar. Fixed-layout books use Source mode.

Supported PNG/JPEG image resources can open the image editor. Other binary
resources can be replaced. Package-control resources and encrypted resources
have additional restrictions. **Undo**, **Redo**, **Validate**, and **Preview**
operate on the package session, including chapter and metadata changes.

Unchanged resources retain their content, unknown package entries are retained,
and the actual package path is preserved. A no-edit session leaves the original
bytes intact. Edited saves may change ZIP headers and compression for changed
entries; this is not a promise of an identical complete ZIP after editing.

## Save, copy or export

| Action | Result |
| --- | --- |
| **Save** / Ctrl+S, or Command+S on macOS | Updates the captured original EPUB when storage access and conflict checks permit it. |
| **Save a copy** / Ctrl+Shift+S, or Command+Shift+S | Creates a differently named EPUB in the original directory when a storage destination is available. Existing targets are rejected. |
| **Export a copy** | Uses the native save/document-provider dialog to choose a destination. |
| **Download a copy** on web | Starts an EPUB download. It does not acknowledge an overwrite of the original file. |
| **Export AZW3** / **Export MOBI** | Converts the current EPUB and exports a separate Kindle file when the native converter is available. MOBI export contains legacy KF7 and modern KF8 streams. |

Archive members and other byte-only inputs are copy-only editing sessions.
Failed writes retain edits for retry or export. An asynchronous save acknowledges
only its submitted revision; text typed afterward stays unsaved. Copies also
leave the original unchanged, and closing a dirty session requires an explicit
choice. Unsaved book edits are held in memory, not automatically recovered after
an app crash or shutdown.

Kindle conversion can change typography, navigation and unsupported features.
Review the conversion notes and the exported book. **Edit Kindle metadata**
currently exposes title and authors in the app and exports a separate copy;
the underlying package's broader metadata API is not a broader UI promise.

## Limits

The app opens input files up to **64 MiB**, allows EPUB output up to **128 MiB**,
and limits an edited text resource to **8 MiB**. Package and conversion libraries
also apply entry-count, expanded-size, XML, image and encoding bounds; their
READMEs give the exact budgets.

Signed EPUBs are read-only. Standard IDPF/Adobe font obfuscation is distinguished
from DRM and preserved without changing its publication identifier. Unsupported
encryption is refused. Book scripts and remote resources are blocked in the
enhanced reading/import representation, so interactive or network-dependent
publications can behave differently. These display changes do not rewrite the
original EPUB.

**Validate** checks the editor's structural rules and common references. It is
not full EPUB conformance validation. Use EPUBCheck for publication or release
validation, and retain Source mode for complex or unsupported content.

## Implementation, provenance and verification

- [EPUB package core](../packages/crisp_ebook/README.md): preservation model,
  structural operations, validation and limits.
- [Reader integration](../packages/crisp_ebook_reader/README.md): hosts,
  offline behavior, tests and licenses. The exact foliate-js revision is
  [78914aef4466eb960965702401634c2cb348e9b1](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1);
  [UPSTREAM.json](../packages/crisp_ebook_reader/UPSTREAM.json) and the
  [local patch](../packages/crisp_ebook_reader/patches/foliate.patch) record the
  vendored sources and modifications. No Anx Reader or Foliate desktop app code
  is vendored.
- [Kindle conversion](../packages/crisp_ebook_conversion/README.md): native
  build instructions, runtime capability checks and reproducible import/export
  tests. [Kindling provenance](../packages/crisp_ebook_conversion/UPSTREAM.md)
  pins MIT-licensed Kindling 0.46.2 at
  [7774dbae758435d6ed94a4cd4a50e3f33ab61aa7](https://github.com/ciscoriordan/kindling/tree/7774dbae758435d6ed94a4cd4a50e3f33ab61aa7).
  Native builds require Rust 1.88+ and the target toolchain. Approved MPL-2.0
  dependencies, including the CSS parser, are recorded with the other
  [third-party notices](../packages/crisp_ebook_conversion/licensing/THIRD_PARTY_LICENSES.txt).
- [Ebook CI workflow](../.github/workflows/ebook-editor.yml): package checks,
  EPUBCheck, native conversion, independent reader parsing, browser probes and
  focused application tests. The package READMEs contain local commands.

Verification on **12 November 2026** included 30 passing core tests, 76 passing
focused app/service/widget tests, and clean targeted application analysis.
The actual application JavaScript release build also passed with
`flutter build web --release --no-pub --no-wasm-dry-run`.
The actual Foliate normalization → core import → EPUB save/reopen pipeline
retained metadata, Unicode, nested contents, links and unchanged non-XHTML
resources. Its source fixture plus AZW3, dual-MOBI and legacy-MOBI imported EPUBs
passed **EPUBCheck 5.4.0 with zero errors and warnings**.

Those fixtures are authored integration samples, not a publisher compatibility
corpus. The local Chromium renderer probe was blocked before browser startup by
the execution environment's socket restriction. Parser and widget results do
not establish full browser layout or six-platform device verification. Run the
browser and native smoke checks in a suitable environment before a release.
