# ODS app merge reconciliation

This is development evidence for the pending merge of the concurrent local
qualification branch at `8a4cc8b62c75461a05f58cc97386191cbca9f05c` into the
integration branch after its current-main checkpoint at
`65e462b1`. It is not final source-bound qualification of the combined app and
canonical Office sources.

Only `lib/services/office_document_service.dart` and
`test/office_document_service_test.dart` were reconciled by this worker. The
incoming namespace-aware ODF traversal, row groups, typed booleans, shared
rendered-cell/text budgets, and explicit out-of-grid refusal were retained.
The combined row reader also reserves merged footprints and consumes explicit
covered-cell placeholders without double-counting them, while retaining
compatibility with producers that omit those placeholders. Empty row runs are
materialized only when later content needs their coordinates. Trailing padding
therefore allocates no expanded rows. CSV removes only generated trailing line
separators, preserving leading empty rows and cell whitespace.

All incoming service test declarations remain. Five distinct cases from the
integration parent remain in addition: omitted covered placeholders, interior
blank rows with large trailing padding, leading blank rows with cell
whitespace, explicit/repeated covered placeholders, and data following a row
gap outside the supported grid. The last case now requires explicit refusal
and no partial preview, matching the stronger incoming import policy.

Both files were formatted with the pinned Dart toolchain. The focused
development command and exact input SHA-256 hashes are recorded under
`attempt-01/`. Its raw stdout is JSONL, raw stderr is separate, and the
completion summary records the exit code, test events, and whether the two
source hashes stayed unchanged. Native hooks are enabled. This attempt does
not run the new ODS editor workflow suite; that suite requires the final
combined canonical reader and belongs in the later complete app cohort.

The focused run completed at `2026-11-15T09:43:57Z`: exit code 0, all 32 real
tests passed, and the JSON run-completion event reports success. Both assigned
source hashes stayed unchanged. Total elapsed time was 153.393 seconds,
including the first genuine native-hook builds. The raw stderr retains a
Visual Studio discovery notice; it did not prevent the Linux run from passing.
