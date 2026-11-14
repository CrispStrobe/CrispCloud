# Parser audit, fifth pass — 13 November 2026

## Recovery status, checked 14 November 2026

The fifth-pass implementation survived the interrupted session. Its final
runtime and test checkpoint is
[`6b57d176fccd6f4b8b11bae2e7168f73e870e9dc`](https://github.com/CrispStrobe/legacy-doc-parser/commit/6b57d176fccd6f4b8b11bae2e7168f73e870e9dc).
The evidence upload reached
[`4de67fe946bd13304e5999759f1d9846e9a50864`](https://github.com/CrispStrobe/legacy-doc-parser/commit/4de67fe946bd13304e5999759f1d9846e9a50864),
then the implementation was merged into `main` in
[`83acdf1c8b6b1b6346f0744988ef3d15f9fa08ff`](https://github.com/CrispStrobe/legacy-doc-parser/commit/83acdf1c8b6b1b6346f0744988ef3d15f9fa08ff).
The recovery baseline is `731e37032e11a3bc1ae6bdb0475fdcb48067bda4`,
which additionally corrects canonical-path comparison in native-probe tests on
macOS.

**The evidence upload is incomplete.** The retained control archive describes
17 data archives and 14,103 files. Only data archives 001–004 were committed:
3,124 manifest files are present and 10,979 are absent. Every present manifest
file was checked against its recorded SHA-256; all five retained ZIPs also pass
their CRC checks. The original archives and manifest remain unchanged.

This report reconstructs the saved implementation and surviving receipts. It
does not replace missing historical files with later runs or treat a passing
receipt as proof that its entire input/output bundle remains available. See
the [evidence recovery index](evidence/parser-audit-20261113-fifth-pass/README.md)
and [compact recovery inventory](evidence/parser-audit-20261114/recovery-inventory.json).

## Saved corrections

| Area | Implemented change | Remote checkpoints |
| --- | --- | --- |
| Note references | Check story ownership and reference identities before visibility filtering, preventing hidden references from masking an active reference with missing note content. | [acef06c](https://github.com/CrispStrobe/legacy-doc-parser/commit/acef06c) |
| Compound containers | Bound metadata reads by physical sectors; validate fixed allocation geometry and an unambiguous root; share validated directory ownership between bounded and raw readers. | [7c57db6](https://github.com/CrispStrobe/legacy-doc-parser/commit/7c57db6), [4980dd7](https://github.com/CrispStrobe/legacy-doc-parser/commit/4980dd7), [0c4d3c1](https://github.com/CrispStrobe/legacy-doc-parser/commit/0c4d3c1) |
| Formatting values | Validate public-model scalar properties before XML emission; enforce Word measurement domains and preserve negative exact line spacing. | [8f7e610](https://github.com/CrispStrobe/legacy-doc-parser/commit/8f7e610), [52785b9](https://github.com/CrispStrobe/legacy-doc-parser/commit/52785b9) |
| Fields | Scope instruction/result visibility, retain source marker formatting, reject contradictory public runs, and add an explicit cached-results export choice. | [0a75324](https://github.com/CrispStrobe/legacy-doc-parser/commit/0a75324), [0971374](https://github.com/CrispStrobe/legacy-doc-parser/commit/0971374), [4fcef6a](https://github.com/CrispStrobe/legacy-doc-parser/commit/4fcef6a) |
| Field history | Retain the original displayed value and typed revision metadata for cached or inert fields, including caller-built fields without a raw source record. | [6dc8933](https://github.com/CrispStrobe/legacy-doc-parser/commit/6dc8933) |
| List labels | Distinguish literal percent text from real placeholders; preserve complete marker formatting, inherited properties and explicit resets; keep marker visibility independent of body visibility. | [7bb5a81](https://github.com/CrispStrobe/legacy-doc-parser/commit/7bb5a81), [8fb28ca](https://github.com/CrispStrobe/legacy-doc-parser/commit/8fb28ca) |
| Acceptance tools | Extend generated field, compound, public-model, list and measurement checks in portable JavaScript and SDK gates; correct the older hidden-body list expectation. | [96b8b6b](https://github.com/CrispStrobe/legacy-doc-parser/commit/96b8b6b), [6b57d17](https://github.com/CrispStrobe/legacy-doc-parser/commit/6b57d17) |

The preceding [fourth-pass report](parser-audit-20261113-fourth-pass.md) remains
a historical record. Its literal `%1`–`%9` rejection describes the earlier
checkpoint, not current behavior.

## Choosing field output

The default `LegacyWordFieldMode.preserve` retains supported complex fields,
their cached results and a field lock. Consuming applications can still
recalculate fields despite that lock.

Callers that need the stored display without active field evaluation can opt
into the saved cached-results mode:

```dart
final converted = convertLegacyWordToStructuredDocx(
  source,
  fieldMode: LegacyWordFieldMode.cachedResults,
);
```

This mode emits existing result runs through the ordinary bounded writer.
Instructions, nesting, source positions, flags, cached text and supported
revision evidence remain inert package evidence. Field editing and
recalculation are intentionally unavailable in this mode. It is not a claim
of identical layout in every application.

## Acceptance receipts that survived

The retained `runs/final/acceptance/portable-receipt.json` and
`schema-receipt.json` identify runtime `6b57d17`, clean source state and
unchanged source hashes before and after their runs. Their command logs are
present in data archive 001. These are **historical recorded results**, not
new acceptance results for the later merge or subsequent repairs.

| Historical gate at `6b57d17` | Recorded result |
| --- | --- |
| Dart tests | 3,345 passed |
| Formatting and analysis | Passed |
| Python controls | 166 passed |
| Retained corpus integrity | 24 checks passed |
| Compiled JavaScript | 30 groups passed |
| DOC-derived SDK outputs | 1,046 packages, zero validation errors |
| Separate public-model SDK outputs | 325 packages across six groups, zero validation errors |
| Total SDK scope | 1,371 packages |
| Source identity | Receipts retain 697 portable source hashes; the schema receipt also identifies its 432-file source inventory |

Test totals in the table follow the contemporaneous session transcript; the
surviving receipts independently confirm successful commands and source
identities, and retain the corresponding logs. The receipts also retain
repeat-generation and output identities. They can be
read from the surviving archive, but the incomplete bundle prevents a claim
that every originally inventoried artifact is still retrievable.

## Native results and remaining boundaries

The attached transcript reports 96/96 generated ASCII cases preserving cached
text in cached-results mode, versus 49/96 in active-field mode. It also reports
three-cycle passes for 11 targeted cached-field cases and 24 literal-label
cases, with 21/22 list-visibility cases passing; the remaining case was a native
label marked hidden that LibreOffice displayed.

**Those aggregate native results are transcript claims in this recovery.**
Their principal native artifacts, failures and final rerun bundles fall in the
missing archive range. They must not be presented as newly verified native
acceptance. A future native run needs its own input hashes, tool identities,
reports and complete retained output inventory.

The saved source improves literal-label and field handling, but it does not
establish universal active-field cache preservation, Microsoft Word rendering
equivalence, full CFB conformance, every numeral system, every revision
topology, or arbitrary drawing and layout support. The [fidelity contracts](fidelity-status.md)
continue to distinguish supported source structures, package validity and
native rendering.
