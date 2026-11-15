# Corrected parser qualification

The corrected runtime source was first saved and qualified at **5ba4993c24c88eb366ffbb4f5e16b8da6b418064**. It retains all five incoming PRs, repairs the reproduced preservation/limit defects, and uses mirror-safe evidence paths. Observed main `7df906d2` contributes source-equivalent merge ancestry and README capability bullets, now consolidated without changing production/test/dependency bytes; `main-reconciliation.json` records the object identities. Later qualification records identify their exact saved commit.

## Completed gates

`focused-fixed/` records **17 passing tests**, zero failures/errors/skips, at the exact saved source pin. Source, commit identity, package-resolution inputs and recorded tool hashes were unchanged. This includes the 13 previously failing regressions, three existing controls and an added positive en-US Windows1252 control.

`strict-analysis/` records a clean **17-file analysis with fatal infos enabled** at saved `09c8b3731edb60bf6e5309578260af36b9433570`. It reports no issues; source, commit identity, package inputs and tool hashes stayed unchanged. This source-equivalent main-consolidation commit is the app-facing source pin.

`all-parser-final/` records the complete ordinary unit inventory: **143 requested suites and 4,122 passing tests**, with zero failures, errors, skips, missing suites or unexpected suites. The exact saved receipt head was `97c930ba336f120863bb526f4796284aba344cca`; production, tests and dependency declarations are byte-identical to app-facing source pin `09c8b3731edb60bf6e5309578260af36b9433570`. Source, commit identity, resolved inputs and tool hashes stayed unchanged during the gate. The raw machine stream, per-suite results, exact inventory, and before/after snapshots are retained alongside this status.

The standalone development graph uses archive 4.7.1, test 1.33.0 and XML 6.6.1. The host app's committed graph uses archive 4.6.0; host application acceptance is recorded separately on the byte-matched managed parser source. No dependency declaration or committed host lock was changed.

A separate read-only review found no concrete defect in aggregate accounting, bounded views, UTF16 piece scaling/scalar validation, or the explicit conservative charset profile. Runtime results above establish only their recorded scope, not native Office rendering or broad schema acceptance.

No GitHub Actions run was awaited or restarted.

## Host-discovered compound-directory gap

The host integration gate exposed a case absent from the original 143-suite inventory: valid allocation metadata and intact referenced Word/CLX streams with a zeroed compound root directory. The underlying reader throws `CfbfException`, while the conversion fallback currently catches only `FormatException`. A generated canonical fixture now matches that host damage pattern and checks explicit recovery, source preservation, strict/default refusal, DOCM refusal, encryption/obfuscation refusal, missing FIB refusal, and the input bound. The original successful gates remain scoped to their recorded source and inventory; this correction has not yet passed acceptance. The new exact inventory contains 144 ordinary suites.

`directory-baseline/` reproduces that host failure on saved regression head `d9d182c6b25544c3484f54a3d0f0e23810579cda`: **nine tests, seven controls passed and two recovery entry points failed** with `CfbfException: Invalid compound root directory`. Source, HEAD, package inputs and tool hashes were unchanged. The raw failures were saved before modifying production code.

The correction is limited to `conversion.dart`: explicit `FormatException` and `CfbfException` branches share the same opt-in DOCX-only bounded recovery helper. A failed fallback rethrows the original structural exception; `_plainTextOrNull` also recognizes typed compound-reader failure. Unrelated exceptions and conversion-writer errors are not swallowed. Reader limits, encryption checks, structured parsing and DOCM handling are unchanged. Fresh focused, strict and complete 144-suite gates are pending for this source.
