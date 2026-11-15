# CrispCloud continuation audit

Audited immutable checkpoint `cc92423bb98789239380864d5e8343c19c25e815` on
`integration/storage-carving-20261115`. The most recent application source
checkpoint is `20ee83ff965d5433aeb528ae84debdb304edcf4a`; later commits retain
qualification evidence. This is 32 commits beyond the pasted `c3a2dfee` handoff.

## Findings

The complete incoming inventory covers **17 branches and 14 PRs updated on
2026-11-15**, representing 20 unique heads. Fifteen are ancestors of the audited
checkpoint; one is the checkpoint itself. Two old branches have independently
reverified historical supersession proofs: 72 matching file blobs and their
ancestor revisions remain intact. The remaining shared application features
have later combined implementations and passing coverage. Two newer heads
(`main` at `68631862` and `fix/ods-date-styles` at `443db522`) differ from the
already imported ancestor `c8fd8d76` only in the manifest's `source_commit` field.
Their code is already present. Keep the reconciled canonical Office/parser pins
when importing their history. No recent PR uses an external fork head.

The independent receipt audit passed all **12 final gates**. It read original
bytes from immutable Git objects, verified exact artifact inventories and hashes,
matched 8,577 tracked source paths by bytes/blob IDs/modes, and checked the common
recorded 8,588-input source/resolution snapshot. Raw machine events show:

| Saved cohort | Suites | Passing tests |
| --- | ---: | ---: |
| App `app-retry-1` | 65 | 903 |
| Engine `engine-final` | 22 | 249 |
| Editor `editor-final` | 9 | 101 |
| Primary total | 96 | 1,253 |
| Separate navigation capture | 1 repeated suite | 12 |

The four strict analysis receipts cover 76 app, 16 engine, four editor and one
CLI file. No skipped, failed, missing or unexpected suites are present in the
accepted raw reports. Every start event has exactly one successful completion.

Fresh independent Python reads also passed for all 12 retained Office outputs,
all six navigation workbooks, 16 retained VM/compiled-JavaScript recovery ZIPs,
and their 20 decoded PNG images. Candidate identities, exact source bytes,
decoded pixels, CRCs, and the wrong-expected-hash rejection match the saved
reports. The Office and navigation output hashes match their generator receipts.

Both actual navigation PNGs were visually inspected. The English duplicate-name
modal is fully readable; its validation text and actions are complete. The
390-pixel Arabic capture shows readable joined Arabic text, real action icons,
and a visible worksheet selector and rename control. No blocking issue was found
within this capture scope. `navigation-visual-review.json` records exact hashes
and the nonblocking test debug marker.

## Evidence scope and remaining work

This audit is a revalidation of saved evidence, not a new Dart/Flutter runtime
execution. It verified 39 retained repository tool files, the retained original
environment launcher, and the identical available Node executable. Three old
SDK binaries and two CLI resolution files are no longer available at their
historical paths. Their saved before/after hashes are consistent; their current
bytes are not claimed as independently verified. Eleven nontracked input
fingerprints remain recorded without materializing fabricated package graphs.

The saved parser evidence reports 4,131 cases in 144 suites; canonical parser
verification is assigned separately and is not added to the host total here.
External Office rendering, broad Open XML schema acceptance, other platforms and
native macOS toolbar acceptance remain separate scopes.

The existing PR #111 description is stale: it still cites `dd77efcb` and older
pins and planned gates. Once the latest incoming source is reconciled and its
scope checked, update the handoff/PR evidence pointers. Do not substitute old
runtime receipts for changed production inputs. No GitHub Actions job was
awaited, polled, restarted or used as a gate during this audit.

## Reusable audit files

- `audit_saved_receipts.py` and `saved-receipt-audit.json`: immutable historical
  receipt/source/machine-event audit.
- `recheck_saved_outputs.py` and `retained-output-recheck.json`: fresh independent
  reads of retained output bytes. Recheck scripts write only under this notes
  directory.
- `audit_incoming.py`, `crispcloud-incoming-audit.json`,
  `crispcloud-recent-pr-metadata.json`, and `incoming-closure-recheck.json`:
  finite branch/PR inventory and independently reverified disposition proofs.
  The incoming script accepts `--head` so the root can repeat closure against the
  final saved integration commit.
- `navigation-visual-review.json`: explicit actual-image observation.

The `output-recheck-snapshot` directory is a disposable materialization of exact
Git source/helpers and retained outputs. Reports and audit scripts are the
review deliverables; original outputs remain preserved in the repository.
