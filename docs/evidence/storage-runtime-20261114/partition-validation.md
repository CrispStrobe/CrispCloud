# Partition inspection qualification — 2026-11-14

The final combined Flutter gate passed **58 tests, zero failures, zero skips**. Strict analysis of **nine** runtime, UI, test and fixture files found no errors, warnings or infos. The SDK acceptance driver passed **14 groups / 516 checks** on both the production Dart **3.13.7** VM and the actual compiled JavaScript running in Node **24.22.1**.

The tested partition runtime, UI, fixture, all four Flutter test files, and final SDK driver were verified byte-for-byte against published source commit **`fb57e8abb22e1a2fe588c1a22d9ac0326e7358ee`**. The source owner froze the inspector at SHA-256 `46f5e40daa9818f6bf05b2cfe67bf0e03617deb58a6b5b719d51453391090ebf`; the final SDK driver is `7eea895265bc909c198b198c1d92e7bf7c6478702022c1139108bb2a84def6f7`. Each receipt records exact source hashes and the published-commit comparisons.

## Native and widget gate

| Test file | Passed |
| --- | ---: |
| `test/disk_partition_inspector_test.dart` | 24 |
| `test/disk_partition_inspector_review_test.dart` | 20 |
| `test/widget/disk_partition_viewer_test.dart` | 8 |
| `test/widget/binary_structure_viewer_test.dart` | 6 |
| **Total** | **58** |

The independent review cases cover reserved GPT/PMBR bytes, 4096-byte PMBR tails, changed signatures between probe and full read, a mirror table pointer into partition payload, late short/oversized reads, final-validation cancellation, two bounded 1 MiB arrays, and the maximum exact JavaScript source offset. The viewer tests cover independently invalid primary-header and backup-array CRC results, selection of real backup metadata beyond 64 KiB, byte/source preservation, explicit sector sizes, short unknown files, cancellation/disposal, narrow layouts with enlarged text, and localization.

The test command was:

```sh
flutter test --no-pub --reporter json \
  test/disk_partition_inspector_test.dart \
  test/disk_partition_inspector_review_test.dart \
  test/widget/disk_partition_viewer_test.dart \
  test/widget/binary_structure_viewer_test.dart
```

The same isolated native-test profile described in `native-validation.md` disabled only the optional native ebook conversion hook. The original dependency lock and ordinary SQLite, SMB and PTY native assets were used. The wrapper restored both manifests exactly. `partition-native-gate-receipt.json` records the production, temporary and restored manifest hashes; no primary checkout manifest was changed by validation. Earlier 12- and 13-widget passes were intermediate overlapping runs, not additional tests to add to this total.

## Actual JavaScript and VM acceptance

`partition-vm-acceptance.log`, `partition-js-compile.log`, `partition-js-acceptance.log`, and `partition-sdk-acceptance-receipt.json` retain the final driver runs. The actual `dart compile js -O2` output is **138,279 bytes**, SHA-256 `83c24572f4de0afe889fe33ae5569513cb2b05cb56c5d49df3d1c4269204b007`. Node aliases `globalThis.self` to `globalThis` to provide the browser global used by Dart's asynchronous timer runtime; the parser and checks run from the actual emitted JavaScript. The VM and JavaScript check totals overlap and are not additive.

The separate full production application build is recorded in `web-validation.md`, with its production manifest hashes, source/version stamps and bundled Apple license verification.

## Independent fixture control

`partition-python-fixture-oracle.json` is the directly captured output of the independent Python standard-library control: **three fixtures and 12 CRC checks passed**. It checks 512-byte and 4096-byte logical sectors and a sparse **5 TiB** fixture. Python `struct` and `zlib.crc32` validate both GPT headers and both partition arrays, plus geometry and names, independently of the production inspector's CRC implementation. This fixture-integrity result is distinct from the inspector behavior and UI tests. `partition-python-fixture-oracle.md` preserves the command and frozen supporting source hashes.

`partition-scoped-analysis-receipt.json` records the nine exact analyzed files and the strict `--fatal-infos --fatal-warnings` command. `partition-evidence-sha256.json` checksums the partition evidence bundle, including the independent review records. No physical 5 TiB image, filesystem payload scan, partition write/repair, native/device release build, or WebAssembly build is claimed by these checks.
