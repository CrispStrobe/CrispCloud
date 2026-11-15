# Zotero validation — 15 November 2026

## Rich formatting continuation: current executed results

The final shared source is pinned to Quds
`f40aa887325982ea70c8285b25f8ff5b92a46eb9`, whose library/test trees are identical
to the fully tested code commit `b09537fb34dd711118ae6df5872184b6e813d2df`.
The final actual host qualification ran at
`9f1c8e144958fc88451be558d09f304f35ea0640`.

| Local check | Result |
| --- | ---: |
| Canonical engine/client/parser/Word import and related regressions | 232 passed |
| Canonical shared Flutter controller/formatter/dialog regressions | 81 passed |
| Actual CrispCloud service/transport/credential/target and ribbon tests | 23 passed |
| **Combined selected tests** | **336 passed** |
| Canonical changed-path and seven-target host strict analyzers | Clean |
| Canonical changed Dart formatter check | Clean |
| Normal Python vendor guard and Git-index guard | 2,379 managed entries verified |
| Integrated terminal Bash/Zsh smoke, counted separately | 3 scenarios passed, none skipped |

The preceding Quds source independently passed 171 baseline tests, including
all **39 previously unexecuted cases**. Those overlapping baseline results are
not added again to 336. This continuation adds **63 canonical regression cases**.

Current evidence, exact source identities, manifests/locks, log hashes and
reproduction steps are under
[validation/zotero-rich-text-20261115](validation/zotero-rich-text-20261115/README.md).
The actual host/vendored library hashes were unchanged during tests and analysis;
analyzer source copies were byte-identical to production. Official Flutter
3.47.8 / Dart 3.13.7 and genuine enforced Pub lockfiles were used. Production
manifests and dependency constraints were not relaxed.

The normal guarded sync verified **522 Quds + 1,857 standalone parser files**.
The parser pin remains `4895712158127b2fc930d796e17035c3ca0dac62`.
Main through Quds #42 and CrispCloud #152 and the newer terminal #140 commits
through `4cd8065a` are included. No GitHub Actions were polled, awaited or rerun;
new remote checkpoints use `[skip ci]`.

Full native builds, live desktop/private-account connectivity, real OS-keychain
acceptance and native Word/Zotero refresh remain unverified. This increment does
not add a full document-wide CSL processor, native picker/HTTP citing adapter,
active ODT transfer, small-caps/paragraph-layout rendering or new mixed-format
inline citation generation. Earlier sections below retain their original source
revisions and historical limitations.

## Earlier local identity continuation: historical source review

This continuation adds identity-checked desktop operations for unsynced
`users/local/<localUserKey>/items/<itemKey>` references. It also checks numeric
reference identities before connected document operations and prevents
two-phase desktop exports from accepting a database or library-version change.

**No Dart/Flutter tests, analyzer, formatter or full application builds were
executed in this continuation.** The execution service returned
`No usable execution environment is available` during setup attempts.
No GitHub Actions were awaited, polled, rerun or used as validation.

Fresh checks are repository/source checks: exact-context integration of recent
main changes, remote checkpoint/head verification, source review of the new
code/tests, and CrispCloud's managed-source comparison to its pinned canonical
Quds source. These checks do not establish that the Dart code compiles or
that the widget regressions pass.

New regression cases cover URI/route separation, colliding item keys in
different local profiles, wrong or missing returned identities, alias
normalization, zero network calls for incompatible requests, exact selection
completeness, server/database and library-version changes, and preservation of
original DOCX identities. The existing online and desktop tests remain in place.

### Run locally

Use the repository's Flutter/Dart toolchain and resolve the workspace dependencies
before running the tests. The shared packages are used by both hosts:

```sh
flutter pub get
cd packages/quds_office_engine
dart test test/zotero_client_test.dart test/zotero_identity_client_test.dart test/word_zotero_test.dart
dart test test/ods_sheet_reader_test.dart test/word_content_control_fidelity_test.dart
cd ../quds_office_editor
flutter test test/word_zotero_format_test.dart test/word_zotero_dialog_test.dart test/word_zotero_controller_test.dart
cd ../..
```

Run the repository analyzers/format check on the changed sources as well.
For host acceptance, build a native Quds Studio or CrispCloud application, then
use an unsynced Zotero library with the local API enabled. Exercise insertion,
individual preview, basic refresh, bibliography and reference export; save and
reopen the DOCX. Check that a different database with a colliding item key
refuses refresh/export and leaves the document unchanged. Check source
switching, a delayed response after caret/document changes, and an older Zotero
client without the database header. Native Word/Zotero refresh acceptance
remains outstanding.

