# Ebook reading and editing

CrispCloud reads EPUB books and edits their original packages. Its enhanced
reader also opens unencrypted Kindle, FictionBook and CBZ comic archives and can
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
| MOBI / AZW / AZW3 | Enhanced reader for unencrypted MOBI/KF8 content; convert to a new EPUB for content editing. Edit ten metadata fields in a separate Kindle copy on native builds or in the browser. |
| FB2 / FBZ | Enhanced FictionBook reader, including supported zipped input; convert to a new EPUB. |
| CBZ | Enhanced comic reader; conversion retains page images and fixed-layout dimensions in a new EPUB. |
| PDF | Uses CrispCloud's existing [PDF viewer and editor](pdf-editor.md). |
| KFX or DRM-protected purchases | Unsupported by this integration. A recognized filename extension does not imply support for encryption. |

## Reading controls and platform differences

The enhanced reader provides page navigation, Back/Forward location history,
percentage seeking, nested contents, search, bookmarks, highlights with notes,
text selection/copy, and shared appearance settings. **Appearance** includes
publisher typography, font size/family, line spacing, themes, scrolling or
pagination, maximum columns, page margins and column width. Narrow windows
reduce the number of columns automatically. Fixed-layout books retain their
published text and page geometry and expose only meaningful controls.

Back/Forward follows explicit navigation, while ordinary page turns update the
current history entry. The complete navigation stack lasts for the current
reader session; the current reading position is saved.
Progress, annotations and appearance are stored on this device or browser
profile, separately from the ebook. They are tied to the source and its exact
content version; edits do not silently reuse highlights at changed positions.
The portable and enhanced readers keep separate position records because their
location formats differ.

| Platform | Reader | EPUB editor | Import into EPUB | Kindle export / metadata copy |
| --- | --- | --- | --- | --- |
| Android, iOS, macOS, Windows | Enhanced reader using the platform WebView; its runtime must be available. | Yes | Supported enhanced-reader formats | Available when the native converter is bundled and loads successfully. |
| Web | Enhanced reader in a Flutter asset iframe. | Yes | Supported enhanced-reader formats | Metadata copies use the bundled offline Wasm worker. Full Kindle export and cover replacement require a native build. |
| Linux | The same enhanced engine through the optional embedded WebKitGTK 4.1 host, selected after a runtime probe. A portable Flutter EPUB reader is used when that host is unavailable. | Yes | Supported enhanced-reader formats when the Linux host is available | Available with the native converter, including EPUB-to-Kindle export and metadata copies. |

Linux uses the distribution's complete WebKitGTK runtime rather than bundling
CEF or a partial browser library. See [Linux build and runtime requirements](../linux/README.md).
Before opening an enhanced reader, an isolated helper checks that the browser
can start and paint in the current session. If it cannot, the EPUB reader uses
the portable path. The check has a bounded deadline and keeps the app responsive.
Missing runtime support does not prevent the application from opening. A
reported host startup error offers **Use portable EPUB reader** explicitly; this
keeps its separate locator state instead of interpreting Foliate CFIs as scroll
positions. The same recovery action is available from the ebook menu.

The portable reader uses continuous scrolling and does not provide enhanced
pagination, full book CSS/fixed-layout fidelity, or saved highlight and note
tools. EPUB editing and the legacy text fallback remain available. The platform
table describes implementation paths, not a completed certification of every
OS/version/device combination. Pixel-identical pagination across different
browser engines, fonts and screen sizes is not guaranteed.

The Linux texture currently does not expose publication text through Flutter's
accessibility semantics, and Tab traverses Flutter controls rather than links
inside the book. Those features require implementation as well as assistive-
technology and device testing before claiming complete interaction parity.

### Portable EPUB reading

Use the shared **Search** field to find literal text across chapters without
case sensitivity. Selecting a result opens the matching text block. Internal
links and contents entries can jump to anchors in the current or another
chapter, including Unicode anchors and archive paths containing literal percent
characters. Added search anchors exist only in the display copy.

**Add bookmark** records the current chapter and position; the bookmarks panel
reopens or removes saved positions. Reading progress restores an anchor or an
approximate scroll position within the chapter. **Appearance** saves font size,
serif/sans-serif/monospace selection, line spacing, and light/sepia/dark theme.
These settings and bookmarks persist locally for the same book version.

Portable search returns up to **200 results** in the app. Queries are limited
to 1,000 characters; a search examines at most 2,000 chapters or 32 MiB of
chapter data and skips individual chapters larger than 2 MiB. The interface
reports skipped chapters and search-budget limits. Chapter display retains the
8 MiB text limit and additionally bounds markup complexity. A search result
does not create a saved highlight.

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

