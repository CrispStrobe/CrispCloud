# Office host gap-closure evidence — 12 November 2026

The tested app implementation is `5202d362a929c30266519dee178a441884056ca0`.
Its 352 managed Office files match Quds source
`a9bd470a4807c65f65271be896703e587c12de00`.

`final-app/producer-acceptance.json` records the complete mandatory app gate:
873 engine and 140 host tests, 344 engine Python controls, seven sync controls,
ten host-inventory controls and nine coverage controls. Both exact inventories
passed (277 engine outputs, 59 actual host captures). No test was skipped in
this gate. Pubspec/lock restoration and the clean tested tree are recorded.

`final-app/external-summary.json` records all 336 exact inputs passing Open XML
SDK validation. The unchanged native renderer additionally converted the eleven
actual host XLSX/PPTX/DOCM/DOTX/DOTM uploads to 23 pages with no failures. The
full source-engine native corpus is reported in Quds; this supplementary host
probe does not claim repeated-save equivalence for all host files.

`host-coverage.json` records 2,223/3,558 executed instrumented lines (62.5%), with
all ten declared host integration files present. Its scope includes the new
captured-copy target, conversion action and dialog; six reusable format modules
are maintained and measured in Quds. Earlier coverage percentages have a
different denominator and should not be compared directly.

`archive-manifest.json` lists every exact receipt copy and its original path,
size and hash. Full input packages, PDFs/PNGs/text, LCOV and raw logs stay outside
Git at their recorded validation paths. Reproduction sources are included under
`final-app/runtime/`. The artifact index inside `final-app/` also describes the
larger original evidence directory, including its generated artifacts.

`focused-format-refresh.json` attributes incoming Office commits and the 64
source/61 host focused tests. `main-refresh-acceptance.json` records 69 local
upstream-merge tests and four SFTP prerequisite skips. These are scoped earlier
cohorts, separate from final mandatory acceptance. `remote-audit-before-pr.json`
records the timed branch/PR audit and queued Actions; it does not claim remote
CI success or describe PRs created afterward.
