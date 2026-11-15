# Zotero rich formatting — host qualification

The implementation is synchronized from exact Quds commit
`f40aa887325982ea70c8285b25f8ff5b92a46eb9`. Its library/test source is identical
to the fully tested code commit `b09537fb34dd711118ae6df5872184b6e813d2df`.
The final CrispCloud source checkpoint is
`9f1c8e144958fc88451be558d09f304f35ea0640`.

## Results and source identity

| Local check | Result | Evidence |
| --- | ---: | --- |
| Canonical Quds engine/client/parser/Word import cohort | 232 passed | [Canonical receipt](https://github.com/CrispStrobe/quds_office_suite/blob/f40aa887325982ea70c8285b25f8ff5b92a46eb9/docs/validation/zotero-rich-text-20261115/final/receipt.json) |
| Canonical shared Flutter controller/formatter/dialog cohort | 81 passed | Same canonical receipt |
| Actual host service/transport/credential/target and ribbon cohort | 23 passed | [host-tests.log](host-tests.log) |
| Changed canonical engine/editor analysis and formatter | Clean | Canonical receipt |
| Seven host analyzer targets with `--fatal-infos` | Clean | [host-analysis.log](host-analysis.log) |
| Normal vendor guard and `--require-tracked` | 2,379 entries verified | [normal](crisp-vendor-verify.log), [tracked](crisp-vendor-verify-tracked.log) |
| Integrated terminal shell helper smoke | 3 scenarios passed; 0 skipped | [terminal-shell-smoke.log](terminal-shell-smoke.log) |

The Zotero/related Word/host total is **336 tests**, without counting baseline
or development reruns again. The three shell scenarios are separate. The prior
Quds source also passed 171 baseline tests, including all 39 previously
unexecuted cases; the new increment adds 63 canonical regression cases.

The exact host command/environment, source hashes, locked dependency graphs,
runtime identities and analyzer-copy verification are retained in
[host-validation-receipt.json](host-validation-receipt.json) and
[host-source-hashes.json](host-source-hashes.json). All actual host and vendored
library sources were fingerprinted before and after the host tests.

## Managed-source verification

The standard `sync_office_fidelity.py` dry-plan and apply workflow was used.
Both variants of `verify_office_fidelity.py` were executed, rather than inferred
from remote blobs. The [inventory manifest](crisp-vendor-inventory.json), with its losslessly compressed
complete inventory and both SHA-256 hashes, covers
**522 Quds files + 1,857 standalone parser files = 2,379 entries**. Every managed
Quds blob and file mode matches its exact canonical source. Existing standalone
parser hashes, modes and blobs remain unchanged at
`4895712158127b2fc930d796e17035c3ca0dac62`.

The plan and inventory retain the host base/staged tree at verification time.
The separate public transport import is outside the managed Quds inventory and
is included in the host test/analyzer source hashes. Subsequent evidence/guide
commits do not change the qualified source trees or manifest.

## Reproduction and limits

The runtime is official Flutter 3.47.8 / Dart 3.13.7. The focused host harness
symlinks the actual host `lib` and both original test files, with actual vendored
package source links. It resolves genuine dependencies with enforced lockfiles.
Scratch manifests and path dependencies are rebased to the checkout; production
manifests and dependency constraints remain unchanged. Analysis uses fresh
byte-identical host source copies to avoid symlink context ambiguity.

The [earlier setup recipe](../zotero-20261115/SETUP.md) describes reconstruction;
use the manifests and lockfiles in the current receipt. From the resolved
harness, run:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
  test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
```

From the real checkout, run:

```sh
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
python3 tool/verify_office_fidelity.py --source ../quds_office_suite --require-tracked
python3 tool/terminal_shell_setup_smoke.py
```

This is focused qualification, not a full native application build or all
terminal widget/SSH tests. No live private Zotero account, desktop database,
real OS keychain or native Word/Zotero refresh acceptance is claimed. Complete
CSL processing, native picker/HTTP citing adapter, active ODT transfer, small
caps/paragraph layout and new mixed-format inline citation generation remain
outside this increment. See [the user guide](../../zotero.md).

[branch-audit.json](branch-audit.json) accounts for all 15 Quds and 30 CrispCloud
heads. Main through Quds #42 and CrispCloud #152 is included. Terminal #140's
three newer commits through `4cd8065a` were merged at `3b8b79fc`, retaining both
parents, before feature implementation. No GitHub Actions were polled, awaited
or rerun. Every new checkpoint uses `[skip ci]`.