The current evidence is under
[validation/zotero-local-identity-20261115](validation/zotero-local-identity-20261115/).
The following older results retain their original source hashes and do not
count as current test passes.

### Host verification

The new shared client/editor files are vendored from the exact Quds pin in
`tool/office_fidelity_manifest.json`. The initial recent-work integration is
recorded in [recent-integration.json](validation/zotero-local-identity-20261115/recent-integration.json).
It compared all 2,374 then-managed blob identities, modes and lengths, freshly
hashing the six changed canonical files; the standalone parser pin stayed
`4895712158127b2fc930d796e17035c3ca0dac62`.

For the current feature source, see the [final source integration receipt](validation/zotero-local-identity-20261115/final-integration.json). Unchanged immutable blobs reuse earlier SHA-256 evidence;
changed/new files are freshly hashed and matched against Quds. This remote
comparison does not mean the Python guard ran in this execution environment.

From a resolved local CrispCloud checkout, rerun the host tests and guard:

```sh
flutter test test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
```

## Earlier desktop continuation: historical results

The new desktop API work is saved at Quds code commit
`1cc4d251ebeb3e0cce205805e9183396da0c0df4` and CrispCloud code commit
`3c4cd0e24ab36f4fd88363cbc8521455bda811c6`. Subsequent audit/documentation or
source-pin commits can retain these exact tested source hashes.

| Fresh check | Result | Scope |
| --- | ---: | --- |
| Complete canonical Zotero client test file | 34 passed | 19 existing and 15 desktop protocol/identity regressions |
| Actual production CrispCloud HTTP boundary | 16 passed | 8 existing and 8 new transport tests, using original test-group/helpers |
| Focused Dart analysis with `--fatal-infos` | Clean | Client/models, pure host transport and the two focused test files |
| Changed Flutter/Studio Dart parsing | Formatter succeeded | Syntax only; not Flutter type analysis or widget execution |

**50 focused tests ran in this continuation.** Its source snapshots are
byte-identical to the production client/models/test and new pure transport
file. The host harness retains the transport tests verbatim and substitutes
`package:test` imports for Flutter imports; it does not substitute production
implementations or dependency stubs.

The runtime was official Dart 3.13.7, with genuine Pub resolution (`test` 1.33.0,
`http` 1.6.0). The workspace was nearly full and full repository clones failed.
An official SDK subset enabled genuine frontend compilation, VM execution with
assertions and static analysis. Exact installed-file hashes, CRC32 checks,
commands, manifests/lockfiles, original logs and reproduction scripts are under
[validation/zotero-desktop-20261115](validation/zotero-desktop-20261115/), starting
with [SETUP.md](validation/zotero-desktop-20261115/SETUP.md) and the
[validation receipt](validation/zotero-desktop-20261115/validation-receipt.json).
GitHub saves used content-addressed trees and expected-head ref updates.

New shared dialog and CSL import regressions are committed, including local
credential isolation, numeric/unsynced/offline identities, source switching and
a 320 × 640 desktop connection/error case. These Flutter cases **were not run**
in this continuation. Full native builds, the complete application/provider
graph, other host credential/controller/ribbon cases, live Zotero desktop and
private-account connectivity, OS keychain acceptance, and native Word/Zotero
refresh acceptance remain unverified. The earlier counts below are historical
results for their recorded sources, not fresh qualification of the new UI.

No GitHub Actions were awaited. Checkpoints carry `[skip ci]`.

## Earlier desktop managed-source verification

The final integration checkpoint is CrispCloud
`e43fc424c5cb58bec93ee33c3f81de15f4f921db`, pinned to Quds
`244474c688c3a49a6fbcd98acc501a06794c1370`. The subsequent receipt/document-only
commit does not change managed Office files or tested production/test sources.

The [final integration receipt](validation/zotero-desktop-20261115/final-integration.json)
links the independent full archive audit of **2,374 managed files** and proves
that 2,372 retain identical Git blobs, modes and sizes. The only two changes,
the engine/editor changelogs, were freshly hashed and matched against the final
manifest and canonical Quds source. All **517 Quds files and 1,857 legacy files**
match their pinned sources; the inventory and standalone parser pin are unchanged.

