# Zotero local validation — 15 November 2026

The host was qualified at CrispCloud commit
`803537e0c1e5dc3acf4c3659a37515dfb78224d7`, including main
`50b459323fe798c3638b8b8ce499ea91b89f98c0` through PR #148, with shared Quds
source `9da9c638bfe3bf932a70b2268dc16ef783fc009a` (main through PR #39).
Later documentation/source-pin commits retain the tested code hashes. The
current exact source pin lives in `tool/office_fidelity_manifest.json`.

## Results

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

## Evidence and reproduction

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

## Important assertions

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

## Boundaries

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
