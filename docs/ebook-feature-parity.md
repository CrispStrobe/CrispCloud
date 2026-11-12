# Ebook platform consistency and FBReader comparison

Assessment date: **12 November 2026**. This document distinguishes code that is
implemented, behavior that has been exercised, and work still required for a
release. See [the user guide](ebooks.md), [reader package](../packages/crisp_ebook_reader/README.md),
and [recovery checkpoints](recovery/ebook-parity-2026-11-12.md) for usage and
the verification record. Implementation is on draft PR
[CrispStrobe/CrispCloud#53](https://github.com/CrispStrobe/CrispCloud/pull/53).

## Why Linux was different

The first integration used `flutter_inappwebview` 6.1.5 for native hosts. Its
stable supported-platform list includes Android, iOS, macOS, Windows and web,
but does not include Linux. The missing component was the Flutter-to-browser
host, not the Foliate ebook engine. The portable Flutter chapter renderer kept
EPUB reading and editing useful on Linux, but introduced a second rendering
and location system. It consequently could not provide the same CSS layout,
pagination, selection highlights, fixed-layout fidelity or non-EPUB import.

Sources: [supported platforms](https://inappwebview.dev/docs/webview/in-app-webview/),
[native browser implementations](https://inappwebview.dev/docs/intro/).

The expansion adds a narrow Linux WebKitGTK 4.1 host for the **same bundled
Foliate assets and command/event bridge**. It composes a native offscreen
browser through a Flutter texture, rather than positioning a separate native
window above Flutter dialogs. The existing stable plugin and other platform
dependencies are retained. Linux support is selected only after an isolated
startup check: a packaged helper must load the same sandboxed WebKit runtime,
serve a fixed local readiness page, receive its JavaScript reply, verify a
known-color painted snapshot and clean up its subprocesses. Missing libraries,
unusable sandbox prerequisites, helper
failure or timeout report an unavailable host before an in-process WebView is
created. A build without the optional development headers also continues to
launch and can use the portable EPUB reader. The result is cached for the app
process; restart after changing runtime prerequisites.

The Linux code is not, by itself, evidence of a working shipping Linux build.
Its dedicated gate must compile and exercise the actual WebKit process, frame
production, Flutter texture consumption, screenshot composition, input, resize,
navigation and disposal. The startup check is not a rendering/input test, and
does not prevent every possible later browser or graphics failure. An unavailable runtime is a fallback result, never a
passing enhanced-reader check. See the recovery record for the latest results.

## What “the same experience” requires

There are three different targets:

1. **Feature and interaction consistency:** the same menus, book formats,
   navigation commands, annotations, library operations and error recovery.
2. **Data consistency:** the same book identity, location semantics, annotation
   schema, settings schema, import rules and conflict handling on every host.
3. **Pixel identity:** the same line breaks, font metrics, pagination and image
   rasterization at the same viewport size.

The first two are the product target. The third is not guaranteed by sharing
JavaScript. Android WebView, Apple WKWebView, Windows WebView2, WebKitGTK and a
user's browser can differ in typography, CSS and accessibility behavior. User
fonts, display scale, viewport size and engine updates also change pagination.
Locations should therefore use content anchors; a page number alone is not a
portable reading position.

To make a release-level parity claim, all of the following must hold:

| Layer | Required contract | Current approach |
| --- | --- | --- |
| Publication | Same bytes, parser version, offline resource policy and format capability | Pinned Foliate assets, original package preservation and bounded input/import |
| Host | Inline rendering, bridge replies, selection, pointer/touch/keyboard, focus, sizing and teardown | Existing native/web hosts; new optional Linux host with its own real-runtime gate |
| Reader UI | Same controls, meaningful capability flags, predictable errors and recovery | Shared Flutter toolbar/dialogs; fixed-layout and portable controls are explicitly limited |
| Reading data | Exact publication identity, renderer version, stable anchors, bounded schema and conflict rules | Versioned sidecars bound to SHA-256 and byte length; Foliate and portable locators remain separate |
| Library | Persistent metadata and exact source identity, with access resolved afresh | Local indexed entries over existing account/root/file references; no credentials in rows |
| Sync | Atomic updates, revisions, conflict resolution, offline queue and deletion semantics | Explicit JSON transfer is implemented; automatic synchronization remains work |
| Accessibility | Labeled controls plus actual text selection, reading order and assistive-technology exposure | Shared Flutter controls; Linux publication semantics and in-book Tab navigation are not implemented. Assistive-technology/device audits remain required |
| Distribution | Browser runtime, subprocess/sandbox dependencies, updates, signing and notices | Use complete maintained system WebKit packages on Linux; do not copy a partial browser library into the app |
| Validation | The same publication corpus and operation tests on every shipping host | Parser, controller, widget and browser gates plus dedicated Linux tests; mobile/desktop hardware validation still required |

Strict pixel identity would require a common controlled text/layout/raster
implementation, bundled fonts with suitable licenses and tightly controlled
rendering inputs. That is a substantially different architectural project.
It would also need accessible text semantics, selection and input support;
matching screenshots alone would not make it an equivalent reader.

## Scope added in this expansion

### Shared navigation and appearance

- Real Back/Forward navigation, distinct from previous/next page commands.
  Commands are ordered and wait for the renderer's navigation completion.
- Percentage seeking with bounded finite values and a visible progress slider.
- Responsive maximum column count, column width and page margins.
- Publisher typography preference alongside font size, font family, line
  spacing, reading flow and light/sepia/dark themes.
- Capability-aware controls: fixed-layout publications do not expose typography
  and geometry changes that cannot be honored; the portable reader does not
  advertise Foliate-only features.
- Copying the selected text from the shared toolbar.

Reader styles do not remove or rewrite the publication's CFI-bearing content
nodes. Appearance settings remain separate from saved book content. The public
Foliate history is **session-only**: the pinned engine exposes Back/Forward
operations and availability, but not a supported serializable history stack.
Current position persists; the complete navigation stack is not exported.
Importing reading data, or refreshing a changed sidecar after using the library,
recreates the reader and resets this session history.

### Local library

Opening a book records its title, authors, format, recent-open time, renderer and
exact content revision. Entries support favorites, shelves, tags, explicit
reading status, progress, search and sorting. The library is available from the
file browser and reader. Removing an entry removes catalog metadata only.

Reopening resolves the original storage account and root, then checks the
stored object identity when one was recorded; otherwise it uses the saved path.
It does not search for moved files. Changed book bytes create a separate revision
and annotation binding. A matching provider name is insufficient. A
disconnected account produces a reconnect/locate message. Attachment and
ephemeral inputs have metadata-only entries and require the user to locate the
file again; the catalog does not manufacture a file-access grant.

This is a bounded local catalog, not a downloaded-book cache or automatic cloud
library: at most 1,000 entries and 4 MiB of serialized catalog data. Separate
instances serialize updates so two open dialogs do not overwrite each other's
catalog edits. Cover grids, series metadata, bulk management, recursive folder
scanning, managed offline downloads and cross-device shelves remain separate
extensions.

### Reading-data transfer

**Export reading data** produces a UTF-8 JSON sidecar containing the current
position, bookmarks, highlights/notes and all appearance options. The sidecar
does not contain the book itself, source paths, account identifiers or access
credentials. Export is explicit; it does not modify the original publication.

**Import reading data** verifies the format/version, exact book hash and length,
renderer contract, locator envelope/structure, field bounds and nesting budget before
previewing changes. Three modes are available: merge while keeping local
conflicts, merge while preferring imported conflicts, or replace the local
reading state. The preview shows additions, conflicts, result counts and whether
position/appearance change. Replacement explicitly identifies removal of local
items absent from the incoming sidecar.

Application is atomic with respect to local persistence: a failed write does
not publish a successful import. A stale preview or another reader's newer
saved sidecar is rejected rather than silently overwriting notes. The reader
is recreated from the committed state, then restores appearance, position and
highlights. Stored-state application is atomic; renderer restoration is
asynchronous. The importer does not validate the full EPUB CFI grammar or prove
that every target resolves. Unresolved annotations remain in the stored data,
and renderer errors are surfaced when returned; an unresolved initial position
can fall back to the beginning. The picker checks both declared
and actual streamed size; the JSON limit is 2 MiB, with at most 500 bookmarks
and 500 highlights and bounded note/locator strings.

The preference write locks and stale-instance guards coordinate readers within
one running app. They are not a cross-process or remote conditional-write
protocol. Automatic synchronization is not implied. Users can transfer this file through
their existing storage tools, then import it explicitly on another device with
the exact same book and compatible renderer. A portable-reader sidecar cannot
be applied as Foliate CFIs, and edited book bytes deliberately need a new
annotation binding. A future migration/re-anchoring tool must preview ambiguous
matches instead of guessing.

## FBReader comparison: choose the correct baseline

FBReader does not present one uniform feature set on every platform. Its
[desktop news](https://fbreader.org/news) identifies **2.1.5 as the stable
baseline** and announces **2.5 RC 1 on 29 October 2026**. The release candidate
adds several features that should not be attributed to every stable desktop
installation. [Android](https://fbreader.org/android) also distinguishes free
and Premium functionality. The [iOS page](https://fbreader.org/en/ios) lists a
different format and catalogue set. Compare the desired shipping platforms
and editions explicitly.

Android Free relies on plugins for PDF/comics; Premium includes those readers
and adds speech and Google/DeepL translation. DjVu still uses a plugin. The
current iOS page excludes PDF, DjVu, comics and OPDS, while its free edition
limits the library to ten books and lacks online translation. Android's stable
3.8 and 4.0 beta tracks are separate from the desktop stable/RC comparison.
These are platform/edition distinctions, not a universal FBReader feature list.

| Product area | FBReader reference | CrispCloud after this expansion | Remaining work for comparable coverage |
| --- | --- | --- | --- |
| EPUB, MOBI/KF8 and FictionBook | Core desktop/mobile reading; exact supported extensions vary | Enhanced engine reads EPUB, unencrypted MOBI/AZW/AZW3, FB2/FBZ; Linux uses the shared path when its host works | Broader real-book corpus, old encoding/layout cases and device validation |
| Comic archives | Desktop stable CBZ; CBR/CB7 called out in 2.5 RC | CBZ through the enhanced engine | CBR/CB7 extraction with reviewed libraries, limits and packaging; comic zoom/pan/reading direction |
| RTF, old DOC and plain text | Listed on desktop and iOS pages | Existing separate text/document viewers; no unified ebook-library import path for those formats | Deliberate normalization and styling rules; avoid treating a separate viewer as equivalent reader support |
| Pagination and styling | CSS/style controls, two-column reading, fonts and layout preferences | Shared pagination, maximum columns, width/margins, themes, font family/size/spacing and publisher preference | Custom-font discovery/import, typography breadth, hyphenation controls and broad RTL/vertical-writing QA |
| Bookmarks and annotations | Styled/editable bookmarks; persisted desktop reading-position back stack; experimental transfer in RC | Bookmarks, highlights/notes, local position, shared selection, conflict-aware sidecar transfer | Rich annotation editing/search, persistent back-stack contract, interoperable formats and robust re-anchoring after edits |
| Library | Stable title/author/recent/series views; RC redesigned library, favorites/custom shelves and bulk actions | Local title/author/format/recent/progress index, favorites, shelves, tags, status, filtering and sorting | Covers, series, batch operations, scanning, managed downloads and synchronized shelves |
| Cross-device synchronization | Book Network synchronizes collection, positions and bookmarks; synchronized desktop favorites/custom shelves are a 2.5 RC addition | Explicit portable reading-data files; existing cloud file access | Versioned remote sidecars, conditional writes, conflict review, offline retry, deletion tombstones and account/device management |
| Online catalogues | OPDS on desktop; RC OPDS 2.0 groups/filters/profiles and browser/QR authentication | General file providers can supply books, but no OPDS client | OPDS 1/2 parsing, discovery, authenticated acquisition, pagination, download queue and safe credential scoping |
| Speech | Android Premium; desktop system TTS in 2.5 RC | Not integrated into the ebook reader | Shared speech queue, text/CFI mapping, platform voices, controls, background playback/audio focus and accessibility testing |
| Dictionary and translation | Android Premium translation and platform-dependent integrations | Text selection/copy only | Dictionary adapter, optional selected-text translation, language handling, clear network consent and privacy behavior |
| EPUB audio/video and read-aloud | Desktop 2.5 RC adds media playback | Offline reading sanitizer has a deliberately narrower content model | Reviewed local media support, codecs, controls, playback lifecycle and separate SMIL/media-overlay synchronization |
| Protected loans | LCP-protected EPUBs on desktop 2.1+, Android 3.7+ and iOS | Unsupported encrypted purchases/loans are refused | Licensed/certified LCP integration, key handling, loan/expiry UX and distribution requirements; never promise generic DRM removal |
| Store/library acquisition | Book Network and RC store/borrowing integration | Existing storage providers and explicit imports | Product-specific discovery, account flows, acquisition metadata and rights-aware download lifecycle |
| Reader ergonomics | Mature platform-specific UI and keyboard/touch behavior | Shared Flutter controls and engine bridge, optional portable recovery | Gesture/tap zones, orientation/full-screen preferences, mobile safe areas, e-ink and assistive technology audits |
| EPUB content editing | Reader-focused comparison | Original-package editing, formatted text corrections, metadata/cover/resources/TOC, undo/redo and conflict-aware saves | Expand editing separately; these strengths do not fill missing reader/sync/catalogue features |

Primary product sources for the table:

- [FBReader for Linux](https://fbreader.org/en/linux) and
  [Windows](https://fbreader.org/windows): stable desktop feature tables.
- [FBReader news](https://fbreader.org/news): dated stable/RC distinctions and
  desktop 2.5 additions.
- [Book Network FAQ](https://books.fbreader.org/faq.html): synchronized data and
  storage behavior.
- [Android](https://fbreader.org/android), [paid editions](https://fbreader.org/faq/paid-versions)
  and [iOS](https://fbreader.org/en/ios): platform/edition differences.

The table is a gap analysis, not a claim that the new implementation has passed
FBReader's complete behavior or performance corpus. FBReader's modern desktop
application is not an open-source drop-in; any proposed SDK adoption needs its
own licensing and integration decision. See its [product overview](https://fbreader.org/).

## Next increments and acceptance criteria

### 1. Finish and qualify the common reader foundation

Run the real Linux host gate, then the same reading corpus on X11/Wayland and
each other shipping host. Exercise Unicode selection, copying, keyboard and
touch navigation, resize/scale, nested dialogs, disposal, offline mode and
renderer failure recovery. Include reflowable/fixed-layout EPUB, images/SVG,
non-Latin/RTL text, long chapters, FB2, CBZ and every supported Kindle variant.
Confirm OS accessibility exposure explicitly; a texture does not automatically
expose the browser's semantic tree through Flutter.

### 2. Add automatic reading-state synchronization

Reuse the strict schema and publication binding but add a versioned protocol:
device IDs, stable annotation IDs, revision/ETag checks, atomic replace,
deletion tombstones and an offline queue. Merge independent annotations by ID;
surface simultaneous edits/deletes. Current reading position is a product
choice (resume latest, keep per-device or ask), not a numeric maximum. Account
changes must invalidate pending operations. Test two devices, interrupted
writes, stale revisions, reconnects and a changed book before enabling it.

### 3. Add catalogue and library depth

Implement an OPDS adapter that converts entries into the same bounded catalog
and download model. Start with anonymous acquisition, then explicit supported
authentication mechanisms. Treat feed URLs, redirects, acquisition links and
credentials as separate trust decisions. Add covers, series, batch actions,
managed offline copies and duplicate/revision handling. Validate large feeds,
slow networks, partial downloads, restart/retry and incorrect MIME types.

### 4. Add speech and language tools

Create a shared reading-text/locator interface before choosing speech backends.
It must map spoken chunks back to stable content ranges and exclude hidden or
unwanted content. Define pause/resume, chapter transitions, rate/voice choices,
offline availability, background behavior and selection-to-speech. Dictionary
lookup and optional translation can then share selection/language plumbing
without sending entire books to a network service.

### 5. Add licensed content and media deliberately

LCP requires an approved integration and a full loan lifecycle, not a relaxed
encryption check. Audio/video and media overlays need a narrowly reviewed
resource policy, codec support and playback state machine. Extend format
support only with archive/memory limits and fixtures for malformed input.

These stages are separable, reviewable deliverables. A broad “feature parity”
label should be reserved for the subset actually implemented, packaged and
validated on each supported platform.
