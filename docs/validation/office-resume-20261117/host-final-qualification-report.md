# Final focused CrispCloud qualification — 17 November 2026

## Accepted source and result

The focused host qualification and independent raw-evidence review passed on host `511361a4623e6ddf787b5cccfaed4ba14ae1899f` (tree `bc7916f9d5949c6611a96510f62bebb8b43668a7`), with canonical Quds `def52d84f3c3c5ce22c44d2620ecfa08d77780a7` and standalone parser `4895712158127b2fc930d796e17035c3ca0dac62`. The accepted run executed **96 Dart/Flutter cases and 28 Python controls, 124 substantive passes total**, with no host failures or skips. All 11 required commands passed.

| Cohort | Passed |
| --- | ---: |
| Annotation preview | 8 |
| Complete document service | 41 |
| Bundled notice registration | 2 |
| Zotero service | 21 |
| Zotero citing transport | 16 |
| Zotero ribbon | 2 |
| Supplemental writer, list and note probes | 6 |
| Vendor/parser Python controls | 28 |

The prior requirement of 80 Dart/Flutter cases plus 28 Python controls remains covered. This run adds eight annotation cases and two document-service cases, and executes the six supplemental writer-to-host probes. Loading/setup events are excluded from totals. The reviewer independently checked exact suite sets, unique terminal IDs, all raw log hashes and the Python case IDs.

## Static gates and preserved inputs

Strict analysis passed for 14 host targets and all 61 selected vendor targets. The host and viewer formatting scopes passed. Vendor formatting passed for 43 authored targets; 18 generator-owned files were excluded only after verifying their exact committed manifest hashes and generator headers. They remained within strict analysis, vendor guards and source fingerprints. No generated payload or lint suppression was added.

The before/after tracked vendor guards verified **2,603 managed files: 746 canonical and 1,857 standalone parser files**. All 3,829 source inputs, 6,020 dependency inputs, six captured runtime inputs and supplemental probe bytes remained unchanged. The temporary analyzer graph was removed to restore its original absence. The production-bound wrapper retained 107 locked packages, including all 97 hosted package/version/archive pins, using Flutter 3.47.8 and Dart 3.13.7.

The independent source-preservation audit binds these exact published commits. It retains 50 canonical Zotero paths, 46 host Zotero paths, 20 host customizations and six original notice files. Twelve inherited mode differences remain unchanged; no new source-preservation failure was found. Its complete JSON and auditor are included in the accepted evidence archive.

## Retained failures and corrected contracts

Attempt 001 remains a failed, source-bound record at host `fe2a1d026c7e4725723b88ba1b6bbadb010d74e8` / canonical `4c49b0435bc6611221bc49b58b15e735059467ff`. Its full logs, exact original probes/runner, unchanged-input maps and original preservation audit remain in `host-final-qualification-failed-001-20261117.tar.xz`.

The note probes were corrected against behavior already established in the preceding canonical source: note-reference style spans, one modeled automatic separator, and visible paragraph projection of note tables. Exact cached text, authored spaces/tabs/newlines, namespaces, note ownership and input model identity remain asserted. A separate aliased-table and foreign-namespace authored input verifies hidden payload exclusion from previews while preserving exact raw XML. The other two probe files are byte-identical. The only production amendment was the canonical one-token `const` correction reported by strict host analysis, mirrored through the guarded source sync.

The historical annotation inverse control is also retained separately: seven expected assertion failures and one clean-case pass with the corrected raw-XML header contract. Its passes are not added to the accepted final-source totals. The final annotation suite passes all eight cases with the same corrected test blob.

## Scope

This is a focused genuine-source qualification through the locked host dependency graph, not a full application dependency resolution or release build. Full viewer/export-dialog acceptance, live Zotero accounts, Word/LibreOffice interoperability and native/Wasm Harper execution remain separate scopes. No optional GECToR model or native binary was added to the host. No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.