The same receipt confirms that the source/test bytes behind the fresh **50
passing tests** match the final remote trees. Terminal draft #140 is integrated
through `b0b3334b2160ee7d43378d730803f32781a53968`; its last three changed paths
are disjoint from managed Office content. This integration check does not claim
a new terminal test run. See [VENDOR.md](validation/zotero-desktop-20261115/VENDOR.md)
for the full audit method, archive inventory and reproducer.

## Earlier Web API increment: historical results

The following evidence belongs to the earlier implementation and is retained
with its original source identity and limits.

The host was qualified at CrispCloud commit
`803537e0c1e5dc3acf4c3659a37515dfb78224d7`, including main
`50b459323fe798c3638b8b8ce499ea91b89f98c0` through PR #148, with shared Quds
source `9da9c638bfe3bf932a70b2268dc16ef783fc009a` (main through PR #39).
Later documentation/source-pin commits retain the tested code hashes. The
current exact source pin lives in `tool/office_fidelity_manifest.json`.

### Results

| Check | Result | Scope |
| --- | --- | --- |
| Host service and real ribbon tests | 15 passed | 13 target/transport/credential tests and 2 menu/ribbon tests |
| Host focused analyzer | No issues found | Exact source files and production lint settings listed in the receipt |
| Shared Quds engine/client/field cohort | 66 passed | Canonical source, before and after latest-main integration |
| Shared Quds editor suite | 43 passed | 11 controller, 24 formatter and 8 dialog tests |
| ODS reader integration check | 78 passed | Separate latest-main/vendor-merge regression check |
| Vendor/source guard | 2,374 files verified | Exact canonical source plus unchanged standalone parser pin |

That is **124 focused Office/Zotero tests plus 78 ODS integration regressions**.
This is not a full application or workspace test total. Previous storage,
native-format and spreadsheet qualification records keep their own source
identities and are not added to these counts.

### Evidence and reproduction

The [evidence directory](validation/zotero-20261115/) contains the host receipt,
source SHA-256 values, exact focused/analyzer manifests and locks, setup note,
and final logs. Shared-source evidence is preserved in
[Quds Office's validation record](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-support-20261115/docs/zotero-validation.md).
The [branch audit](validation/zotero-20261115/branch-audit.json) records the
latest reviewed branch/PR heads.

Tests use official **Flutter 3.47.8 / Dart 3.13.7** and genuine dependencies
pinned from the production lockfile, with unchanged production `lib` and `test`
sources in a minimal scratch package. Analysis uses byte-identical source
copies with the production lint rules. The harness setup and exact resolved
manifests are retained so the check can be reproduced without claiming a full
resolution/build of unrelated native providers.

The host test command, from that prepared package, is:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
  test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
```

From the CrispCloud checkout, with the pinned Quds source commit fetched in the
sibling checkout, the canonical mirror check is:

```sh
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
```

### Important assertions

Host tests compile the actual service, localization and ribbon implementations.
They cover the original document/revision/caret/selection/story target captured
before asynchronous credential loading; the fixed HTTPS destination;
header-only keys; disabled redirects; declared and streamed response limits;
whole-request timeout and stalled-body cancellation; disposal; and sanitized
errors. Credential tests verify persistence capability, write/read-back/delete,
invalid-key rejection, backend errors and preservation of unrelated keys.

The real Word Insert menu and References ribbon invoke Zotero. Viewing mode
disables editing, and hosts that omit the optional callback do not show the
entry point. Shared widget tests additionally cover import/insertion/undo,
stale targets, the full 320 × 640 flow, immediate stored-key opt-out, secret
exclusion from saved DOCX, and preservation of imported bibliography choices.

The vendor merge was resolved using the complete combined canonical Quds
source. The guard verifies all 2,374 managed files. The separately maintained
legacy DOC parser remains pinned to
`4895712158127b2fc930d796e17035c3ca0dac62`.

### Boundaries

No GitHub Actions checks were awaited; remote checkpoint messages use
`[skip ci]`. No full native CrispCloud build was run: this environment does not
have the Rust/Cargo toolchain needed by unrelated native components. The full
`office_editor_dialog.dart` provider graph was not analyzed by the minimal
harness; its extracted target guard was compiled/tested, and integration wiring
was reviewed against the actual providers and shared API.

Credential adapters were tested with injected stores, not a real operating
system keychain. No private Zotero account or user key was used. Native
Word/Zotero refresh acceptance, full document-wide CSL processing, desktop
citing transactions and active ODT citation transfer remain outside this
qualification. See [`zotero.md`](zotero.md) for the supported user workflow and
formatting limits.
