# Completed qualification of source `20ee83ff`

**PASS for the recorded source scope; superseded for current-branch acceptance.**

A later concurrent source commit, `41885d7d1d67348f5abe3579b99d9d2951fc909f`,
adds ODS bounds and Linux golden coverage. The results below qualify source
`20ee83ff` and its source-identical descendants through `137c95de`; they do not
qualify the later changed source. Its fresh qualification is tracked separately
in [remote-refresh-20261115](../remote-refresh-20261115/README.md).

**Recorded result:** The final combined production source is
`20ee83ff965d5433aeb528ae84debdb304edcf4a`. The twelve accepted host gates are saved
through `cc92423bb98789239380864d5e8343c19c25e815`; later continuation commits
preserve that production source. All listed local gates for source `20ee83ff`
are complete. PR [#111](https://github.com/CrispStrobe/CrispCloud/pull/111) remains
a draft for implementation review.

The earlier disk-capacity blocker was resolved. Fresh Flutter/Dart qualification
ran locally, with real native build hooks enabled. Every completed gate was
saved remotely before the next gate. Checkpoint commits use `[skip ci]`.
No GitHub Actions run was awaited, polled, or restarted.

## Source and incoming work

The finite observed incoming batch is fully accounted for: **53 relevant heads,
49 ancestors, four explicitly proved supersessions, zero gaps**. This includes
main through `4933ffc2`, app PR 120 through `c8fd8d76`, the incoming ODS dates and
comments work through `9cc8c6e9`, parser main `7df906d2`, and the earlier document
workspace, worksheet navigation, picture, wrap-text, storage, and parallel
qualification histories. The original user handoff `71c14b98` remains an
ancestor. The final supplement rechecks the same observed batch against the
final production pins; it does not claim a later upstream refresh.

While the final reports were being saved, a concurrent commit advanced the
integration branch to `137c95de`, merging new main `68631862` (PR 120). The remote
save guard detected that advance before writing. Both the reviewed checkpoint
and the concurrent merge have the **same complete tree**
`af9411791cbfb2081b7633e493dd8d61fea389cc`, so the qualified source is unchanged.
The merge is preserved in the ancestry of the final evidence save. The
[concurrent-main supplement](incoming/concurrent-main-closure.md) records this
additional immutable comparison separately from the original 53-head inventory.

| Repository | Final production pin |
| --- | --- |
| CrispCloud | `20ee83ff965d5433aeb528ae84debdb304edcf4a` |
| Canonical Office | `c17098d65fe5f6e2bdf9999389deb2a6b508d928` |
| Standalone parser | `9bdcc7eba3f1ce80b7d834d7740895774eeca615` |

All **2,303 managed files** match their canonical Git blob identities, object
types, file modes, and manifest SHA-256 hashes: 496 Office files and 1,807 parser
files. The app manifest and parser `UPSTREAM.json` agree on the source pins.
See [the final closure supplement](incoming/final-closure-supplement.md) and its
[complete proof](incoming/final-closure-supplement.json).

## Defects reproduced and corrected

- **ODS geometry:** copy-save reduced the native default column width from 81px
  to 64px. The canonical correction preserves default/base geometry, native
  `sheetFormatPr` attributes, and explicit or zero defaults through direct and
  isolate save cycles.
- **ODS dates and comments:** the integrated reader preserves authored date
  component order, literals, long month and weekday names, and quoted or escaped
  format-section delimiters. Namespace-aware comments remain separate from cell
  values, with shared text and grid bounds and explicit refusal of ambiguous
  annotation structures. Author serialization preserves first-seen IDs using
  indexed lookup.
- **Legacy Word recovery:** bounded input and cumulative work, authoritative
  stream bounds, declared encodings, and half-open story cleanup retain the
  reconciled parser corrections. The host presents text-only recovery and its
  losses explicitly, leaves unknown source inventory unknown, and preserves
  create-only copy-save and collision behavior.
- **Underline integration:** the first full host run exposed 18 suite-loading
  errors because the ribbon did not cover the expanded 18-value underline enum.
  Review also found that the Font dialog could receive an imported style absent
  from its five choices. Both controls now share all 18 choices and localized
  labels. The regression selects every style, applies Font unchanged, then
  saves and reopens DOCX. Imported and mixed-font fidelity is covered too.
- **Damaged compound directories:** two host failures reproduced a typed
  `CfbfException` that bypassed the existing fallback. The parser now routes that
  specific exception through the existing opt-in, bounded DOCX text-recovery
  path. Nine new regressions cover admission and strict/default, DOCM,
  encryption, FIB, size, source, and private-tail refusal boundaries.
- **Strict-analysis defects:** nullable flow promotion, rethrow, and constant
  declarations were repaired. The deprecated cryptography wrapper was replaced
  by its exact underlying freeze operation under the existing locked dependency;
  no dependency or cryptography policy change was introduced.

The raw failed runs and their classifications remain saved. In particular, the
742-case host run at `f7295806` is failed predecessor evidence, with all 20
failures classified. Earlier successful cohorts retain their original source
scope and are not added to the final totals below.

## Final accepted qualification

| Area | Final result | Receipt |
| --- | --- | --- |
| Strict host analysis | 97 files: 76 app, 16 engine, 4 editor, 1 CLI; no issues, fatal infos/warnings | `analysis-*-final/` |
| App | 903 tests in 65 suites; no failures, errors, or skips | [app-retry-1](app-retry-1/summary.json) |
| Office engine | 249 tests in 22 suites; no failures, errors, or skips | [engine-final](engine-final/summary.json) |
| Office editor | 101 tests in 9 suites; no failures, errors, or skips | [editor-final](editor-final/summary.json) |
| Standalone parser | 4,131 tests in all 144 suites, plus clean strict analysis of 18 files | [canonical parser qualification](canonical-parser-current-qualification.json) |
| Independent Office output checks | 12 actual DOCX/XLSX/PPTX outputs and 17 oracle controls pass | [scripted oracle](scripted-oracle-final-artifacts/summary.json) |
| Source integrity | 11,366 tracked files at the integrity checkpoint, all 2,303 managed files, and 85 Python controls pass | [source integrity](source-integrity-final-details/summary.json) |
| PNG recovery portability | Dart VM and actual compiled JavaScript each pass 8 cases and 248 assertions; independent readers verify 8 ZIPs and 10 PNGs per runtime | [portable results](png-portable-final-artifacts/summary.json) |
| Navigation capture | 12 tests pass in the separate capture run | [capture](navigation-capture-final/summary.json) |
| Navigation independent checks | Six workbooks and two complete-host, font-backed PNGs pass source, font, dimensions, and semantic checks; both PNGs visually reviewed | [verification](navigation-independent-review-final-artifacts/verification.json), [visual review](visual-review.md) |

The primary host/Office total is **1,253 tests across 96 suites**
(903 + 249 + 101). The additional 12-test preview execution repeats navigation
coverage and is not added to that total. The parser is a separately resolved
canonical scope; its focused nine new regressions and earlier focused recovery
checks are already included in the 4,131 full-suite total.

Parser raw final evidence is saved at
[`57442c79`](https://github.com/CrispStrobe/legacy-doc-parser/tree/57442c79239fb4d483e274e0ebb04f34686beb6c/doc/evidence/storage-carving-reconcile-20261115).
The source pin remains `9bdcc7eb`; the later parser changes add evidence only.

## Why the receipts apply to this source

The [independent review](final-independent-review/) rereads raw commands,
machine events, source snapshots, hashes, tool identities, and output inventories.
All twelve accepted host gates share source/resolution digest
`8987e08d73b266e89dbf0e4f4615333155ee6754b9a38fd90380444d02d64c8b`.
Their 8,588 recorded source and resolution inputs match the final reviewed
checkout, including content, Git blobs, and file modes. Source, HEAD, and tool
identities remained stable during each recorded gate.

The review checks unique complete machine-test events rather than adding retries
or hidden loading/setup events. Engine and navigation generation receipts bind
the exact artifacts consumed by independent readers. Four additional artifact
inventories match exactly. The PNG check runs actual compiled JavaScript and
also verifies rejection of deliberately wrong expected output hashes.

App and CLI locked offline resolution passed with their committed lockfiles
unchanged. The host uses its locked archive 4.6.0 graph; the engine/parser
development graph uses archive 4.7.1. Five real ELF native assets were built by
the initial app execution. That build receipt is retained as build evidence;
the failed initial runtime result is not accepted as a passing test gate.

## Scope and continuation

Acceptance covers the recorded Linux toolchain and selected host suites, the
complete standalone parser suite, independent semantic checks, and the stated
preview review. Before/after identity checks are not a hermetic cache snapshot or
proof against transient writes. These results do not assert native Office
application rendering, broad Open XML schema certification, or execution on
other operating systems. Two optional HOME-scanning corpus harnesses are
retained without execution or vacuous counts.

PNG recovery remains bounded to its supported complete PNG subset and reviewed
new ZIP publication. It does not reconstruct fragmented files, infer original
names, carve other formats, read physical devices, or enable browser/cloud
publication. Native verify-then-rename is not an atomic compare-and-swap against
arbitrary external writers.

All listed gates for source `20ee83ff` are complete. The later `41885d7d` source
requires its own scoped receipts before current-branch acceptance. Future
source or resolution changes require fresh appropriately scoped receipts under
new labels; do not reuse these totals for changed source. The branch remains
available for review through PR #111. This continuation does not merge main or
make a release/deployment claim.

The machine-readable acceptance index is [final-acceptance.json](final-acceptance.json).
