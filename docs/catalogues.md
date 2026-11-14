# Offline catalogues

Open **Tools → Catalogues** (also available in the command palette). Create a catalogue from a chosen local folder, open a `.crispindex` database, or import a Cathy/Catfish `.caf` file. F3/F4 recognise catalogue headers; Core Audio CAF files continue to use the media viewer.

The shared Rust engine streams metadata into SQLite without a default entry cap. It does not read file contents. Directory totals are logical bytes, child symlinks are skipped, and partial scans retain their errors. Large catalogues stay on disk: the GUI requests pages of 200 rows, supports sorting, name/path search, size/date/extension filters, and largest-file/folder rankings. Library search shows at most 20 matches per catalogue and 200 overall; open the catalogue for its full search. Treemap/sunburst charts describe the current folder page, with unlisted bytes represented separately; they are disabled for overlapping recursive rankings.

Saved metadata can be browsed while the source disk is disconnected. It is historical evidence, not a claim that files still exist. Link a local folder explicitly to reveal a selected entry in the captured file pane. Paths escaping that folder or resolving through an escaping symlink are refused. This action never copies or deletes indexed source files.

Refresh chooses the original root and replaces the database only after successful publication. Cancelled or failed work preserves the previous catalogue. The library can rename entries, save SQLite copies, export CAF, and forget external files without deleting them. Removing an app-owned catalogue deletes only that metadata file. Existing storage-analyzer reports remain available.

## Database and CAF

Use `.crispindex` as the working catalogue: it preserves coverage/errors, supports indexed queries and refresh, and stores a catalogue identity used to reject stale GUI actions. New databases use schema 2; schema 1 remains readable. Update old CLI installations before opening schema-2 databases.

CAF is an optional dated interchange export, not a second live index and not a speed optimisation. Keep one beside a database when another tool or a recipient needs it. Do not automatically duplicate every scan. Import reads CAF versions 1–8; export writes version 8. Empty directories and timestamps are retained. Imported source dates remain source dates on re-export. CAF cannot represent scan failures/completeness, so partial/unknown exports require acknowledgement. Unknown legacy sizes cannot be exported as invented exact values. Classic exports require Latin-1 names; use the native database for arbitrary Unicode paths.

The reusable format codec remains MIT, from the explicitly MIT CrispSorter crate. Its exact upstream checkpoint and hashes are recorded in `packages/crisp_catalog/native/vendor/crispcat-format/UPSTREAM.json`. Extracting a public Rust crate is a useful follow-up after API and portability acceptance; this increment does not publish or relicense it.

## CLI

`crispcloud` is the primary executable, matching `crispsorter` in CrispSorter. `crisp` remains a compatible alias. Both use the same configuration and catalogue engine. Examples:

```sh
crispcloud catalog scan /Volumes/Archive -o archive.crispindex
crispcloud du --index archive.crispindex --top 50
crispcloud catalog search archive.crispindex invoice
crispcloud catalog export archive.crispindex -o archive.caf
```

The CLI bundle must be kept intact with its native libraries and licence files. The native CLI workflow builds both names and supplies separate macOS Apple Silicon/Intel, Linux and Windows bundles. Tagged releases attach these bundles after their platform checks pass.

Native build hooks cover desktop, iOS and Android. Browser builds show the platform limitation instead of importing FFI; browser catalogue execution and WebAssembly are pending. Native platform build evidence does not replace device-level permission and performance acceptance.
