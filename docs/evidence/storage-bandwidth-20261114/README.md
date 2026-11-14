# Queued HTTP payload limits — source-bound evidence

The foreground **native common-HTTP profile is implemented and qualified**.
The wider G29 global-bandwidth gap remains partially implemented. Actual Chrome
helper acceptance is **pending hosted CI**, not inferred from JavaScript
compilation or native tests.

- Qualified source: [`d450a63e0041ef8d02f490b008681babf8ee6e38`](https://github.com/CrispStrobe/CrispCloud/commit/d450a63e0041ef8d02f490b008681babf8ee6e38).
- Remote branch: [`integration/storage-bandwidth-20261114`](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-bandwidth-20261114).
- Review: [draft PR #106](https://github.com/CrispStrobe/CrispCloud/pull/106).
- Baseline: `022ac6c91ccaa86f1d36a4d8cc1b20733037a67d` from main.
- Product boundary: [actual HTTP profile and remaining paths](../../file-manager-gaps/transfer-bandwidth-http-profile.md).

## Final local gates

All commands below ran after the implementation was saved remotely. Each used
the existing [source inventory runner](../storage-binary-20261114/run_gate.py),
which checks every tracked non-document blob before and after execution,
rejects untracked source files, and requires an unchanged package map. The
runner does not alter dependencies or permissions. Subsequent commits add only
documentation and evidence; their source is compared with the revision above.

| Gate | Observed result | Evidence |
| --- | --- | --- |
| Strict scoped analysis | Exit 0, no issues in 21 implementation/test files | [Receipt](final-analysis-receipt.json), [raw log, gzip](final-analysis.log.gz) |
| Allocator on Dart VM | 24 passed, 0 failed | [Receipt](final-allocator-vm-receipt.json), [raw log, gzip](final-allocator-vm.log.gz) |
| JavaScript compilation | Exit 0 with Dart 3.13.7, `-O2` | [Receipt](final-allocator-js-compile-receipt.json), [raw log, gzip](final-allocator-js-compile.log.gz), [actual compiled program, gzip](allocator.js.gz) |
| Actual compiled JavaScript execution | 24 passed, 0 failed in Node | [Receipt](final-allocator-js-receipt.json), [raw log, gzip](final-allocator-js.log.gz) |
| Native integration and regression cohort | **314 passed, 0 failed, 0 skipped**; all **28 expected suites** observed; no unfinished tests or hidden failures | [Parsed summary](final-native-summary.json), [receipt](final-native-receipt.json), [raw events, gzip](final-native-events.json.gz), [raw log, gzip](final-native.log.gz) |

All five receipts record **8,155 unchanged source paths**, the same source
inventory hash and the same unchanged package map. The inventory files are
byte-identical; their separate names preserve the original receipt references.

| Input | SHA-256 |
| --- | --- |
| Uncompressed source inventory | `15d8cd44ed74f1570cecc4701f86945ba553818fe3a2175dc478e15bccae25bc` |
| `pubspec.yaml` | `76799433117b092fc22766cc7a3557434813ee2d53b6ba61aa705f0532373441` |
| `pubspec.lock` | `27ed26a9e89f5c9baac9ee9c78e18ec1691a4eab2ed9e53d2a278ddeb45c1c2c` |
| `.dart_tool/package_config.json` | `1ad837e582ef0ccad7acdfb2fb96d467631920b909113816b7a1ccfcc5f747b7` |

The original production manifests and dependency versions are unchanged. The
[toolchain restoration receipt](toolchain/restoration-receipt.json) records the
verified Flutter 3.47.8 / Dart 3.13.7 archive, scratch-local Rust/Cargo 1.100.0,
Clang 19.1.7, exact package-cache restoration and locked dependency resolution.
Copied launcher sources preserve the hashes referenced by that receipt; they
are historical execution inputs, not an installed SDK in this directory.

The local native run used the original bundled native-asset configuration.
Hosted CI uses the repository's existing **CI-only system SQLite wrapper**,
which probes SQLite and restores its temporary manifest hook in `finally`.
The workflow verifies the original manifests afterward and records its actual
Rust/Cargo/Clang and runner-image versions. Neither profile changes production
dependency selection.

## Actual native HTTP measurements

The loopback fixture used two simultaneous IOClient operations, each uploading
16,384 bytes and consuming the echoed response. Both directions had one shared
32,768 B/s cap. Raw emitted JSON is retained in the native log/events and parsed
in the summary.

| Observation | Result |
| --- | ---: |
| Aggregate upload payload | 32,768 bytes |
| Aggregate response payload | 32,768 bytes |
| Last upload completed after | 1,061.082 ms |
| Response-consumption interval | 1,058.944 ms |
| Total elapsed | 2,115.646 ms |

Original inputs, server-received bodies and returned bodies matched. Each
direction's observed interval lies within the fixture's 800–8,000 ms bounds;
the lower bound detects independent per-operation caps accidentally replacing
the aggregate cap, while the upper bound tolerates loaded test hosts. This is
a small loopback acceptance fixture, not a live-provider throughput benchmark
or a large-file stress claim.

The 14 HTTP tests additionally cover buffered/streamed/multipart finalization,
headers and request policies, captured context, independent pools and metadata
accounting, retries, malformed length/metadata bounds, closed empty requests,
and both operation and original-request abort signals while IOClient waits for
response headers. Nine queue tests cover batch fairness, sibling lifetimes,
pause semantics, cancellable settings waits, disposal, retries and recovery
from a failed policy load.

The declared [native suite inventory](../../../tool/transfer_bandwidth_tests.txt)
also retains scheduler, journal/recovery, existing logical limiter, provider
transfer and localization regressions. New UI cases exercise persisted policy,
save failure, unreadable settings, shared controls and enlarged German/Arabic
layouts. The eight platform-neutral HTTP-policy cases passed **on the native
runtime** in this cohort; that is not a Chrome result.

## Hosted browser status

[The dedicated workflow](../../../.github/workflows/transfer-bandwidth.yml)
runs the allocator on VM/JavaScript, the declared native cohort and the
platform-neutral helper tests in actual Chrome. At the observation saved in
[`ci-status.json`](ci-status.json), both jobs were still queued:

- [Push run 43631458997](https://github.com/CrispStrobe/CrispCloud/actions/runs/43631458997).
- [PR run 43631531807](https://github.com/CrispStrobe/CrispCloud/actions/runs/43631531807).

Chrome tests use MockClient inside the actual browser runtime to check the
compiled conditional policy: upload-body collection is explicitly unsupported
and uncounted, while covered response consumption uses the download pool. They
do not establish real-fetch timing, remote-service behavior or socket-level
receive throttling. Local Chrome was not attempted in this continuation; the
previous environment's Unix-socket restriction was not bypassed or retried.

## Preliminary failures and corrections

Development runs are retained under [`preliminary/`](preliminary/) and are
explicitly **not source-frozen qualification**. Counts overlap the final cohort
and must not be added to it.

| Run | Observed result | Interpretation |
| --- | --- | --- |
| Native asset warmup | 22 passed, 0 failed/skipped | Existing queue/control/logical-limiter cohort after toolchain restoration |
| HTTP + queue first runtime attempt | 23 passed, 0 failed/skipped | Includes actual loopback and response-header aborts; exact timing telemetry was added before final qualification |
| UI attempt 1 | 37 passed, 10 failed | Widget-clock fixture issues plus duplicated-finder assertion and a real enlarged German Activity overflow |
| UI attempt 2 | 41 passed, 6 failed | Behavior/layout assertions passed; unowned test-provider rate-decay timers failed widget teardown |
| Dialog attempt 3 | 10 passed, 0 failed/skipped | Owning ProviderScope fixed the test fixture; final 28-suite cohort subsequently passed together |

The production layout correction keeps the full logical operation header in
the bounded scrolling region on narrow screens with enlarged text. It preserves
the metrics and keeps the expansion control reachable. Fixture corrections
create/own controllers within Flutter's widget lifecycle. Raw preliminary
events/stderr, their parsed counts and existing run receipts are preserved;
failed runs have not been relabelled successful.

## Earlier comparison qualification

The earlier comparison source `22bd67b8` has independent hosted evidence:
**1,373 native and 31 actual-Chrome comparison tests passed**. The complete
storage workflow later failed because the external FatFs reference archive
server timed out. [The preserved artifact and receipt](../storage-binary-20261114/hosted-22bd67b8/README.md)
record that distinction. Those counts belong to the earlier source and are not
part of this bandwidth acceptance.

## Artifact integrity and reproduction

[`artifact-sources.json`](artifact-sources.json) records original source-file
hashes and stored bytes for exact copies or deterministic gzip encodings.
[`files.json`](files.json) hashes this evidence directory except itself.
Receipts retain the exact command, source tree, start/end time, raw log hash and
package-map checks. The readable native summary is derived from the retained
JSON event stream, excluding hidden loader records from test totals.

To reproduce with the pinned SDK and the original locked dependencies, run the
commands in the receipts or the dedicated workflow. The pure driver uses only
SDK imports and can run directly with `dart`; it does not require `dart run`
or unrelated native hooks. Native suites are the exact paths in the declared
inventory. Browser tests require the Chrome runtime explicitly. Any failure,
skip or incomplete run remains distinct from a passing qualification.
