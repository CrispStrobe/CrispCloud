# Hosted Office acceptance at fb81b2ac

The official-branch [Office fidelity integration run 43390627156](https://github.com/CrispStrobe/CrispCloud/actions/runs/43390627156) completed successfully on **13 November 2026 at 08:45:22 UTC**. Both `host-roundtrip` (job `131769379446`) and `external-schema` (job `131783096763`) completed successfully, with every recorded step successful.

This is an evidence-only checkpoint. The measured hosted source is **`fb81b2ace557964459189afd7c0c7d76b2c9557d`**, tree **`a14d066f1179ea00e20eaa3431aec0dd4fe05a5f`**. Its application runtime is the previously measured **`86d5a218853d8441afe8bc28f19cfe0adf4cd71e`**, tree **`765bf752b0095233192d38e678941e7ca92a76b8`**; only documentation and local acceptance evidence were added between those commits. The exact vendored parser remains **`c5ff75e76163d9abbdd44a9f2a7c5ad210929289`**. Later evidence commits do not change those test identities.

## Observed results

| Check | Actual result |
| --- | --- |
| Committed Office source gate before test hooks | 1,679 tracked inventory files verified |
| Hosted toolchain | Flutter 3.47.8; Dart 3.13.7 |
| Host test invocation | Exact ordered inventory of 30 Flutter test files; 202 successful host test events retained |
| Shared engine test output | 1,165 successful Dart test events and 440 Python controls retained |
| Actual host export inventory | All 122 required packages present, with zero inventory failures |
| Host format breakdown | 99 DOCX, 4 XLSX, 16 PPTX, and one each DOCM, DOTM and DOTX |
| Office host line coverage | 2,624 / 4,138 instrumented lines, 63.4%; all 12 scoped source files instrumented |
| Open XML SDK validation | 468 packages, zero errors: 122 host exports plus 346 engine exports |
| SDK implementation | .NET SDK 8.0.428 and source-pinned DocumentFormat.OpenXml 3.3.0 |
| SDK negative controls | 8 valid Word packages, 4 invalid XML controls, 12 mismatched types and exact discovery |
| Actual host native rendering | All 122 host exports rendered; 158 pages retained |
| Native renderer | LibreOffice 24.2.7.2, with Poppler-produced RGB rasters and extracted text |
| Repeated app/engine saves | 33 three-save groups; 66 exact comparisons of save 1 against saves 2 and 3, covering page count, extracted layout text, decoded RGB dimensions/fingerprints and applicable picture evidence |
| Authored picture geometry checks | 18 exports: 12 slide PNG insertion cases and 6 Word GIF/JPEG insertion cases |
| Other native scope | 23 unnumbered files rendered; zero independent sibling-baseline comparisons and zero page-order-baseline comparisons in this host-only set |
| Native exclusions and retries | Zero schema-only exclusions; all 122 conversions succeeded on their first attempt |

The success-event counts are counted from the complete hosted reporter log. The exact 30-file invocation and successful completion are also bound by the coverage collection receipt. The log retains the 14 host-inventory controls, 34 coverage controls and 77 external/native helper controls. Negative-control diagnostics in those helper tests are retained verbatim; the actual 122-file rendering report has no failures or exclusions.

The 66 comparisons establish stability across three app/engine save outputs in each group, with each output independently opened and rendered by LibreOffice. They do not measure three native DOC save bridges, PDF-byte equality or per-word bounding-box equality. With no independent sibling source baseline in this host set, repeat stability alone cannot establish that every first export matches its original document. The 18 authored picture cases provide separate package, geometry and actual raster-bound checks for those cases. The other 23 files have rendering observations without a three-save comparison. The remaining engine packages received SDK validation in this job; they were not included in its actual-host native render set. The 63.4% figure measures instrumented lines in the 12 scoped Office files, not whole-app coverage, branches or comprehensive Office fidelity.

## Committed source and the SQLite test boundary

The exact committed workflow ran `python3 tool/verify_office_fidelity.py --require-tracked` before dependency setup and before its temporary system-SQLite wrapper. The recorded 3,971 coverage inputs comprise **3,966 committed inputs and five generated resolution inputs**. Every recorded committed input matches the source inventory except `pubspec.yaml`, which contains the deliberate hook during tests:

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| Committed `pubspec.yaml` | 10,756 | `c3a86f613b810ee66f7b12dbcaa0161e2d616846512ef0073bc3effc80a665aa` |
| Test-time `pubspec.yaml` with the exact 89-byte hook | 10,845 | `66e6c8810da5200bc377ea187673cdafbf5386abe150be499d9654ff5b64a2de` |

The retained wrapper adds the `sqlite3: source: system` test hook and restores the original pubspec bytes in `finally`. The actual log identifies `libsqlite3.so` version 3.45.1 and successful foreign-key/transaction checks, with optional FTS5 available. The coverage collector verifies its recorded inputs remained stable during the test invocation. The coverage summary's instrumented-source status covers the 12 scoped Office Dart files; it does not assert the test-time pubspec was unmodified.

The workflow did not emit a complete post-hook Git snapshot. Restoration is therefore described as the source-defined wrapper behavior, not an independently captured final hosted tree. The earlier local acceptance and original-checkout transition receipts separately preserve actual local lockfile, version and package-configuration checks. No hermetic release-SQLite or complete installed-dependency claim is made.

The five generated inputs are the root and engine package configuration/graph files and the engine's generated lockfile. Their observed hashes remain in the original collection receipt. The root lockfile hash remains identical to committed source. The verifier reconstructs the exact hooked pubspec, checks every recorded source hash, binds all 1,679 Office inventory entries and checks the complete ordered Flutter command and recorded runtime.

## Retained artifacts

The two original GitHub ZIP archives are retained completely, split only to keep Git blobs bounded. **No outputs or binaries were omitted from either ZIP.** Concatenating parts in numbered order reproduces the exact original archive, including compression and ZIP metadata.

| Artifact | GitHub ID | ZIP bytes | Members | Uncompressed bytes | SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- |
| `office-host-fidelity-evidence` | 14022440972 | 3,787,466 | 519 | 7,504,304 | `36e2cd7585656cc2e33c038bd499c2d19e0c39427b453ad7d1dcb282a65d7805` |
| `office-host-schema-evidence` | 14022222719 | 3,026,036 | 527 | 4,533,364 | `c04ab98780403ab553489528875e29ab0b7f66b81e70ba4d6cb63281a03da69c` |

`records.tar.xz` retains the final run/job/artifact API observations, complete decoded job logs, exact artifact member manifests, complete committed-source inventory, selected exact source files, independent source review and checkout/integration receipts. The earlier host-success/external-queued snapshot remains historical evidence; final success is bound separately to the completed run and both completed jobs. Signed artifact-download URLs are not retained.

The external ZIP contains the 122 byte-identical staged host packages, complete SDK and host-inventory reports, 122 PDFs, 158 PNGs, 122 extracted-text files and the complete native report. Each conversion attempt retains its exact argv, input hashes, stdout and stderr. There were no failed conversion attempts to omit. The source-defined three-attempt SIGKILL-only retry policy remains in the report, with the actual first-attempt-only result explicit.

## Verification

From the repository root:

```sh
python3 docs/evidence/office-hosted-fb81b2ac-20261113/verify.py --repository .
python3 docs/evidence/office-hosted-fb81b2ac-20261113/test_verifier.py
python3 -O docs/evidence/office-hosted-fb81b2ac-20261113/test_verifier.py
```

Verification checks the outer seals, both original GitHub ZIP digests, all member bytes and ZIP metadata, API/source/job identities, all 122 required host paths and owning OPC parts, all 468 SDK package hashes, source/coverage/command bindings, all staged native inputs and every PNG's independently decoded RGB fingerprint. It checks retained PDF page objects and text bytes, then recomputes the three-save comparisons. For the 18 authored picture cases it reuses only the hash-pinned renderer's pure package-geometry and raster-measurement functions with in-memory ZIP input; it does not invoke a renderer or regenerate exports. All safety and consistency checks use explicit exceptions and remain active under optimized Python.

The corruption controls first verify the complete original bundle, then alter inner semantic records after the outer byte seals have been checked. They reject misattributed sources, changed commands, missing host or schema outputs, changed source hooks, altered LCOV, substituted staged packages, false native scope/counts, pixel/text contradictions and invented native completion. Original execution records remain unchanged.

## Related evidence and remaining limits

The [local exact-runtime acceptance](../word-final-c5ff75e7-20261113/README.md) separately covers the 107 data-only Word tests, 13 actual native assertions and portable JavaScript checks at runtime `86d5a218`. The [hosted provider proof](../provider-fb81b2ac-20261113/README.md) records 131 cases across four engines and 363 cross-decryptions, while retaining **ten known gaps and `promotion_ready=false`**. This Office success does not change that provider qualification.

The parser's [final native corpus proof at 822fdc53](https://github.com/CrispStrobe/legacy-doc-parser/blob/822fdc533b9412ab5fdfd2ea1427357cc8d0ca0b/doc/evidence/native-corpus-c5ff75e7/README.md) independently retains its 24-case/three-cycle measurements. That local corpus used LibreOfficeDev 26.8.0.0.alpha0; this hosted run used LibreOffice 24.2.7.2. The corpora and renderer environments are distinct. The parser's new tiled-fill preservation improves the initial Word14 aggregate pixel error while reducing repeat RGB parity against regenerated binary DOC from 39/72 to 36/72 across the full parser corpus. That measured difference remains open; the 122 hosted exports do not settle it. Original Word14 alternate DrawingML and effect limitations remain explicitly preserved. The [ink contract at the exact c5ff75e7 parser pin](https://github.com/CrispStrobe/legacy-doc-parser/blob/c5ff75e76163d9abbdd44a9f2a7c5ad210929289/doc/ink-decoding.md) describes supported nonempty payload inspection and its bounds; native Word ink placement and editing remain unsupported. The application continues to retain original payloads and explicit diagnostics for unsupported material.