## Ebook library

Open **Ebook library** from the file browser menu or reader toolbar/menu. Books
you open are added to this device's local catalog with their title, authors,
format, exact content version, recent-open time and reading progress. Search
across titles/authors/tags/shelves, filter by favorite, shelf, tag or reading
status, and sort by recent opening, title, author or progress. **Edit library
entry** changes favorites, shelves, tags and explicit Unread/Reading/Completed
status. **Remove from library** removes only its catalog row.

**Open book** resolves the original account and folder and checks the object
identity when one was recorded; otherwise it uses the saved path. It does not
search for moved files. Changed book bytes use a separate annotation revision.
**Locate file** opens the original directory.
Reconnect the original account if it is unavailable. Attachments and temporary
sources retain metadata-only entries; locate their files manually to reopen
them. No account credential or file-access grant is created by the library.

The local catalog supports at most 1,000 entries and 4 MiB of serialized data.
It does not download books automatically or synchronize shelves between devices.
Cover grids, series, bulk operations, recursive scans and managed offline copies
remain future work.

## Transfer reading data

Choose **Export reading data** in the ebook menu to save/download a `.reading.json`
file containing the current position, bookmarks, highlights/notes and all
appearance settings. It contains neither the book nor its source path/account.
It can also rescue the in-memory reading state when local preference saving
fails or another open reader has saved a newer sidecar.

Choose **Import reading data** with the exact same book open on another device.
The app validates the JSON format/version, publication SHA-256 and byte length,
renderer, locator envelope/structure, field lengths and overall size. A different edition, an
edited book or a sidecar from the other renderer is refused before changes are
made. This is deliberate: the app does not guess where old highlights belong
in changed text.

Review additions, conflicts, resulting item counts, position and appearance
changes. Choose **Merge, keep local conflicts**, **Merge, use imported conflicts**
or **Replace local reading data**, then **Apply import**. Replace removes local
items absent from the imported file. The reader updates only after local
persistence succeeds. A failed or stale import leaves the current data intact.
The reader then restores the saved position and annotations asynchronously.
The importer cannot guarantee that every saved anchor resolves; unresolved
annotations stay in the stored data, and an unresolved initial position can
fall back to the beginning. Importing recreates the reader and clears its
session Back/Forward history.

The maximum sidecar is 2 MiB, with up to 500 bookmarks and 500 highlights.
New notes entered in the reader are limited to 2,000 characters; the transfer
schema permits existing notes up to 16,384 characters. The file picker checks actual streamed size,
not just the provider's declared size. Automatic synchronization and migration
between edited editions or locator formats are not included. See the
[FBReader comparison and next increments](ebook-feature-parity.md).

If reading data cannot be saved when closing, the reader remains open and offers
**Keep reading**, **Export reading data**, or an explicit **Close without saving
reading data** choice. Exporting a copy does not overwrite a newer sidecar from
another open reader.

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
**Source** mode. For reflowable XHTML, **Text** mode offers two correction paths:

- A plain paragraph opens in one multiline field. New lines become XHTML line
  breaks, retaining the paragraph's attributes and identifiers.
- A formatted paragraph exposes its existing text segments with a preview and
  labels for recognized emphasis, links and other inline formatting. Correcting
  text inside a link preserves its destination; correcting emphasized text keeps
  the original wrappers, publisher spans and attributes.

Images, mathematical/foreign markup, ruby annotations, comments and other
protected content remain in place. Breaks carrying their own identifiers or
attributes also remain protected. Use **Source** to alter these structures, add
formatting, or edit complex nested containers. The preview shows recognized
formatting; the book's full CSS remains available through **Read**. Fixed-layout
books use Source mode.

**Apply** commits the paragraph's changes as one undo step. The editor checks
the complete chapter version before applying, so a changed chapter cannot
receive an old paragraph draft by mistake. A rejected or failed application
keeps entered text in the dialog. An unchanged paragraph leaves the package
clean. This is a bounded correction surface, without a general word-processor
formatting toolbar.

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
Review the conversion notes and the exported book.

### Edit Kindle metadata

Choose **Edit Kindle metadata** from the ebook menu. The dialog exposes
**title, authors, publisher, description, language, ISBN, ASIN, publication
date, subjects, and identifier**. Authors and subjects accept one value per line.

Each field starts at **Keep**, which preserves the stored value even when that
value is not displayed. Choose **Set** to replace a value, or **Clear** to remove
it explicitly. An empty Set field is rejected instead of silently clearing
metadata. Unselected fields and the existing Kindle text/resource records are
retained. The selected metadata is limited to 120 KiB in the app.

