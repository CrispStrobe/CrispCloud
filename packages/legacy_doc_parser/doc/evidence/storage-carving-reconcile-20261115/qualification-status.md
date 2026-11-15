# Corrected parser qualification

## Current accepted source

The app-facing parser source pin is **`9bdcc7eba3f1ce80b7d834d7740895774eeca615`**. It retains all five incoming parser PRs and observed main `7df906d2643d1fec39c49fc795733316a49f3278`, the bounded recovery/Unicode/story-boundary corrections, and the subsequent typed compound-directory recovery correction. Later receipt commits leave production, tests and dependency declarations byte-identical to this pin.

The final correction is confined to `conversion.dart`: explicit `FormatException` and `CfbfException` branches share the same opt-in, DOCX-only bounded text recovery helper. If no text can be recovered, the original structural exception is rethrown. `_plainTextOrNull` recognizes those same two structural exception types. Unrelated exceptions and conversion-writer errors are not swallowed. Reader limits, encryption checks, structured parsing, and DOCM handling are unchanged.

## Current completed gates

| Gate | Recorded result | Exact saved head tested | Raw evidence |
| --- | --- | --- | --- |
| Host-shaped damaged-directory regression and controls | 9 passed; no failures, errors or skips | `9bdcc7eba3f1ce80b7d834d7740895774eeca615` | `directory-focused-fixed/` |
| Strict analysis with fatal infos enabled | All 18 incoming/corrected Dart files; no issues | `fde5685965db83e9cfb6807ecba1205438d7e819` | `directory-strict-analysis/` |
| Complete ordinary parser inventory | All 144 requested suites; 4,131 passed; no failures, errors, skips, missing or unexpected suites | `337b2fad504ce68f9e5e5053ae859bb5905f3dd8` | `directory-all-parser-final/` |

Every gate records unchanged before/after source bytes, commit identity, resolved package inputs and tool hashes. Exact commands, machine streams, per-suite results and input snapshots are retained. The complete inventory is `all-parser-directory-suites.txt`; the analysis inventory is `analysis-directory-files.txt`. The full run includes both the original 17 reconciliation regressions and the nine subsequent directory-recovery checks.

The damaged-directory fixture matches the host failure: allocation metadata and referenced WordDocument/CLX streams remain intact, while the first directory sector is zeroed. It verifies both recovery entry points, explicit text-only status and omission disclosure, source immutability, exclusion of unreferenced private bytes, strict/default refusal, DOCM refusal, encryption/obfuscation refusal, missing-FIB refusal and the 64 MiB input bound.

## Preserved failure evidence and earlier gates

`baseline/` records the original source reconciliation defects on saved regression head `c1559d9d2efa8651c0f9a7759473720e3155f9b5`: 16 tests, three controls passed and 13 failed. The bounded recovery, Word98 signature, Word6 Unicode/charset and following-story annotation corrections were then saved. `focused-fixed/` records 17 passing checks on `5ba4993c24c88eb366ffbb4f5e16b8da6b418064`, including an added positive en-US Windows1252 control.

`strict-analysis/` and `all-parser-final/` preserve the earlier clean 17-file analysis and 143-suite/4,122-test run. Those receipts describe their original inventory and source; the later host gate exposed the separate typed compound exception gap. Observed main was consolidated at `09c8b3731edb60bf6e5309578260af36b9433570` without changing production/test/dependency bytes; `main-reconciliation.json` records the Git object identities.

`directory-baseline/` reproduces the later host failure on saved regression head `d9d182c6b25544c3484f54a3d0f0e23810579cda`: nine tests, seven controls passed and two recovery entry points failed with `CfbfException: Invalid compound root directory`. Source, HEAD, package inputs and tools stayed unchanged. These raw failures were saved remotely at `ac4c88ca6f4d583d3e7f66cfe7f4ee797b1766b6` before production was corrected.

## Scope and reproducibility

The standalone development graph uses archive 4.7.1, test 1.33.0 and XML 6.6.1. The host app's committed graph uses archive 4.6.0; host application acceptance is recorded separately on byte-matched managed parser source. No dependency declaration or committed host lock was changed.

Input snapshots establish before/after equality, not a hermetic cache snapshot or proof against transient writes. These unit and analysis gates do not claim native Office rendering or broad schema acceptance. An independent read-only review of the earlier correction found no concrete defect in aggregate accounting, bounded views, UTF16 piece scaling/scalar validation, or the conservative charset profile.

Raw package-snapshot bytes remain intact under mirror-safe evidence names. `dependency-setup/evidence-path-mapping.json` records the two renames; the original baseline snapshot index and original output index remain available. No generated-directory exclusion in the managed-mirror tool was weakened.

No GitHub Actions run was awaited or restarted. Each source, failing baseline and completed gate was saved to the remote integration branch before proceeding.
