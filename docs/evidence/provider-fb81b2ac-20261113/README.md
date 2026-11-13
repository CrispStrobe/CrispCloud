# Hosted provider result at official app head fb81b2ac

The existing provider workflow passed on official CrispCloud commit
[`fb81b2ace557964459189afd7c0c7d76b2c9557d`](https://github.com/CrispStrobe/CrispCloud/commit/fb81b2ace557964459189afd7c0c7d76b2c9557d),
tree `a14d066f1179ea00e20eaa3431aec0dd4fe05a5f`, on
`feature/office-fidelity-gaps-20261113`. This is a separate hosted observation
from the [local app acceptance](../word-final-c5ff75e7-20261113/README.md) measured
at runtime `86d5a218`. The parser pin remains `c5ff75e7`; this checkpoint adds
only evidence and does not change application or provider runtime code.

## Actual result and retained limits

[Run 43390627091](https://github.com/CrispStrobe/CrispCloud/actions/runs/43390627091),
attempt 1, completed successfully. Conformance job `131769379332` and all 15
steps succeeded. Its actual report records **131 cases across four engines**,
**34 mock cases**, **363 cross-decryptions**, no unexpected failures and
`passed: true`.

The same report explicitly retains **10 known gaps** and
**`promotion_ready: false`**. Nine are observed differences between engines;
the tenth records the shared acceptance of a missing listing collection.
These include malformed-input handling, legacy text encoding and empty text,
retry behavior and undecryptable metadata handling. A passing workflow does
not establish complete provider equivalence or readiness to promote a backend.
Every original result, gap reason and raw observation is retained unchanged.
No provider behavior was altered as part of this Office integration.

The executed command is retained in the source workflow and decoded job log:

```sh
python _provider_conformance/conformance/run.py --pointycastle 4.0.0 --dart-pg 2.1.0 --dart-filen packages/filen_client --published-internxt 0.2.3
```

The workflow uses the pinned `crisp-cloud-rs` source revision
`6c1f351dbe0cb9efe2ecf19b009603907bf5cf2e`. The source snapshot retains all
7,579 app Git blob identities, modes, sizes and byte hashes, and the exact
workflow/validation sources used to interpret this result.

## Complete output retention

Artifact `14020796791`, `provider-conformance`, was downloaded and verified
against GitHub's exact ZIP size and digest:

- ZIP bytes: **54,108,309**.
- ZIP SHA-256: `13800eb19f18cd237f43ac82efe889fcd641b0cd17e07108d7b01107f35bd495`.
- Original inventory: **27 files**, **125,772,046** uncompressed bytes.
- Retained outputs and dependency locks: **25 files**, **40,388,702** bytes.

Only the reproducible compiled ELF files `results/rust-probe` and
`results/dart-probe` are omitted. Their exact hashes, lengths, ZIP attributes
and omission reasons remain in the complete inventory. All four raw engine
results, every export and cross-decryption result, mock request log, final
report and both dependency locks are retained byte for byte.

The retained output archive is **18,711,960 bytes**, SHA-256
`886cce4c0f5422c13d2ea650505b1b7f27900b453d241c5ef4748d9d4a5167d7`.
It is stored in ordered pieces to keep each repository blob bounded.
`receipt.json` binds their exact order, size and hashes. The verifier reassembles
the original archive before checking every retained member against the
downloaded ZIP inventory. `records.tar.xz` separately retains full run/job/
artifact API records, the returned decoded job log, source and publication
receipts, independent app review and the collection helper. Temporary signed
download URLs and SDK/dependency caches are not included.

## Office workflow queue observation

The separately queued [Office run 43390627156](https://github.com/CrispStrobe/CrispCloud/actions/runs/43390627156)
has the same exact official app head. At the retained **08:20:09 UTC** snapshot,
its first job `131769379446` was still queued after creation at 08:06:31 UTC.
GitHub reported `ubuntu-latest`, `runner_id: 0`, an empty runner name and
**zero executed steps**. This receipt makes no hosted Office success claim.

The first job has no `needs` dependency; only the later external-schema job
depends on it. There were no active or pending runs on this official branch,
and this was its only queued run. A separate archive-operation workflow was
active on another branch with a distinct concurrency group. That observation
alone does not establish a runner-capacity blocker. No same-group blocker or
superseding run was found, and no job was restarted or cancelled. Exact API
snapshots, workflow sources and the read-only diagnosis are retained. Later
Office observations belong to their own timestamps and receipts.

## Separate parser native evidence

The [complete native parser corpus at evidence commit 822fdc53](https://github.com/CrispStrobe/legacy-doc-parser/blob/822fdc533b9412ab5fdfd2ea1427357cc8d0ca0b/doc/evidence/native-corpus-c5ff75e7/README.md)
measures the same `c5ff75e7` parser runtime. That later proof is external to the
exact vendor projection. Its README and Git identity are retained here as an
attributed handoff; the underlying native artifacts remain in the parser repo.

All 24 initial cases and 72 repeat imports completed; nine initial cases were
exact. The real repeat parity reduction from **39/72 to 36/72** against
regenerated binary DOC is preserved. It is confined to Word14's newly retained
pattern/texture fills. Aggregate initial Word14 changed pixels improved from
35,146 to 30,704, and absolute RGB channel error from 10,774,592 to 6,725,615;
that aggregate does not mean every object improved. Source geometry, image
selection and payloads were preserved, and no lost explicit tile operand was
found. The evidence does not justify guessed offsets, recoloring or dropping
fills to restore the old exactness count. Alternate DrawingML remains retained
but unsupported, and native Word ink placement/editing remains unsupported.

## Verification

```sh
python3 docs/evidence/provider-fb81b2ac-20261113/verify.py --repository .
python3 docs/evidence/provider-fb81b2ac-20261113/test_verifier.py
python3 -O docs/evidence/provider-fb81b2ac-20261113/test_verifier.py
```

The verifier uses explicit checks that stay active under optimized Python.
It validates exact source/run/job/artifact identities and every retained member,
then independently reconciles the four raw case inventories, known differences,
all export/cross-decryption results and the final totals. It also checks the
queue snapshot against its exact job record and source workflow. It does not
execute cryptography or turn a retained queue observation into a later status.
Thirteen semantic controls bypass the outer checksums and require contradictory
source, result, promotion, gap, artifact, retention and queue claims to fail.