New metadata text respects each section's existing UTF-8 or Windows-1252
encoding. Unsupported encodings or characters that cannot be represented
losslessly produce an explicit error; the converter does not relabel the
unchanged book body. Title changes reconcile the header title and EXTH fields,
including books that did not originally have an EXTH metadata block.

The operation exports or downloads a separate `-metadata` copy. If conversion
fails, a warning is declined, or the export is canceled, the dialog retains its
field choices and text for retry. **Cancel operation** stops the current request;
it does not overwrite the original book.

In a native build with cover capability, **Replace cover** accepts a bounded PNG
or JPEG replacement for an existing Kindle cover. **Remove replacement** clears
the pending replacement and keeps the book's existing cover. Full EPUB-to-Kindle
export and Kindle cover replacement require the native converter.

Browser metadata editing runs offline in a bundled WebAssembly worker, using
the same metadata byte engine as native builds. It supports unencrypted AZW3,
dual MOBI and legacy MOBI files. No book is uploaded to a conversion service.
The operation is offered only when the worker and Wasm asset load successfully.
Cancellation or timeout terminates that request's worker and discards partial
output. Browser/device memory limits can still prevent a job from completing;
the input and entered metadata remain available for retry.

## Limits

The app opens input files up to **64 MiB**, allows EPUB output up to **128 MiB**,
and limits an edited text resource to **8 MiB**. Package and conversion libraries
also apply entry-count, expanded-size, XML, image and encoding bounds; their
READMEs give the exact budgets.

The structured paragraph editor permits up to **1,024 text/protected segments**
per paragraph. Plain-text line-break expansion is checked before allocation,
and the resulting chapter must fit its XML node and size budgets. Larger or
unsupported structures remain accessible in Source mode.

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

Earlier editing/conversion verification on **12 November 2026** included **46 core
tests**, **27 native-converter Dart tests**, **4 Rust bridge tests**, **3 embedded
reader controller tests**, and a complete **102-test application/service/widget
run**, including the seven focused prose-dialog tests. The compiled
Dart browser metadata adapter passed 24 assertions through 11 actual Node
workers using the bundled Wasm. Native/Wasm metadata parity is checked against
the same Kindle fixtures. See the
[extension verification record](recovery/ebook-extension-2026-11-12.md) for the
release-build and hosted status for that earlier revision.

The four core fixtures, including a formatted-text correction, pass **EPUBCheck
5.4.0 with zero fatal errors, errors or warnings**. The previously verified
Foliate normalization → core import → EPUB save/reopen pipeline also retained
metadata, Unicode, nested contents, links and non-XHTML resource bytes. Its
source fixture plus AZW3, dual-MOBI and legacy-MOBI imported EPUBs passed the same
independent validator.

Those fixtures are authored integration samples, not a publisher compatibility
corpus. The local Chromium renderer probe was blocked before browser startup by
the execution environment's socket restriction. Parser and widget results do
not establish full browser layout, actual browser worker loading, or six-platform
device verification. Run the hosted browser and native smoke checks before a
release; the [platform-parity recovery record](recovery/ebook-parity-2026-11-12.md) separates
completed local checks from pending platform checks.


### Platform/library expansion verification

The [platform-parity recovery record](recovery/ebook-parity-2026-11-12.md)
tracks the larger extension. The earlier `1d08158` checks include **8 reader controller/model
tests**, **154 application/service/widget tests**, normal and missing-grouping +
raw-DEFLATE parser variants, and a successful full web release build. The three
host-owned reader JavaScript modules in the built web bundle match their source
hashes. The source audit covers 207 paths; its existing Python suites and
source-bound evidence check passed without changing any gate or policy decision.

The first dedicated Linux run compiled the enhanced plugin and passed its
package checks; the portable-only build and launch passed. The enhanced
application then exited before completing actual rendering/input validation.
That is an unresolved native runtime gate while diagnostics are investigated,
not a successful enhanced-reader result. Consult the recovery record for later
runs and exact revisions. Mobile, Wayland, hardware input and assistive-
technology validation remain separate requirements.

The recovery continuation adds a bounded, isolated Linux startup check and
fixes explicit reading-data discard, concurrent chapter-resource cleanup,
canceled search overlays, search chapter indices, and late callbacks from
replaced books. After synchronization with integrated `main`, **157 focused
application/service/widget tests passed**. The reader package has **8 passing
tests** and clean analysis. The native guard has **7 passing real subprocess
scenarios**, and both native helper and plugin pass compilation against the
actual Flutter/GTK/WebKit headers. Header compilation does not establish a
linked or rendered native application. The merged application's web release
build passed, with all five reader assets and all three metadata assets
matching source. The recovery record tracks exact revisions and the separate
hosted rendering and recovery jobs, which remained queued at the final check.
