# Latest integration continuation

## Saved integration scope

Current main through `4933ffc2`, ODF `7dec00fb`, both parallel qualification histories, and all observed canonical Office and parser work are incorporated. The finite final refresh includes app PR 120 through `c8fd8d76` (including `b0e0f174`), canonical ODS dates/comments through `9cc8c6e9`, and parser main `7df906d2`. Exact ancestry, overlapping-file equivalence and resolution are recorded in `incoming/late-refresh-audit.json` and `final-source-reconciliation.json`. Later upstream work is outside this recorded cohort.

The app mirrors canonical Office `b4950d60eb03365c1798d2dfc66a2c85a4e61be5` and standalone parser `09c8b3731edb60bf6e5309578260af36b9433570`; all **2,274 managed files** match their source pins. The latest source is checkpointed before runtime qualification.

## Corrections and preserved failures

The ODS baseline first exposed a duplicate test helper, then reproduced default columns shrinking from **81px to 64px** after copy-save. Both failed gates remain unchanged. The canonical correction preserves native default/base geometry and tests repeated direct and isolate saves. The late date/comment integration preserves authored date order and literals, month/weekday rendering, and namespace-aware bounded annotations kept separate from cell values.

The parser baseline reproduced 13 failures in 16 targeted cases. Canonical corrections cover cumulative recovery work/input bounds, authoritative stream bounds, Word6 Unicode/declared encoding handling, Word98 identification and half-open story cleanup. All 17 revised targeted regressions pass on the identical production/test bytes retained by the current source pin. Complete parser strict/full-suite qualification is recorded on its canonical integration branch separately.

The host now represents unreadable source inventory as unknown, propagates explicit text-only recovery classification, requires localized loss disclosure and acknowledgement, and retains create-only copy saving and retry ownership. A separate source review covers this host integration.

## Local qualification in progress

The final selected cohorts contain **63 app / 9 editor / 22 engine suites**. Strict analysis covers **72 app / 16 engine / 4 editor / 1 CLI files**. The standalone parser runs all 143 unit suites under its separately recorded development dependency graph. Test counts will come from completed raw machine reports, not the predecessor totals.

Remaining source-bound gates include strict analysis, the selected runtime cohorts, independent checks of actual Office outputs, source/notices controls, actual VM and compiled-JavaScript PNG recovery, and real font-backed worksheet navigation captures with independent artifact and visual review. Development runs and retries never inflate final acceptance totals.

App and CLI locked offline resolution passes with their committed locks unchanged. Native hooks remain enabled and use the verified real toolchain. Each completed gate, including failures, is saved remotely before the next gate. Checkpoint commits use `[skip ci]`; no GitHub Actions run is awaited or restarted.

## Evidence boundaries

The independently revalidated predecessor evidence comprises 996 tests, Office output/oracle checks, source controls and VM/JavaScript PNG proof on its original source. Those raw receipts remain preserved and are not acceptance for this newer combined source. External native Office applications, other operating systems and broad Open XML schema certification remain separate scopes. Two optional HOME-scanning corpus harnesses are preserved without execution or vacuous acceptance.
