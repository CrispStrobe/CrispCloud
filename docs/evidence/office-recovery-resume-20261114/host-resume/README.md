# Resumed actual-host acceptance

The bounded native cohort passed **52/52 tests** on app implementation
`31838929276690e2804231c7928ddd8f1e46811c`, with canonical Office source
`c37789b596a6f6516d9e2cee78ce57ab33872b07`. It exercised device export, editor
dialog lifecycle, ribbon state, independently authored native workflows, and
save fidelity through five existing test files. Flutter 3.47.8 / Dart 3.13.7 ran
the actual host harness. All 4,739 recorded inputs remained unchanged.

The new fill case uses the actual Bold and Align center toolbar actions, then
three real intercepted cloud uploads and reopen cycles. Each saved workbook
retains the exact independently authored gradient and pattern definitions, plus
the edited bold/alignment values. Every upload, including the first, is checked
against the authored source definitions.

## Source and execution records

- `inputs/` retains the pre-execution source map, dependency lock/config/graph
  byte snapshots, native setup versions/checksums, and both committed and
  expected collected pubspec views. All 2,174 managed Office files were checked
  before execution.
- `execution/attempt-1/` preserves a failed compiler-toolchain discovery attempt
  that stopped before any Dart tests. It changed no source inputs.
- `execution/attempt-2/` preserves the successful full log, run status, compiler
  launchers, native-hook receipts, original workbook bytes, and coverage
  verification status. The existing CI helper temporarily selected system
  SQLite; committed pubspec bytes were restored after collection and again
  after receipt verification.

## Scoped coverage

`coverage/lcov.info.gz` and `coverage/collection-receipt.json.gz` retain the
complete raw LCOV and collection receipt as lossless gzip files.
`coverage/retained-bytes.json` records both original and stored byte hashes;
`coverage/coverage-report.json` is the full verified report.

The selected cohort executed **1,287 of 3,045 instrumented native host lines
(42.3%)**. Eight native files were not instrumented and are listed explicitly.
One browser-only source is reported separately, as is a verified declaration-only
file. This is a bounded cohort, not the full host coverage gate; its percentage
is not comparable to the historical full-cohort percentage or branch coverage.

## Independent schema findings and fixture correction

`external/native-fill/` retains independent OpenXML SDK 3.3.0 results and exact
package bytes. All three actual saved workbooks pass with zero errors. The
authored source has one unrelated font-child ordering error: color precedes
size. That initial failure is preserved.

`external/font-order-diagnostic/` independently confirms that swapping only those two
font children produces a schema-valid source, with every other uncompressed
ZIP part unchanged. It is explicitly a scratch diagnostic, not an actual host
acceptance run. Canonical checkpoint `3543b29a2daa82279777802df8728d72dc96e9c5`
corrects the fixture, and app checkpoint `9101520b12b7a9f17af10757775b9f6e98cbc4bf`
synchronizes it. All production code and fill definitions are unchanged.
On the corrected app source, the native-fill host case was executed again and
**passed**, using the actual toolbar, upload and reopen path. Its 4,739 input
hashes stayed unchanged. The only changed inputs from the 52-test cohort are
the authored XML fixture and canonical manifest; all production and test code
remain identical. `execution/attempt-3/` retains that separate result and exact
workbooks. `coverage-corrected-input/` retains its own LCOV, verified receipt and
scoped report; this repeated case is not added to the earlier unique test count.

The final independent result in `external/attempt-2/` is **four files, zero
schema errors**: the corrected authored source plus all three actual host uploads.
The SDK validator's existing self-test passed immediately before validation,
and every file hash matched before, during and after validation. Exact package
copies, command logs and the host input capture are retained alongside the report.
`external/` records source, build, SDK/NuGet versions, official download
locations, checksums and collector source without embedding toolchain binaries.

## Archive verification

`acceptance.json` summarizes the separate measured scopes. The independent
`source-audit.json` binds every one of the 4,739 collected inputs: 4,736 exact Git
blobs, the single retained system-SQLite pubspec view, and two generated package
metadata snapshots. The pre-collection map matches 4,737 Git blobs and those two
generated snapshots. It also verifies the complete raw LCOV against its receipt.
There are no unexpected differences or unrecoverable recorded input entries.
External dependency, SDK and native runtime payloads are outside that inventory.

`retained-artifacts.json` records the relative path, byte length and SHA-256 of
every other file in this directory. `external/publication-manifest.json` retains
the validator's independently produced 39-file manifest with its original layout.

No new physical-device, live-provider, browser-execution or rendered visual
comparison is claimed by this native cohort. Historical results remain attached
to their own measured sources.
