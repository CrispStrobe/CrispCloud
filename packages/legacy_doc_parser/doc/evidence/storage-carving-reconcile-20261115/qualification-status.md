# Corrected parser qualification

The corrected runtime source was first saved and qualified at **5ba4993c24c88eb366ffbb4f5e16b8da6b418064**. It retains all five incoming PRs, repairs the reproduced preservation/limit defects, and uses mirror-safe evidence paths. Observed main `7df906d2` contributes source-equivalent merge ancestry and README capability bullets, now consolidated without changing production/test/dependency bytes; `main-reconciliation.json` records the object identities. Later qualification records identify their exact saved commit.

## Completed gate

`focused-fixed/` records **17 passing tests**, zero failures/errors/skips, at the exact saved source pin. Source, commit identity, package-resolution inputs and recorded tool hashes were unchanged. This includes the 13 previously failing regressions, three existing controls and an added positive en-US Windows1252 control.

The strict 17-file analysis and complete 143-suite ordinary parser run are still pending. Their exact inventories are saved alongside this status.

The standalone development graph uses archive 4.7.1, test 1.33.0 and XML 6.6.1. The host app's committed graph uses archive 4.6.0; host application acceptance is recorded separately on the byte-matched managed parser source. No dependency declaration or committed host lock was changed.

A separate read-only review found no concrete defect in aggregate accounting, bounded views, UTF16 piece scaling/scalar validation, or the explicit conservative charset profile. Runtime results above establish only their recorded scope, not native Office rendering or broad schema acceptance.

No GitHub Actions run was awaited or restarted.
