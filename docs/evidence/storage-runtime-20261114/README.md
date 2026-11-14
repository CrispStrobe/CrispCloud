# Storage runtime qualification — 2026-11-14

The qualified runtime is
[`fb57e8abb22e1a2fe588c1a22d9ac0326e7358ee`](https://github.com/CrispStrobe/CrispCloud/commit/fb57e8abb22e1a2fe588c1a22d9ac0326e7358ee).
Subsequent integration checkpoints retain documentation and evidence. The full
production JavaScript release build embeds that source revision and version
**1.2.9+22**. No deployment or new device/native release build is claimed.

This increment implements [LZFSE DMG reading](../../archive-dmg-codecs.md) and
[read-only GPT/MBR inspection in Hex](../../disk-partition-inspection.md).
The [roadmap and library assessment](../../storage-capabilities-20261114.md)
retains the wider proposed work and its separate source/license evidence.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Native archive regression gate | 418 passed; 0 failed, 0 skipped across nine files | [Native qualification](native-validation.md), [test events](native-archive-gate.jsonl) |
| Final DMG follow-up | 82 passed; 0 failed, 0 skipped, including mixed compression and cancellation before a later chunk | [Follow-up receipt](native-dmg-followup-gate-receipt.json) |
| Final partition service/review/viewer gate | 58 passed; 0 failed, 0 skipped: 24 service, 20 independent-review, eight new viewer and six existing structure-viewer tests | [Summary](partition-native-gate-summary.json), [source/profile receipt](partition-native-gate-receipt.json) |
| LZFSE on production Dart VM and actual compiled JavaScript | Each passed 12 reference groups, 489,825 exact output bytes, 76 malformed/profile cases and 2,660 truncation prefixes; bounds and offset views passed | [LZFSE qualification](lzfse-validation.md) |
| Partition service on production Dart VM and actual compiled JavaScript | Each passed 14 groups and 516 checks | [SDK receipt](partition-sdk-acceptance-receipt.json) |
| Independent partition review on compiled JavaScript | 20 review cases passed; framework import adaptation and exact source hashes disclosed | [Review](partition-review.md) |
| Independent partition fixture control | Three synthetic fixtures and 12 header/array CRC checks passed with Python `struct` and `zlib` | [Control output](partition-python-fixture-oracle.json) |
| Independent LZFSE streams and UDIF images | All 12 permanent vectors and all 12 UDIF oracle payloads pass the original Apple decoder with exact completion | [Fixture source](lzfse-fixtures.md), [UDIF report](lzfse-sevenzip-report.json) |
| External 7-Zip 26.06 UDIF extraction | Six exact successful extractions; six narrower-reader errors retained explicitly | [Results and oracle limits](lzfse-validation.md#independent-dmg-results-and-oracle-limits) |
| Selected source attribution/import boundary | Seven pinned BSD files verified; unchanged control passed and four tampering controls rejected | [Verifier controls](lzfse-verifier-controls.json) |
| Scoped analysis | Clean: no errors, warnings or infos in the recorded LZFSE and final partition scopes | [Archive scope](native-scoped-analysis-receipt.json), [partition scope](partition-scoped-analysis-receipt.json) |
| Full production JavaScript release build | Passed; source/version stamp, manifest restoration and bundled BSD license verified | [Web build](web-validation.md), [receipt](web-release-build-receipt.json) |

These runs overlap and their counts are **not additive**. The 418-test archive
gate predates two added DMG cases and a cosmetic braces change. The 82-test
follow-up and standalone codec checks qualify the later relevant bytes. Each
receipt records its exact source hashes rather than attributing uncommitted
work to a Git HEAD. The final partition and release-build receipts verify their
runtime files against published commit `fb57e8ab`.

Tool logs are retained verbatim, including terminal progress whitespace. Their
checksum manifests verify the recorded bytes; source/document whitespace checks
exclude these raw logs.

## Source and runtime boundary

The Apple source is BSD-3-Clause commit
`e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`. Its selected C files are retained for
review, while the application executes the bounded Dart port. The full license
is bundled and registered in the license screen. The original partition
inspector carries an MIT notice and uses the existing Apache binary field model.
No new Pub dependency, native codec, GPL/NC implementation or helper executable
is bundled. The external 7-Zip executable was used only for verification.

The full app build used **Flutter 3.47.8 / Dart 3.13.7** and the original
production manifest. Native tests used the existing locked dependencies, with
the optional native ebook conversion hook disabled temporarily because this
host lacks Cargo. The wrapper restored the manifest and lock byte-for-byte;
this profile and its hashes are fully recorded in the native receipts. The
new archive and partition implementations do not depend on that omitted hook.

The full compiled `main.dart.js` is 27,570,755 bytes, SHA-256
`84f5571fc1698b4347db220d96df68ad8eecf068b6703924cc2013536ab1db20`.
The build output remains reproducible from the pinned source and dependencies;
this evidence directory retains logs and identities, not third-party executables
or a duplicate generated application bundle.

## Preservation and hosted CI

All fetched **11 remote branch heads and 91 PR heads** were reachable from the
integration checkpoint. The original inventory and later main update remain
preserved; see [reconciliation](reconciliation-before-partition.json). Main's
CLI disk-usage update `b84f450c` was merged at `26540f65` before runtime changes.

Runtime work was saved incrementally:

| Checkpoint | Preserved work |
| --- | --- |
| `26540f65` | Latest main/CLI disk usage merged with the retained assessment |
| `a9cca4dd` | LZFSE decoder, DMG integration, license provenance and reference vectors |
| `767041f5` | Completed LZFSE native/JS/oracle qualification and cancellation follow-up |
| `fb57e8ab` | GPT/MBR inspector, Hex UI, independent-review fixes, regressions and focused CI |

The integration branch is
[`integration/storage-capabilities-20261114`](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114),
reviewed in [draft PR #101](https://github.com/CrispStrobe/CrispCloud/pull/101).
Existing remote branches were retained. Documentation/evidence checkpoints after
the qualified runtime do not change the runtime files.

The [hosted CI snapshot](hosted-ci-runtime.json) records **38 queued checks** on
the runtime commit. Queued checks are not passing validation. The new Storage
capabilities workflow has both portable source/JS and native viewer gates;
the completed results in this directory are local qualification.

## Remaining qualification and feature scope

WebAssembly, physical-device builds and native release packages were not built.
The large-image tests use sparse synthetic sources, including 5 TiB metadata
access and exact JavaScript offset boundaries; they do not scan a physical disk
of that size.

The partition feature reads metadata only. EBR traversal, filesystem browsing
through GPT/MBR, automatic repair and partition writing remain outside it.
LZFSE remains a bounded read-only DMG profile with explicit canonical-padding
requirements; encrypted DMGs, APFS and broader DMG writing remain unsupported.
UDF, ZIP salvage, filesystem adapters, OCI/VM semantics and transfer/recovery
extensions remain subsequent roadmap work.
