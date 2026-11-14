# Preserved preliminary evidence

These files preserve setup failures, intermediate working-tree test results,
and a separately bound failed candidate. They do not qualify later commits. Every copied log is
byte-preserving after deterministic gzip decompression. [files.json](files.json)
records original and stored sizes and SHA-256 values. No raw internal approval
review text is included; see [setup notes](../setup-notes.md) for the public
dependency request diagnosis and outcome.

| Attempt | Result | Evidence |
| --- | --- | --- |
| Original locked dependency resolution | Exit 0; manifests unchanged | `dependencies.log.gz`, `manifest-before.json`, `prefetch-results.json.gz` |
| First native launch | Stopped during dependency setup; no tests loaded and no log output | `initial-native.log.gz`, `initial-native-source.json` |
| Native retry | Cargo shim lacked its scratch toolchain location; no tests loaded | `initial-native-retry.log.gz`, `initial-native-retry-source.json` |
| Native run after Cargo setup | Missing Clang stopped the PTY hook; no tests loaded | `initial-native-cargo.log.gz` |
| Native run after compiler setup | Exit 0; 52 passed, 0 failed, 0 skipped | `initial-native-clang.log.gz`, `initial-native-clang-events.json.gz`, `initial-native-summary.json` |
| Initial widget run | 6 passed, 3 failed; settling expectations on intentionally stalled UI | `widget-initial.log.gz` |
| Widget retry after harness correction | Exit 0; 9 passed, 0 failed, 0 skipped | `widget-retry.log.gz` |

Native runs used the original project manifest and the following suites:

```text
test/binary_comparison_source_test.dart
test/binary_comparison_limits_test.dart
test/binary_comparison_navigation_test.dart
test/file_comparison_service_test.dart
```

The two source inventories were captured for earlier attempts while the
working tree was still changing. They are retained as observations, not reused
as bindings for a subsequent successful run. Likewise, the successful summary's
`observedRevisionAfterRun` does not establish a frozen test revision. Final
source inventories and gate results are kept separately at the evidence root.

The Cargo fetch logs show normal resolution of the existing catalogue and
ebook dependencies. They establish tool/cache setup only, not runtime test
coverage.

## Widget commands

Both preliminary widget runs used the same scratch toolchain wrapper and:

```text
flutter test --no-pub --reporter expanded test/widget/comparison_navigation_test.dart test/widget/diff_viewer_localization_test.dart
```

Each was preceded by formatting `test/widget/comparison_navigation_test.dart`.
Neither captured a complete pre-run source inventory. The recorded outputs
remain preliminary working-tree evidence.

## Saved-candidate failure

[candidate-542c1c8b](candidate-542c1c8b/README.md) retains the expanded native
gate's reused-provider-buffer failure and a strict-analysis lint. Unlike the
working-tree attempts above, those receipts bind their exact saved revision,
source tree and unchanged 8,111-path inventory. Both failed results remain
preserved independently of later output-name reuse.
