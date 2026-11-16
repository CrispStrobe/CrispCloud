# Zotero recovery and integrated host qualification — 16 November 2026


This continuation preserves the already merged Zotero implementation, reconciles the observed incoming font/PDF and worksheet work, and publishes source-bound local evidence for the exact implementation pair below. The former session's implementation and qualification summary survived, but its final detailed raw archives were not published before its workspace exhausted disk. These are fresh records; earlier receipts retain their original source identities.

**Completed retry result:** **1,173 fresh, disjoint tests passed: 1,104 canonical + 41 actual-host + 28 Python regressions.** The canonical run reported zero skipped tests. Both completed retries passed every required command, strict analysis/format checks, before/after integrity checks and analyzer-configuration restoration. The totals exclude every historical, failed and interrupted attempt.

The managed Office bytes are verified against their declared sources. One stricter diagnostic remains **false**: eight inherited executable bits differ from canonical Git modes. That diagnostic and its supplemental disposition are preserved below; this report does not claim that every delivery check passed.

## Immutable implementation identities

| Item | Exact identity |
| --- | --- |
| CrispCloud implementation | [`07083d1983db87a9868c3e8ba0cda1efd283b445`](https://github.com/CrispStrobe/CrispCloud/commit/07083d1983db87a9868c3e8ba0cda1efd283b445) |
| CrispCloud implementation tree | `55349829d109305288ee241d29bd358d3d966038` |
| Canonical Quds implementation | [`b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`](https://github.com/CrispStrobe/quds_office_suite/commit/b87f9d6c3a2532c9695024adf48ca9fbd3c0927a) |
| Canonical Quds tree | `acb1d1060879dc4a8168df8abf3105dc828af360` |
| Host recovery parent | `05834b276c69ee45bdf72e9d7819ac58f448d786` |
| Bounded later host main parent | `553f3be64da9ad3c35730f1b6a67d79f1ac54b72` |
| Standalone parser pin | `4895712158127b2fc930d796e17035c3ca0dac62` |
| Managed Office inventory | **2,509 files: 652 non-parser + 1,857 parser** |

The final host merge retains both parents. It was built from the intact later-main checkout, with the five saved host sync/asset/notice files restored, then reconciled with the final canonical source through the guarded updater. The manifest and managed files were verified together before qualification. See [source adoption](audit/host-qualification-source-adoption.json), [final vendor application](audit/crisp-final-vendor-applied.json), and [source delivery verification](audit/delivery-verification.json).

Evidence-only commits after these implementation commits do not change which source trees the receipts qualify.

## Incoming work accounted for

The original host remote snapshot completed at **2026-11-16T19:38:45.364268+00:00**. It contains **258 advertised refs: 73 branch heads and 185 PR heads**, evaluated against frozen main `bf0255a168576b0d9993d8b668f2a7d0d943fd4f`. The raw snapshot SHA-256 is `8b7fd56269c358a839c7b4c86b8b11e7fa32b12ebffcb06d72a4f709b47475e0`.

| Disposition | Ref count | Proof |
| --- | ---: | --- |
| Actual ancestor of frozen main | 210 | Local Git ancestry |
| Exact whole-tree equivalent to a merged ancestor | 48 | 24 branch/PR alias pairs with identical head and merged tree IDs |
| Unresolved at the recorded cutoff | 0 | Every observed ref has a disposition |
| **Total** | **258** | **73 branches + 185 PR heads** |

The 48 equivalence entries correspond to PRs #171–#195, excluding #176. Their complete Git tree identities equal the respective merged commits; each merged counterpart is an actual ancestor of frozen main. This proof does not rely on patch similarity. The earlier Zotero PR #176 was already merged and is an actual ancestor. The new outgoing recovery branch and review PR are excluded from the original incoming count.

One bounded later main observation at **2026-11-16 20:04:10 UTC** found `553f3be64da9ad3c35730f1b6a67d79f1ac54b72`, five commits ahead. The final host merge retains its worksheet page setup and ODS header/footer work through PR #200, including the four sheet production files and two regression files. This later observation supplements the original inventory; it does not redefine its cutoff or assert that all other remote refs stopped changing.

The retained font/PDF work and this sheet work occupy separate source areas. The later host manifest had 2,503 entries; the recovery manifest adds `pdf_document.dart`, four new font/PDF regression/support files, and the original FontTools notice, for 2,509. The standalone parser source identity and inventory stay unchanged.

Review the complete [incoming-work narrative](audit/crisp-incoming-work.md), [per-ref dispositions](audit/crisp-incoming-audit.json), [exact squash tree proofs](audit/crisp-remote-squash-equivalence.json), [bounded later-main observation](audit/crisp-bounded-final-main.json), and [manifest comparison](audit/crisp-late-manifest-comparison.json). The raw [ref snapshot](audit/crisp-remote-refs.txt) and [PR metadata](audit/crisp-pr-metadata.json) are retained beside the replay script.

## Host change accompanying the font work

The incoming font subsetter contains Unicode-range data transcribed from FontTools 4.61.1. This host change carries its original notice through the guarded sync, bundles it as a production Flutter asset, and exposes it through the existing Office license registry. It adds no FontTools runtime dependency.

The narrow host change touches the sync helper and its existing boundary regression, the production asset declaration, the Office license registry, and its existing bundle regression. The sync regression checks notice inclusion, exact bytes, idempotence, similarly named/wrong-package exclusions, and refusal to overwrite edited FontTools or Wortliste notices. The bundle regression reads the actual four assets and checks the resulting Flutter license entries, including the FontTools version and copyright.

The four bundled Office notices are:

- `packages/quds_office_engine/third_party/hyphenation/LICENSE`
- `packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE`
- `packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE`
- `packages/quds_office_engine/third_party/fonttools/LICENSE`

Existing test cases were extended; the case totals were not increased by splitting assertions into extra tests.

## Fresh qualification

Only the completed isolated retries contribute to the totals below. Historical qualification, development checks, and all partial attempts are excluded.

| Cohort or gate | Fresh result | Evidence |
| --- | --- | --- |
| Canonical Quds selected tests | **1,104 passed; zero skips; 70 distinct test files** | [canonical receipt](canonical/receipt.json) |
| Actual CrispCloud host tests | **41 passed** — 39 Zotero + 2 notice cases | [host receipt](host/receipt.json), [raw host test log](host/host-tests.log.gz) |
| Python Office/parser sync and verification regressions | **28 passed** — 28 cases | [raw Python log](host/python-sync-verifier-tests.log.gz) |
| Canonical strict analysis and format | **Passed** — 37 selected targets | [canonical receipt](canonical/receipt.json), [exact invocation](retry-invocation.json) |
| Host strict analysis and format | **Passed** — 24 selected targets | [host analysis](host/host-analysis.log.gz), [vendored analysis](host/vendor-analysis.log.gz), [host format](host/host-format.log.gz), [vendored format](host/vendor-format.log.gz) |
| Host source and tracked vendor guards | **Passed** — all 2,509 managed paths | [source guard](host/vendor-source.log.gz), [tracked guard](host/vendor-tracked.log.gz), [final tracked guard](host/vendor-tracked-final.log.gz) |
| Before/after source, dependency and analyzer-configuration integrity | **Both passed.** Host: 3,732 source inputs and 5,837 dependency files unchanged. Canonical: 1,568 source inputs, 3,857 external dependency/runtime inputs and four font fixtures unchanged. Harnesses unchanged; analyzer configurations restored. | Both completed receipts and their inventories |
| Strict canonical Git blob **and mode** comparison | **False: eight inherited executable modes** | [original diagnostic](audit/delivery-verification.json), [supplemental disposition](audit/host-inherited-differences.md) |

The accepted canonical count is the sum of these non-overlapping cohorts, each with a successful terminal log marker:

| Canonical cohort | Passed |
| --- | ---: |
| `engine-zotero` | 390 |
| `editor-zotero` | 186 |
| `engine-proofing-integration` | 74 |
| `engine-ods-integration` | 102 |
| `engine-word-layout-integration` | 31 |
| `editor-proofing-integration` | 107 |
| `editor-hyphenation-integration` | 30 |
| `engine-recovery-integration` | 180 |
| `editor-recovery-integration` | 4 |
| **Canonical total** | **1,104** |

The host's 24 strict targets comprise eight host targets and sixteen vendored targets: the seven preserved Zotero/text targets, five font/PDF production targets, and four later-main sheet production targets. Canonical test selection covers the retained Zotero, proofing, text-layout, spreadsheet and font/PDF work; its exact selected files and command arguments are recorded in the canonical receipt and invocation, with duplicate file selections removed by the runner.

The runtime provenance records genuine Flutter 3.47.8 / Dart 3.13.7 binaries and preserved locked dependency graphs. The retry harness points to fresh isolated source checkouts. It carries the four actual notice assets, and it does not reuse compiled test/build caches from the interrupted attempt. Setup, absolute local-path rebasing, lock preservation and binary hashes are recorded in [setup provenance](setup/README.md). This is a focused harness graph; it is not a full production dependency resolution.

The completed canonical retry fingerprints **1,568 source inputs** and separately binds all **four system-font fixtures** used by the font/PDF tests; those inputs, 3,857 external dependency/runtime inputs and the harness hashes are identical before and after execution. It includes the three required `packages/quds_office_engine/example/pdf_widgets_{invoice,proposal,report}.dart` imports from the unchanged canonical commit. Its runner SHA-256 is `198271764369f36955d7fe8455e1b74db8a9f32bc0147f14019387c5c3dbf2d9`. This complete rerun reused caches created by the preceding isolated retry that reached a clean terminal failure; it used no cache from the original attempt whose process state could not be established. The host retry separately used its fresh isolated harness without copying compiled test/build caches.

Both retry runners journal their receipt before and after commands, emit progress heartbeats every 15 seconds, and fail a command after 600 seconds. The host runner additionally checks the exact expected test counts and completion of all ten commands, and restores its temporary analyzer configuration. The published [host runner](host/run-expanded-host.py) has SHA-256 `18d3d737e1431d5edc37c3dfe187a5e744479a0f4b89fe9836c44db24b3f050d`; its test/target declarations and command invocations are unchanged from the first attempt.

The fresh synthetic Unicode-alias PDFs also passed [independent Poppler verification](canonical/poppler/receipt.json), with their [producer/source binding](canonical/poppler-binding.json) retained. Encoded and identity-reference fixtures rasterized to identical 320 by 112 RGB images at 72 dpi, and direct and Word-exported PDFs extracted the exact authored code points. These checks add no test cases to the 1,173 total and make no general emoji, CJK, shaping-parity or platform-conformance claim.

## Inherited differences and the strict diagnostic

All **652 managed non-parser blob IDs match canonical Quds**. All **2,509 manifest SHA-256 values match host bytes**. The **1,857 managed parser entries** preserve baseline inventory, bytes and modes; the wider tracked parser comparison also includes its unchanged metadata.

The auxiliary Git comparison deliberately includes executable modes. Eight managed paths are `100755` in the host and `100644` in canonical Quds, so `managed_non_parser_git_blobs_and_modes_identical` remains false. All eight host modes are unchanged from frozen host main. The official sync planner omits a source-mode map and preserves existing target permissions; its pre-existing permission regression records that behavior. No mode was normalized and no gate was weakened. Three of the eight font/PDF files have updated canonical contents while preserving their old host modes.

The complete lib/test comparison also records fourteen unmanaged content differences and six host-only report localization helpers. Every one retains exactly its baseline host blob and mode. They comprise report interface localization, the host `url_launcher` adapter, existing Office package integrity hardening and regression tests, export ordering, and equivalent Dart/nullability forms. Their full classifications and object identities are in [host-inherited-differences.md](audit/host-inherited-differences.md), [the machine-readable disposition](audit/host-inherited-differences.json), and [the baseline proof](audit/unmanaged-baseline-proof.json).

No concrete new incompatibility with the incoming PDF or Zotero code was identified in that bounded source review. In particular, the new optional PDF encoding preserves identity encoding for unchanged widget/report callers, while the Office exporter explicitly opts into the new character mapping. The host-only watermark null checks follow an identical early guard and do not change the reachable rendering path. This inspection adds no tests to the fresh totals.

The complete [original diagnostic records](audit/delivery-verification.details.json.gz) remain available, including the additional 197 unmanaged mode-only observations. The original failure is retained without recasting the whole package comparison as an exact copy.

## Interrupted attempts

The first host attempt completed its 41 selected host tests and vendor guards, then lost its observable execution handle while the analyzer log contained only its startup header. It had no final qualification receipt or completed after-state maps. The available process state could not prove that its analyzer had terminated, so the old temporary configuration was left untouched and the host qualification was repeated in a fresh isolated worktree and harness.

The original raw logs, interruption observations and fingerprint maps are preserved under [attempts](attempts/). The 41 partial host cases are excluded from final totals. The canonical interrupted attempt is likewise preserved and excluded.

The first isolated canonical retry then reached a clean terminal failure because its harness lacked three example imports required by `pdf_widgets_test.dart`: `pdf_widgets_invoice.dart`, `pdf_widgets_proposal.dart`, and `pdf_widgets_report.dart`. Seven earlier cohorts had completed **920 cases**, and the failing recovery-cohort log ended at **162 partial passes and one failure**. All **920 + 162** are excluded from the final total. That failed retry restored its analyzer configuration and retained unchanged source, dependency and harness fingerprints. The missing example files were materialized from the same frozen source, included in the expanded 1,568-file source fingerprint, and the entire canonical suite was rerun with the corrected harness and explicit system-font binding. Its complete terminal receipt supplies the accepted 1,104 canonical cases; no earlier cohort count was carried forward.

## Reproduction and evidence integrity

The canonical and host directories contain completed receipts, raw command logs, before/after source and dependency maps, analyzer graphs and SHA-256 inventories. The canonical package also contains its before/after system-font fixture maps. Consult [canonical inventory](canonical/artifact-inventory.json) and [host inventory](host/artifact-inventory.json) for filenames and compression; compressed records are lossless representations of the original bytes. The same canonical and host evidence is published in both repositories.

Start with [setup/README.md](setup/README.md) to reconstruct the pinned runtime and the locked isolated harnesses. Use fresh output directories and the exact implementation commits above. Retain all test, analysis and format selections when relocating paths.

For canonical qualification, [retry-invocation.json](retry-invocation.json) records the exact argument array and environment; [run-retry-canonical.sh](run-retry-canonical.sh) records the actual shell invocation, and [canonical/run-qualification.py](canonical/run-qualification.py) is the runner. Its workspace paths can be rebased to a new checkout/harness, but source identities and selected targets must stay fixed.

For the actual host, run [host/run-expanded-host.py](host/run-expanded-host.py) with these immutable source identities after applying the setup instructions. The path variables below refer to the reproduced evidence directory, frozen checkouts, locked host harness and a new output directory:

```sh
python "$RECOVERY_EVIDENCE/host/run-expanded-host.py" \
  --repo "$CRISP_SOURCE" \
  --harness "$HOST_HARNESS" \
  --quds-source "$QUDS_SOURCE" \
  --source-commit 07083d1983db87a9868c3e8ba0cda1efd283b445 \
  --quds-commit b87f9d6c3a2532c9695024adf48ca9fbd3c0927a \
  --output "$HOST_OUTPUT"
```

The host receipt records the executed absolute paths, command arrays, binary hashes and runner hash, so the invocation can also be reproduced directly from that record.

Replay the recorded incoming inventory without refreshing moving refs or querying CI:

```sh
GIT_NO_LAZY_FETCH=1 python "$RECOVERY_EVIDENCE/audit/audit_crisp_refs.py" \
  --repo "$CRISP_SOURCE" \
  --evidence-dir "$RECOVERY_EVIDENCE/audit"
```

The replay uses local commit ancestry plus the saved exact-tree proofs for squash heads unavailable in a partial clone. It requires the recorded baseline history to be present and leaves the original observation cutoff intact.

## Scope limits

No GitHub Actions jobs, workflow runs, artifacts, status checks, CI waits or reruns were used. Incremental remote checkpoints use `[skip ci]`.

The focused local qualification does not establish a fresh full application build, full production dependency resolution, live Zotero account or desktop-picker interoperability, Word/LibreOffice acceptance, platform URL-launch behavior, or operating-system keychain acceptance. Network, credentials and protocol interactions in the selected tests use test doubles. Source and evidence identities, test scope, retained diagnostic failures and incomplete attempts are reported separately so those limits remain visible.
