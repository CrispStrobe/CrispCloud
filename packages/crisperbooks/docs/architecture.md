# Package boundaries

| Package | Responsibility | Host responsibility |
| --- | --- | --- |
| `crisp_ebook` | Pure Dart EPUB model, metadata/resources/chapters/TOC/prose edits, validation, snapshots, FB2 and FBZ output | Obtain input bytes and deliver validated output |
| `crisp_ebook_reader` | Sandboxed Foliate renderer, format parsing, normalization, navigation/search/annotations/appearance, platform hosts | Choose files, persist locators, approve external links |
| `crisp_ebook_conversion` | Optional Kindling conversion; immutable inputs, bounded output and cancellation | Supply native toolchain, decide where copies go |
| `crisperbooks` | Flutter editing sessions, undo/redo/save ownership, prose editor, appearance controls, portable EPUB reader, reading-data codecs | Accounts, credentials, write conflicts, downloads and library catalog |

No library imports CrispCloud, Riverpod providers, panel models, account settings
or cloud storage. The facade does not depend on the optional Kindle converter.
Workspace development dependencies allow conversion tests to run together.

## Persistence and identity

`EbookEditSession.save` captures immutable validated bytes and the submitted
revision. An original save acknowledges only that revision. Newer edits stay
dirty; a downloaded/exported copy does not acknowledge an original overwrite.
Failed writes retain the draft. Normalized non-EPUB publications use a copy-only
session. The host owns conflict checks and the destination.

Apply edits through `session.mutate` and await external work before entering that
synchronous callback. Nested history/save commands and asynchronous callbacks
are rejected, and a failed composite edit restores the entire starting package.
The public document is mutable for compatibility with the core API; direct
changes remain unsaved and invalidate redo, but do not get their own undo entry
or listener notification. Use `mutate` for all user-facing editing operations.

Portable reading emits readiness and reading-position callbacks only after a
chapter has prepared successfully. A failed chapter leaves the last persisted
location alone while retaining chapter navigation for recovery.

Existing `crispcloud-ebook-reading-data` sidecars and renderer identifiers remain
compatible. Renaming this wire identifier would break existing exports. Locators
bind to the exact publication bytes and renderer; incompatible imports fail.
The package never accesses the caller's accounts or paths.

## Source ownership and licenses

The extracted packages are authoritative here. CrispCloud consumes an immutable
Git revision and keeps integration adapters. `EXTRACTION.json` records the initial
source. Upstream engine manifests and patches remain alongside their packages.

The facade and core retain CrispCloud's existing AGPL-3.0 license. The reader and
converter retain their package licenses and third-party notices. Extraction does
not relicense existing code. Publication must retain applicable notices and
provenance files.
