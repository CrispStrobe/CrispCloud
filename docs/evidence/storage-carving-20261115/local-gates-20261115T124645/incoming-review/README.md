# Observed remote source 41885d7d — qualification readiness review

**Fresh qualification is required after the three ODS regression cases are restored and the new gate plan is corrected for this workspace. The Linux golden additions retain exact comparisons and are suitable for that qualification.**

This review used immutable app commit `41885d7d1d67348f5abe3579b99d9d2951fc909f`, comparing it with previously qualified production source `20ee83ff965d5433aeb528ae84debdb304edcf4a`. The reviewer did not modify the app, move repository HEADs, run a runtime test, refresh remotes, or use CI. The previous 12-gate final audit remains valid for source `20ee83ff`; it must not be relabeled as acceptance of the new source.

## Material incoming changes and required scope

The new Quds pin is `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea`. Its ODS reader rejects stored cells where a horizontal merge still requires covered-cell tokens and admits at most 10,000 repeated comments. The ODS suite exercises both new paths. An engine `archive: ^4.0.0` development dependency is added; the committed host already resolves archive 4.6.0, but all actual package graphs still need resolving and freezing before accepted gates.

The new parser pin is `08296edbee08da013a8ff718798972552ccd03f7`. Its production library bytes are unchanged relative to the previous parser pin; one explicit damaged-compound recovery regression and final receipts are added. The separate parser owner is checking and qualifying that exact source. Its accepted counts must come from its new recorded results, even though the existing production behavior was already exercised previously.

Two added editor suites select five Linux-specific Word page images, while five default/macOS reference images also change relative to source `20ee83ff`. The exact suite inventories are:

| Manifest | Entries |
| --- | ---: |
| app suites | 65 |
| engine suites | 22 |
| editor suites | 11 |
| app strict analysis | 76 |
| engine strict analysis | 16 |
| editor strict analysis | 6 |
| CLI strict analysis | 1 |
| navigation capture | 1 separate suite |

The two added editor suites are `office_fidelity_golden_test.dart` and `office_structure_goldens_test.dart`. They add four test cases, making 18 exact golden comparisons: two import/reopen comparisons and 16 structure comparisons across three phases and four save cycles. These are source-derived scope expectations, not passing runtime counts.

Run the existing 12 selected gates after the final source is saved, using the expanded editor manifests. A fresh full app/engine/editor run plus four strict groups covers the concrete source risks. No duplicate focus run is needed unless a failure identifies a reason. Run the engine generator before its independent Office oracle, retain all generated outputs, and use fresh labels with exact prerequisite labels. Run the source, portable PNG, capture and independent navigation gates for one common new source/resolution digest. Navigation remains separate from the primary host count. The parser's full 144-suite development graph remains a separate qualification.

## Fix before freezing

1. **Restore removed ODS regression coverage.** The incoming audit confirmed that the currency-symbol copy-save, inherited styled-padding sparsity, and native-column-geometry copy-save cases were deleted rather than moved. Their behaviors are still supported and the new admission policy does not supersede them. Restore those exact cases in canonical Quds, then sync the resulting pin. No additional suite is needed because all three belong to the already selected ODS suite.
2. **Correct canonical checkout paths in the new runner.** Its source-integrity command uses sibling `quds_office_suite` and `legacy-doc-parser`. This workspace uses `QudsCanonical` and `ParserCanonical`. The runner is otherwise byte-identical to the previously audited driver. All six other copied executable helper files are also unchanged.
3. **Correct copied plan metadata.** The actual text manifests correctly contain 11 editor suites and 6 strict editor files, but `gate-plan.json` still says 9 and 4 and retains old integrated pins. `readiness-review.json` is a copied report for source `48432b5d`, not a new preflight. Retain historical records with their original scope, or replace the new copies with a current report. `provenance-overlay-manifest.json` also describes the earlier overlay rather than this new source.
4. **Finish graph setup before any acceptance gate.** Save the final app source and lock changes, resolve app/CLI/engine/editor graphs, and align each canonical checkout HEAD with the final app pin. The source audit intentionally requires exact canonical HEADs. Do not alter graphs or source while a gate runs.

## Linux golden review

All five Linux PNGs are exactly 800×1120 and their SHA-256 values match `word-pages-provenance.json`. The changed-pixel counts relative to the current default masters also match exactly: 5,399; 5,936; 1,468; 5,029; and 4,299 pixels. The saved bounding boxes use inclusive maxima; Pillow's exclusive maxima are one greater, so these are consistent coordinates rather than a pixel-data discrepancy. Detailed identities and pixel checks are saved alongside this report.

The tests still call the standard `matchesGoldenFile` with no custom tolerance or skipped comparison. Linux selects `goldens/linux/`; other systems select the existing default path. Both suites await `OfficeHostFonts.ensureRegistered`; the loader binds Arial to bundled Liberation Sans faces instead of relying on system fonts. DPR is 1 and viewport size is 800×1120. The import and create phases wait for actual authored picture colors before comparing, so an image-loading placeholder cannot silently become a passing expected image. The gate command does not update goldens.

I visually inspected all five Linux references. The import image contains readable heading/body/link/table/note/footer content and the actual colored picture. The create image contains its heading, floating frame text, rotated green picture, table and contents list. Edit page one contains the heading before the scripted column break; page two contains the moved frame, highlighted paragraph, merged table and updated contents. The remove image retains text and the remaining table while removing the authored image/frame/contents. The dense frame/text placement also exists in the prior master; this change does not establish fidelity against external Word rendering or resolve pre-existing layout limitations.

The reference provenance says capture used Flutter 3.44.0/Dart 3.12.0 and claims exact revalidation with Flutter 3.47.8. Its `source_commit` is descriptive prose, not an immutable commit. Therefore that statement alone is not source-bound acceptance. This workspace's recorded Flutter 3.47.8 / Dart 3.13.7 toolchain is appropriate for a fresh exact run against the new immutable source. Do not regenerate references or relax comparisons if that run fails; preserve the mismatch and inspect it first.

For a golden failure, Flutter's current local comparator writes master/test/isolated-diff/masked-diff PNGs under `packages/quds_office_editor/test/failures/`. Missing-picture diagnostics may also appear under the editor's `build/fidelity-diagnostics/`. Preserve these files with the failed raw receipt before cleaning or retrying. A successful run needs no reference rewrite; the baseline hashes are already covered by the source snapshot.

The optional Documents/Downloads corpus scanners remain excluded and must not be counted as passing acceptance. Actual test counts, source snapshot digest, and artifact hashes will be reported only from the new completed gates.

## Artifacts

- `qualification-plan.json`: exact inventories, incoming pins, preconditions, gate order and scope rules.
- `golden-identities.json`: immutable source paths, ten image identities, and upstream provenance.
- `golden-pixel-provenance-check.json`: independently recomputed pixel counts and coordinate convention.
- The exact PNGs were materialized in reviewer scratch for inspection. This plan package retains their identities rather than duplicate images; the canonical copies are at the immutable Git source paths recorded in `golden-identities.json`.

No runtime acceptance is claimed by this preflight.
