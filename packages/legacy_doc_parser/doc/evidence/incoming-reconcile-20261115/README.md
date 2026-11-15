# Current-main reconciliation and local parser acceptance

Saved source: [`08296edbee08da013a8ff718798972552ccd03f7`](https://github.com/CrispStrobe/legacy-doc-parser/commit/08296edbee08da013a8ff718798972552ccd03f7).

This merge retains the continuation's explicit `FormatException`/`CfbfException` bounded recovery helper and all earlier source and receipt history. It adds current main's independent compound-directory regression. Production bytes are unchanged from continuation `57442c79239fb4d483e274e0ebb04f34686beb6c`; only the added test changes runtime inputs.

## Observed gates

| Gate | Result |
| --- | --- |
| Complete ordinary parser inventory | **4,132 passed in 144 suites**, no failures, errors, skips, missing or unexpected suites |
| Strict analysis | **18 files, no issues**, fatal infos and warnings enabled |
| Dependency resolution | Historical standalone lock restored; `pub get --enforce-lockfile` passed with lock and declarations unchanged |
| Input stability | Before/after source, saved HEAD/tree, resolved package inputs and recorded tool hashes unchanged |

The Dart version is 3.13.7 from Flutter 3.47.8. The standalone graph retains archive 4.7.1, test 1.33.0 and XML 6.6.1. Host acceptance uses its own separately recorded graph.

## Evidence

`artifacts.tar.xz` contains the exact raw machine stream, per-suite results, commands, before/after input snapshots, executable hashes, dependency setup output and package snapshots, test/analysis inventories, and the gate runner. `artifacts-manifest.json` records every member's uncompressed size and SHA-256. The archive inventory and all member hashes were independently checked after creation.

The archive also records a fresh integrity audit of the recovered earlier 4,122-test/143-suite and 4,131-test/144-suite receipts, the nine directory-recovery controls and the earlier strict analysis. Historical counts were recomputed from raw events and their complete artifact inventories and stable input snapshots were checked.

Before/after hashes establish input stability at observation points, not a hermetic cache or absence of transient writes. These results qualify the recorded Dart unit and analysis scope, not external Office rendering or broad schema acceptance. No GitHub Actions run was awaited or restarted.
