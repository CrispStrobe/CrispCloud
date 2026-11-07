# Storage analyzer baseline profile

These are measurements of **CrispCloud `ed79f873e1dc945641655689df94ebaac1dd6cb9`**, before the persistent native scan worker and the scanner validation/yield optimizations. The files preserve the evidence used to choose those changes. They are not measurements of the current branch.

## Protocol and limits

The fixture has 24,000 files, 460 directories excluding the root, 20 empty directories, and 359,116,800 logical bytes. It contains sparse files with ASCII names and no symbolic links. Create it with `tool/create_storage_scan_fixture.py`. No file contents are read by the measured scanner.

Each of eight modes ran one warmup followed by **three timed runs**, serialized against other benchmark and compiler jobs. Measurements use Flutter's test runner in **JIT** mode in a shared Linux x86_64 environment with a warm filesystem cache. Compilation, process startup, fixture creation, cached-backend preparation, and post-scan validation are outside the measured interval. These diagnostic runs are distinct from the five-run production and AOT benchmark series.

The full-scan modes check all absolute paths, file/directory flags, logical byte totals, subtree file/folder counts, unknown-size counts, skipped-link counts, and completeness against one baseline tree digest. This profile's digest does **not** include modification times. Because it includes absolute paths, its value changes when the fixture is placed elsewhere. The read-only worker experiment checks aggregate file/folder/byte counts and does not produce or validate a full analyzed tree.

`results.json` is the original raw output, including warmups. `summary.json` contains medians and ranges calculated from the three non-warmup rows. `provenance.json` pins the source commit, environment, protocol, original scratch-harness hashes, and unchanged raw-result hash. The portable copies below only change imports, environment-configured paths, comments, lint annotations, braces, and formatting; the measured algorithm is unchanged.

## Observations

| Mode | Median, ms | Range, ms | What is measured |
| --- | ---: | ---: | --- |
| `original` | 868.979 | 861.388–889.515 | Uninstrumented production scanner and native adapter at the pinned commit |
| `native_instrumented` | 911.008 | 908.816–953.298 | Same scanner and native listing operations with timing wrappers |
| `cached` | 237.618 | 222.944–241.373 | Scanner over prebuilt in-memory metadata; preserves adapter identity/path predicates |
| `cached_cheap_identity` | 239.868 | 232.862–241.737 | Same cached experiment with a constant identity/current-source callback |
| `cached_cheap_path` | 196.801 | 191.039–197.399 | Cached metadata plus cheap identity and simple path predicates, a lower-bound experiment |
| `cached_cloud_guard` | 344.397 | 338.709–351.661 | Cached metadata plus a fake cloud source that recomputes the namespace hash in identity and source checks |
| `single_worker_read_only` | 300.352 | 293.339–324.964 | All directories read by the existing synchronous native reader in one isolate; no tree validation/aggregation |
| `single_worker_full_scan` | 462.355 | 443.088–463.627 | Unchanged scanner in one isolate with synchronous stat/listing and constant fixture identity |

The whole-worker modes are research bounds. They omit a production access-scope, live-source, cancellation, and progress bridge. The cached cheap-path mode only operates on already validated fixture entries; its predicates are not appropriate for arbitrary provider data. The cloud mode uses a public test fake and synthetic identity values. It is not a cloud-network benchmark.

Selected medians from the instrumented native run:

| Bucket | Median, ms | Calls | Interpretation |
| --- | ---: | ---: | --- |
| `source_stat` | 203.010 | 461 | Root and pre-descent folder stat through the generic local backend |
| `source_listing` | 478.182 | 461 | Complete caller-side native listing operation |
| `native_spawn_worker_handoff` | 467.106 | 461 | Nested inside listing; isolate creation, worker work, scheduling, and response handoff |
| `native_worker` | 325.832 | 461 | Nested inside the preceding bucket; synchronous directory enumeration and metadata work |
| `scanner_validation` | 104.349 | 24,460 | Entry path validation, including nested path-operation buckets |
| `scanner_aggregation` | 24.076 | 24,461 | Building and sorting immutable subtree totals |
| `yield_directories` | 48.029 | 461 | Explicit end-of-directory event-loop yields |
| `scanner_source_checks` | 15.167 | 26,862 | Cancellation/current-source/identity checks, including nested identity/current buckets |

**These buckets overlap; do not sum nested rows.** The instrumented median is about 42 ms above the uninstrumented median. Tiny individual bucket timings include timer/wrapper overhead, and differences between medians are diagnostic estimates, not isolated causal experiments.

The repeated folder stat, one-isolate-per-directory overhead, repeated path parsing, and unconditional directory yields are larger local costs than identity checks or aggregation. The reader already checks a directory's no-follow type before and after enumeration; a reader capability can therefore remove the duplicate generic pre-descent stat while preserving that check in unguarded backends. A persistent worker retains main-isolate source/access checks while amortizing worker startup. Actual performance of the resulting implementation must be measured separately.

The SDK documentation for [`Isolate.run`](https://api.dart.dev/dart-isolate/Isolate/run.html) states that its final result is returned using `Isolate.exit`, transferring ownership without copying. A persistent worker's ordinary `SendPort.send` has different transfer costs for mutable object graphs; the full isolate/handoff bucket should not be described as copying cost or assumed to disappear entirely.

## Reproduce the pinned profile

Use the same Flutter/Dart version listed in `provenance.json` when comparing these numbers. From a checkout containing this evidence, prepare a separate baseline worktree so `original` and `single_worker_full_scan` reference the recorded production implementation:

```sh
git worktree add --detach ../crispcloud-profile-baseline ed79f873e1dc945641655689df94ebaac1dd6cb9
mkdir -p ../crispcloud-profile-baseline/tool/benchmarks
cp -R tool/benchmarks/scan_profile ../crispcloud-profile-baseline/tool/benchmarks/
cd ../crispcloud-profile-baseline
flutter pub get
python tool/create_storage_scan_fixture.py /tmp/crispcloud-scan-profile-fixture
SCAN_PROFILE_FIXTURE=/tmp/crispcloud-scan-profile-fixture \
  SCAN_PROFILE_OUTPUT=build/scan-profile/reproduced.json \
  flutter test --no-pub --reporter expanded tool/benchmarks/scan_profile/profile_scan_test.dart
```

If the local environment requires the existing CI system-SQLite workaround, replace `flutter test …` with `python tool/with_ci_system_sqlite.py flutter test …`. Do not run two instances of that helper at the same time because it temporarily adjusts the package configuration. `SCAN_PROFILE_PREPARE_ONLY=1` compiles and starts the test without performing measurements, for a separate preparation window.

The copied scanner and native reader are frozen instrumentation of the baseline. Running this harness directly on a later branch mixes those frozen modes with that branch's current `original` mode and must not be labeled a reproduction of the saved baseline results.
