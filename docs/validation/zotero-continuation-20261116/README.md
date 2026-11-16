# CrispCloud Zotero continuation — 16 November 2026

CrispCloud now uses the continued Quds source for first-use native catalog
insertion, protected mixed citation formatting and automatic note numbering.
The canonical implementation qualified at
**`72691877bd9bafab761e655c13d0c9a0936b55bb`**; documentation-only source-pin
updates retain those measured production and test bytes.

## Executed host qualification

The [actual host receipt](final/host-validation-receipt.json) records **37
passing tests**, clean strict analysis of eight host targets, clean formatting,
and both normal and tracked vendor checks. It measured **1,595 unchanged source
files** and an unchanged manifest with **2,399 entries**: **542 Quds files and
1,857 standalone parser files**. The standalone parser proof checks actual
bytes, hashes, executable modes and its unchanged
`4895712158127b2fc930d796e17035c3ca0dac62` source pin.

The host tree is `e56518372313b5d9c9698a26d25488bf331c1915`, saved at
`e5dc3dc5b0919fd79f913e1ad7aee427bafef09e`. Its content is identical to the local
`a81f686f0e96958da42b055f4264b6f87b9c7b95` commit recorded during execution.
The connected GitHub checkpoint changes commit identity, not the tested tree.
Subsequent evidence/docs and source-pin updates are checked for implementation
identity.

The runtime is official **Flutter 3.47.8 / Dart 3.13.7**. The **96-package**
host graph is genuinely resolved with its lockfile enforced. Actual production
services, transports, editor packages and ribbon are compiled directly; no
implementation stubs or relaxed production dependency constraints are used.

## Combined local results

| Selected unit/widget cohort | Passed |
| --- | ---: |
| Canonical engine/client/Word field, revision and note selection | 579 |
| Canonical shared editor/controller/dialog/note/paste selection | 195 |
| Actual Studio native transport | 16 |
| Actual CrispCloud host selection | 37 |
| Incoming ODS metadata/conditional-affix integration | 85 |
| Incoming terminal/session/forwarding/output-trigger selection | 226 |
| **Total** | **1,138** |

The [terminal evidence](terminal-integration/README.md) separately records three
passing shell smoke scenarios and **six executed passes** against disposable
loopback SSH servers, with one separate optional PTY case skipped. An initial
SOCKS timeout during concurrent heavy qualification, the unchanged diagnostic
retry, and the final full pass are all retained. No source, test or timeout
changed. Live/shell acceptance and overlapping intermediate runs are not added
to the unit/widget total.

Canonical qualification covers all **32 changed Dart targets** with strict
analysis and formatting. The Quds receipt records **1,568 unchanged
source/dependency-input hashes**, stable HEAD and unchanged harness inputs.
See the [canonical evidence and reproduction](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261116/docs/validation/zotero-continuation-20261116).

## Real native Zotero acceptance

The actual Quds catalog/Studio transport and citing driver/Word adapter passed
live local catalog and document-processing checks against official Zotero
10.0.8 with three synthetic sources. Native Document Preferences selected the
pinned Chicago subsequent-ibid style and German locale. DOCX save/reopen retains
a full first citation, `Ebd.`, `Ebd., 34.`, mixed italics and the regenerated
bibliography. The expected bibliography paragraph-layout review was accepted
by the synthetic fixture.

These scenarios are reported separately from the local unit/widget counts.
They verify the shared native integration path, not a full compiled CrispCloud
application, private accounts or OS-keychain behavior. Microsoft Word/LibreOffice
interoperability remains unverified. Exact scripts, output DOCX files, protocol
logs and source/runtime scope are in the
[live acceptance evidence](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261116/docs/validation/zotero-continuation-20261116/live-zotero).

Small caps and bibliography paragraph layout still require reviewed
simplification. Page-based note restarts and unsupported numbering formats
show source-ID fallback. Active ODT transfer is absent; unsupported stories,
protected/ambiguous fields and unsafe note conversions refuse processing.

## Reproduce locally

Reconstruct the genuine host harness from the recorded dependency inputs and
canonical `setup/` scripts. Set `FLUTTER_ROOT` and `PUB_CACHE` to the pinned
runtime/environment, then use the current exact Quds pin from
`tool/office_fidelity_manifest.json`:

```sh
python3 docs/validation/zotero-continuation-20261116/run-continuation-host.py \
  --harness /path/to/zotero-toolchain/crisp-host-harness \
  --quds-source /path/to/quds_office_suite \
  --expected-quds QUDS_COMMIT \
  --output /path/to/new-host-evidence
```

The wrapper derives a temporary canonical analyzer graph from the real harness
and restores the previous configuration. The underlying runner enforces the
lockfile offline, compiles unchanged sources, verifies both vendor modes, and
checks source/manifests before and after. No CI is invoked. Terminal reproduction
is documented with its separate genuine harness and exact source inventory.

## Incoming-work reconciliation

The [final source audit](final-integration.json) uses **2026-11-16 05:17:13 UTC**
as its explicit cutoff: **62 branch heads and 199 PR heads**, with the two
continuation branches identified separately. All **259 external refs** are
actual ancestors after merging terminal PR #160 at
`49d63f78d0b854ba76289dba69fdb6584f8a1260`. The durable merge commit is
`d916a841c54ddcca8f6327e45939c4372ba1d3a9`; both parents are retained. No claim
is made about later concurrent commits.

### Initial audit before feature edits

Initial source cutoff: **2026-11-16 05:00:31 UTC**. All incoming work was accounted for before this continuation's feature edits.

- Repository: `CrispStrobe/CrispCloud`.
- Starting commit: `45ed126a6d7da0ecd80f3a765155f54008b278f3`.
- Prior Zotero checkpoint: `e678e17859f8d29e274d1abbf064b93d04a6fa42`; the new baseline is 42 commits ahead and contains that checkpoint as an ancestor.
- Continuation branch: `codex/zotero-support-20261116`.
- Audited **37 current branch heads** and **149 PR heads** (all states and pages); **182** actual ancestor references, **4** exact-tree-equivalent references, **0** unaccounted references.

The [machine-readable audit](incoming-integration.json) records each observed ref and SHA, its complete Git tree, and any integrated exact-tree equivalent. An equivalent means the entire tracked tree matches a real ancestor, including file contents and modes. It does not rewrite history or reapply older code over newer changes.

The companion repository was audited at the same cutoff: together the snapshots account for **60 branch heads and 198 PR heads**. Both earlier Zotero PRs (Quds #47 and CrispCloud #149) and terminal PR #140 have been merged. Both continuation branches start from current main.

No GitHub Actions or check/status endpoints were queried, polled, awaited or rerun. The audit itself records reconciliation; the executed qualification and live evidence are described above.

## Exact-tree equivalents

| Original source head | Integrated squash commit | Review |
| --- | --- | --- |
| `8a62e0864ad4bae96063ec6f8a542db039a306cf` | `924a2b5de6052514e13fa6d7b6210f38a58842fe` | #158, ODS metadata vendor |
| `343a930ebdbc1b0ee45f16328be868d0f78ba624` | `42f677ab74c3060607ff7964eae13a333d0ee44c` | #159, metadata documentation |

Each source appears once as a branch head and once as a PR head. Both whole-tree equivalences were verified locally; their changes are already present in the baseline.
