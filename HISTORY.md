# History

Release and integration milestones for CrispCloud. This is a summary, not the
full audit trail. Source-level findings, test records and historical revisions
are preserved in the [history archive](HISTORY-details.md).

## 2026-11 — Office, Mail and release integration

- Integrated the shared Quds Office suite as the Word, spreadsheet, presentation
  and PDF path, with guarded vendor pins and explicit format limits.
- Added Finder File Provider support, macOS signing and App Store profile work.
- Added a credential-vault unlock flow and a system-keychain fallback that does
  not weaken existing item ACLs.
- Made Mail a cached inline workspace pane so switching between Documents,
  Writer, Spreadsheet and Presentation does not discard the account session.
- Added a restore/connecting view while saved Mail credentials load, instead of
  briefly showing the login form.
- Defaulted Mail to a clean plain-text MIME body, kept the HTML toggle, and
  stopped envelope headers or language menus leaking into the body.
- Added remote-image loading only after explicit action.
- Added Word-style autocorrect for smart quotes, apostrophes, spaced en dashes
  and repeated hyphens.
- Added adaptive proofing scheduling and paint caching for fluent typing;
  release/AOT builds are the supported interactive performance path.
- Added configurable Word/Writer shortcuts with conflict review and versioned
  settings persistence.
- Reduced Mail chrome to the Documents-editor style; removed pseudo
  File/Mail/View menus.

## 2026-11 — Commander and transfer reliability

- Added source-aware saved collections, bounded collection pages and verified
  refresh/rerun.
- Added transfer previews for panel, folder and search-result drops.
- Added per-job pause/priority/scheduling, durable journals, conflict
  revalidation and recovery for interrupted copy/move work.
- Added reviewed bulk attributes, checksums, split/combine and integrity tools.
- Added explicit handling for unavailable accounts, replaced objects and
  changed metadata.
- Kept cancellation and partial completion visible instead of rolling back
  silently.

## 2026-11 — Images, archives and viewers

- Added image gallery layouts, ratings, labels, tags, comparison, slideshow and
  batch conversion/contact sheets.
- Added archive creation/editing profiles where metadata can be preserved and
  read-only reasons everywhere else.
- Added ZIP recovery to a new file, bounded UDF/FAT/ext/NTFS readers and
  partition-image inspection.
- Added bounded text/hex viewing, binary comparison and Office/PDF previews.
- Kept package installation, member execution and image mounting out of archive
  browsing.

## 2026-07 — Dependency and platform cleanup

- Moved Filen and Internxt clients to published packages.
- Fixed the web build by selecting WebCrypto instead of unavailable FFI.
- Kept lockfiles, vendor notices and source provenance checked in.

## Earlier foundations

- Dual-pane navigation, tabs, history, favourites and synchronized browsing.
- Provider abstraction, streaming transfers and concurrent queues.
- Secure credential storage with migration and recovery.
- Local/remote editing, search, duplicate detection and folder comparison.
- PDF, e-book, terminal and storage-analysis tools.
- Internationalization with English fallback and platform-native chrome.

## What belongs in the archive

The [archive](HISTORY-details.md) retains:

- exact commit and branch checkpoints;
- test counts and known failures;
- per-feature acceptance records;
- historical limits that were later superseded;
- vendor and source-reconciliation notes.

Those records are evidence, not current instructions. Verify the implementation
and tests before repeating a historical claim.
