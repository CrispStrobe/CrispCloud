# Local storage integration — 14 November 2026

The ready ext and NTFS branches are integrated sequentially on top of the BASIC/XML and CSV-to-XLSX changes. The app consumes the canonical standalone MIT `crispcat-format` crate from CrispSorter at `ee165094caeb4fd8eff91de26959124d06a3ba06`; its CAF/index implementation bytes match the previous reviewed codec. No Python runtime, full Tauri application or new format dependency is introduced.

## Integrated sources

- ext: `ffdd6a86820b0d58cf8b93b4e626d0439beefab9`, merged in `4936c9cc` after 199 focused tests.
- NTFS: `d504409a`, merged in `3a3d100d` after 240 focused tests, including the existing CSV/XML and text/hex handoffs.
- Quds remains `b0335829428d50968258219c4fdced15d546f7c9`; the managed source check verifies all 2,161 files, including canonical legacy DOC parser `544a50e7f8ad095a618b6206ccece7e0cb335f4b`.
- CrisperBooks remains the already integrated immutable `505d3d7bfb922e5f0d77b7230cd38b0e266d0606` tree.
- The requested legacy DOC checkpoint `94294e1be87ddfb3c9e4aef6d341955329985b11` is an ancestor of the current canonical parser. CrispCloud's requested archive `efd6969a`, viewer `aef2afa`, Office `788e1f0` and broken-link `41b3e4eb` checkpoints are also included.

## Observed local checks

| Check | Result |
| --- | --- |
| Complete archive/storage cohort, 150 test files | 3,387 passed, 23 conditional/opt-in skips, zero failures |
| Extraction test-host setup corrections | 64 passed; isolated preference stores avoid missing-plugin diagnostics |
| Live sandboxed macOS desktop harness | 3 passed: ext and NTFS image preview/Hex return/extraction, CSV viewer to local XLSX/Quds editor |
| ext portable acceptance | 19 groups, 3,360 checks on Dart VM and compiled JavaScript/Node; identical output |
| NTFS portable acceptance | 18 groups, 2,037 checks on Dart VM and compiled JavaScript/Node; identical output |
| Native catalogue bridge | 13 passed; separate opt-in million-row case passed |
| Million-row synthetic SQLite case | 1,000,005 rows; build 33,170 ms, ranking query 3 ms, database 137,625,600 bytes on this Mac |
| Real CLI/Rust scan, query and CAF interchange | 8 passed, including offline ranking of an imported CAF |
| Standalone CAF codec | 23 unit tests and one compiled documentation example passed; packaged crate verified |
| Existing CrispSorter catalogue consumers | 20 unit tests, 2 catalogue integration tests, 11 CLI tests; new cross-crate API compatibility test passed |
| Existing CrispSorter production WebDAV contracts | 34 PROPFIND parser tests and 56 delta/metadata tests passed |
| CrispSorter check-wait helper | 8 new tests passed; queued workflows cannot be hidden by unrelated successful jobs or old retries |

Counts overlap and should not be added together. The million-row case uses synthetic database metadata, not a million-file disk scan. Platform variants in widget tests are not native Windows/Linux certification.

The live harness runs the actual desktop host and production local filesystem operations against app-owned temporary files. It verifies 80 MiB ext/NTFS sources remain byte-identical after preview and extraction, and that the original CSV survives XLSX creation. It substitutes disconnected account state and empty saved-bookmark resolution; it does not certify remote accounts or user-granted folders. Its source is `integration_test/native_storage_viewer_test.dart`.

The first live build exposed FinderExtension inheriting Runner's CocoaPods linker flags. Debug, Profile and Release now explicitly clear the extension's extra linker flags. The rebuilt live host passes, and the extension's linked libraries contain the native Apple frameworks without Flutter/plugins. This is separate from the already qualified filesystem parser changes.

The full archive run preceded preference-mock corrections in three test hosts. Those corrections change no production code and were checked in a separate 64-test run. Focused and broad phases retain their actual scope; earlier upstream source evidence remains attributed to its original commits.

## Scope and next release

Filesystem readers are bounded and read-only; their [ext](archive-ext-profile.md) and [NTFS](archive-ntfs-profile.md) contracts retain unsupported-layout, metadata and size limits. They do not mount or repair disks. SQLite remains the working catalogue index; CAF is optional portable interchange and does not encode scan completeness.

The local app version is 1.3.2+25. The signed universal macOS app was built from runtime checkpoint `436c7926`, installed and launched. The standalone CLI bundle was also built and installed as both `crispcloud` and `crisp`; a real scan → CAF export/import → offline ranking smoke passed. Imported CAF ranking returns valid data and the deliberate incomplete-coverage exit status 1, since CAF cannot certify original scan coverage. The existing v1.3.1 GitHub queue is left alone; no new release tag or store submission is created by this increment. Hosted cross-platform binaries, web deployment and TestFlight remain separate from these local results.
