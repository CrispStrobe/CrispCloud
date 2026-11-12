# Clean continuation validation at 7308125

The exact clean source `730812534e8dc045d6d97f600218228f05c51b97` (Git tree
`c69a9b26fff0d8b6c22519321f34c2781f4943d6`) passes **725 Dart tests, 130 Python
controls, formatting, fatal-info analysis, 22-source corpus integrity, document
JavaScript acceptance and 51 media JavaScript checks**. Every captured tracked
source, fixture and dependency-resolution file stayed unchanged throughout the
portable gate. `portable-report.json.gz` retains the complete source inventory,
SDK executable hash, exact commands, exit codes and log hashes. All stage logs
are retained losslessly.

The independently rebuilt Open XML SDK 3.3.0 accepts **196 required DOCX
outputs with zero errors**. Exact inventories, determinism, original input
hashes, validator source and assembly hashes, and positive/negative controls
pass. This includes all 24 textbox table-context controls and four retained
native header/footer-ending controls. `schema-report.json.gz` and
`schema-schema-validation.json.gz` retain the complete gate reports.

The earlier 192-case schema pass is also retained as
`pre-retraction-schema-report.json.gz`. It measured the subsequently rejected
textbox-depth reset. Its success did not establish rendered fidelity: the
[independent native counterexample](../textbox-table-context-20261112/README.md)
found a 12-point regression, and the reset was retracted. The final source keeps
the original table-depth behavior and the bounded
[header/footer table recovery](../header-table-boundary-20261112/README.md).

`raster-storage-native.json` records the independent two-page Poppler check:
all-pages PPM and per-page gzip reproduce identical raw PPM hashes, text and
geometry. Gzip changes storage, not the RGB/DPI comparison contract. Runner
failure controls additionally require verified compressed bytes and a saved
page receipt before removing a raw page.

The [native corpus evidence](../native-corpus-7308125/README.md) records its
separate execution scope and completion state. Native geometry, package
validity, source-byte retention and app category-presence checks remain separate
results; these gates do not certify arbitrary Word documents or Microsoft Word
rendering. No source golden was updated.

`summary.json` records compressed and original hashes/lengths for every retained
log/report. Standard Python `gzip.decompress` reads the compressed files.
