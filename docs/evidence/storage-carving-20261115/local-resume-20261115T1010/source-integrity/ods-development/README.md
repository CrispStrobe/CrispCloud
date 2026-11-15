# Canonical ODS development regressions

These are fresh development runs of the canonical Quds ODS reader and its
regression suite. The base commit is
`793c64ac4fc2e896706aa65c13eaa70bd27f7267`. They do not substitute for the
final source-bound combined application/engine gates after canonical saving
and guarded host synchronization.

The original reader failed 11 of the 15 visible tests, with four passing.
The initial patched reader passed all 15, with zero failures, errors or skips.
A subsequent review added two quoted-sheet-reference regressions: both failed
against that initial fix while the prior 15 still passed. The final reader
preserves reference tokens as well as literals and passes all 17 tests, with
zero failures, errors or skips. Strict scoped analysis of both changed Dart
files also passes with no issues.
`baseline-tests.jsonl`, `fixed-tests.jsonl`,
`quoted-reference-baseline-tests.jsonl` and `quoted-reference-tests.jsonl`
retain all raw machine events,
including the separate hidden loading event. The summary totals exclude that
hidden event. No test or assertion was removed after the baseline failures.

The regressions cover:

- Internal repeated blank rows preserve later values and formula addresses;
  their row heights survive XLSX save/reopen, while trailing repeated padding
  allocates neither cells nor large row-height maps. The 100,000-row boundary
  remains enforced.
- Horizontal merge origins reserve columns once. Explicit, omitted, repeated
  and additional covered placeholders preserve the following cell's address
  across XLSX save/reopen. Consecutive origins clear the previous reservation,
  and spans remain within the 4,096-column boundary.
- Formula separators, references and namespace prefixes are translated outside
  quoted string literals. Semicolons, bracket-like text, empty strings and
  doubled quote escapes remain unchanged inside literals, including after XLSX
  save/reopen. Quoted sheet names containing semicolons or
  `COM.MICROSOFT.` remain unchanged and keep the quoting needed for a valid
  spreadsheet reference.

The canonical checkout had no existing or tracked `pubspec.lock`, so
`flutter pub get --enforce-lockfile` refused to resolve. A normal
`flutter --suppress-analytics pub get` then generated a development workspace
resolution from the unchanged dependency constraints. Its lock, package config
and package graph are retained as compressed files here. No package manifest
or tracked dependency declaration was changed. The final patched test and
analysis receipts verify that these resolution inputs and both changed Dart
files remained unchanged across their commands.

`baseline-regressions.patch` preserves the added tests against the original
reader; `canonical-first-fix.patch` preserves the initial15-test passing
fix, and `canonical-fix.patch` contains both final changed files.
`tested-inputs.json` records their SHA-256 and Git blob identities.
The parent workflow saves these canonical changes remotely and runs guarded
host synchronization before any final clean-source acceptance is recorded.
