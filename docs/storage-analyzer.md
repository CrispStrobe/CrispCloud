# Storage analyzer

The storage analyzer provides a GrandPerspective / WinDirStat-style view of the
folder in the active file panel. It recursively reads folder metadata and shows
which files and subfolders account for the most space. The same view works with
local folders, browser-granted local folders, and connected cloud providers.

## Open and explore

1. Navigate to the folder to analyze and wait for its listing to finish loading.
2. Choose **Storage analyzer** in the **Tools** menu or the overflow menu. It is
   also available in the command palette. On macOS it is available in the
   native View and Tools menus.
3. Watch the file, folder, and byte counts while the scan runs. **Stop scan**
   preserves the portion already measured. A currently running provider listing
   finishes before cancellation takes effect; closing the dialog also stops
   further traversal.
4. Select a rectangle or a list row to inspect its path and size. Use the
   folder's arrow, or double-click / long-press its map header, to zoom into it.
   The breadcrumbs and parent button navigate back through the scan.
5. Open **Largest files** to browse the largest 200 files in the current subtree.
   Filter by name or path, or choose an extension in **File types** to restrict
   the list to that type. Clear the type chip to show all types again.
6. Use **Copy path** or **Show in file panel** for the selected item. The latter
   navigates the original panel and selects the original file; existing file
   manager actions can then manage it. **Scan again** refreshes the same captured
   folder and storage account.

Desktop layouts show the map beside the lists. Narrow layouts expose the map
and lists as tabs. All entries remain available in the folder list, including
empty files and items that have no measurable map area. Controls follow the app
theme, support keyboard focus, and include tooltips and semantic labels. New
tool text is translated in English and German; other app locales use English
fallback for messages without a translation.

## Reading the map and totals

- Rectangle area represents the **known file size**; nested rectangles preserve
  folder grouping. Folder headers and borders reserve a small amount of display
  space, so compare sizes within the same folder level.
- File color is derived deterministically from its lowercase extension. The
  **File types** list uses the same colors and reports counts and sizes.
- Tiny items or branches beyond the display budget are grouped in a hatched
  rectangle. Their combined bytes remain represented. Use the folder list or
  zoom into that branch to inspect them individually.
- A folder total is the sum of its known descendant file sizes, not a size
  returned for the directory itself. Native and cloud scans include hidden files,
  regardless of the panel's display filters. Browser-local snapshots have the
  limitations described below.
- **Partial results** and `+ ?` indicate that some sizes are unknown or some
  entries could not be scanned. Click the scan status for details about skipped
  links, unreadable folders, incomplete provider listings, or traversal limits.
  Zero-byte files and files with unknown sizes remain distinct.

The analyzer reads metadata, without downloading or hashing file contents.
Sizes are the bytes reported by the storage provider. They are not filesystem
allocation, free disk space, or the account's billed/quota usage. Sparse files,
compression, hard links, cloud revisions, trash, provider-native documents and
encrypted-storage overhead can make those quantities differ. Hard-linked files
are counted by listed path; symbolic links are excluded rather than followed.
Changing files during a scan can also make the snapshot differ from a later
listing.

## Scope, limits, and incomplete listings

The scan begins at one real folder in one captured storage account. Archive and
container views, search results and saved collections are not scan roots. An
account disconnect or replacement stops the scan and marks the result partial;
it cannot redirect the analyzer or its reveal action into a different account.
Locked tabs, declined folder access and failed reveals keep the report open.

Browser-local scans require a selected folder. The existing browser file service
can return cached listings, omit hidden names and suppress listing failures, so
these results are explicitly marked partial rather than claiming a complete
disk census. The selected folder grant is captured; replacing it invalidates the
scan instead of redirecting reads into a new folder. Native local and cloud
scans use their regular metadata listing contracts.

Most provider adapters consume all listing pages themselves. When an adapter
exposes another page or reports an incomplete response, the analyzer retains
known entries and marks that subtree partial. It does not invent continuation
requests for adapters without a pagination interface. Native B2's virtual
bucket-index root is not a normal recursive filesystem root. Use an
S3-compatible bucket connection to analyze its contents; virtual bucket rows
are excluded and the result is marked incomplete.

Default scan limits are 200,000 entries, 200 levels of directories, and 1,000
individual diagnostics. Additional diagnostics are counted. Sizes and totals
must remain within the exact shared VM/JavaScript integer range
(`2^53 - 1` bytes). A limit produces a partial result; choose a smaller folder
to inspect the remainder. The map renders at most 1,000 tiles and the
largest-files list displays at most 200 matches. These display limits do not
change scan totals or the browsable folder list.

## Implementation and verification

- `StorageScanService` performs iterative, cancellable traversal, validates
  child paths, rejects repeated entries, and aggregates immutable snapshots.
- `storageScanBackend` uses the panel's captured source identity and existing
  access-grant handling. The cloud adapter retains pagination diagnostics and
  reported stored sizes; the local adapter preserves case-distinct filenames.
- `StorageAnalysisView` browses the completed snapshot without more storage
  requests. Filtering is cached separately from item selection.
- `StorageTreemap` uses a bounded squarified layout with a canvas renderer,
  hit testing, hover details, and semantic actions.

Run the focused deterministic checks with the Flutter version in `.fvmrc`:

```sh
flutter test test/storage_scan_service_test.dart \
  test/s3_listing_completeness_test.dart \
  test/storage_treemap_test.dart \
  test/storage_analyzer_widget_test.dart \
  test/storage_analyzer_origin_test.dart
```

These checks use local fixtures and fake providers; live account scans and
platform-specific folder-grant dialogs require a separate device smoke test.
