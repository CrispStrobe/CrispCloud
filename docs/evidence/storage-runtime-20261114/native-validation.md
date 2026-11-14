# Native archive qualification — 2026-11-14

The nine-file archive gate passed **418 tests, zero failures, zero skips**. A later DMG gate passed **82 tests, zero failures, zero skips**, including two added mixed-codec/cancellation regressions. These runs overlap: their counts are not additive. Strict scoped analysis of 11 changed runtime, test, and support files found no errors, warnings, or infos.

## Toolchain and profile

Validation ran in a separate app checkout using **Flutter 3.47.8**, framework `737ba8f885dc774b53b442759999a312c9461e4e`, **Dart 3.13.7**, and genuine Debian **Clang 19.1.7 (3+b1)**. The exact toolchain origins, SDK/package checksums, and native library checksums are recorded in `native-runtime-environment.json`.

The app dependency graph resolved with `flutter pub get --enforce-lockfile`. No dependency versions were changed. Existing native hooks downloaded their normal pinned assets: SQLite **3.53.2** from the locked `sqlite3 3.3.3` package, and the original `libsmb2-r10` Linux x86-64 artifact. The existing PTY native sources compiled with Clang. A native-toolchain discovery message about Visual Studio appears in stderr on this Linux host; it did not prevent the Clang build or the passing test run.

Only the optional native ebook conversion hook was disabled during native archive tests because this host has no Rust/Cargo toolchain. This is the complete temporary manifest addition:

```yaml
hooks:
  user_defines:
    crisp_ebook_conversion:
      enabled: false
```

The wrapper restored the validation checkout's manifest and lock in `finally`, including after the earlier compiler-setup failure. The primary checkout's manifests were never written by the validation workflow. This qualification does not cover the omitted native ebook converter or a device/native release build.

| File | Production and restored SHA-256 |
| --- | --- |
| `pubspec.yaml` | `f10ba24448b047cf379dac0efeb11f8f60d9ae089022a831b12a6b32b8fa564f` |
| `pubspec.lock` | `2a0b95288cf41be9087af0c01ea57afcc4a2f138876d15709bff2f866060ccb4` |

Both successful native runs used temporary manifest SHA-256 `3f9463112deabc2a233697f9ce4c1c653f9a77699fed4b902108bcdb74a2265d`. Their receipts independently record production, temporary, and restored hashes and `lock_unchanged_during_test: true`.

## Passing tests

| Initial gate file | Passed |
| --- | ---: |
| `archive_lzfse_codec_test.dart` | 97 |
| `archive_lzfse_license_test.dart` | 1 |
| `archive_dmg_reader_test.dart` | 80 |
| `archive_adc_codec_test.dart` | 19 |
| `archive_hfs_reader_test.dart` | 40 |
| `archive_iso_reader_test.dart` | 47 |
| `archive_iso_multiextent_test.dart` | 32 |
| `archive_format_registry_test.dart` | 67 |
| `archive_container_dispatch_test.dart` | 35 |
| **Initial total** | **418** |

The later DMG run contains **82** passing tests. It adds a mixed raw/zlib/Apple LZFSE extent sequence and cancellation before a subsequent chunk. It also includes the final cosmetic braces fix in the decoder. The complete test events, per-file summaries, stderr, and command/profile receipts are retained as `native-archive-gate.*` and `native-dmg-followup-gate.*`.

## Exact tested source

The isolated checkout started at `f177bbe5b001f34398bc8c3ca193e502aa1e2aae`. Source synchronization copied every changed or untracked file from the primary checkout, with hashes recorded before testing. The initial gate's synchronization checkpoint was `26540f65fd63713ca1b543f793aa2e5d4a75c650`; the follow-up checkpoint was `a9cca4ddbcf139034c70d3a3b29896d6a75ccecb`.

These checkpoint identifiers alone are not a claim that the tested worktree was committed. Each receipt qualifies the actual bytes through `input_sources.files` and `tested_test_file_sha256`. Unchanged repository files come from `validation_base`; changed files use their listed SHA-256. In particular, the initial and later DMG test source hashes differ because two tests were added between the runs. `native-scoped-analysis-receipt.json` records the exact 11 analyzed source hashes after the lint fixes.

## Commands and records

`native-validation-env.sh`, `native-source-sync.py`, and `native-validation-profile.py` preserve the environment and helper scripts used in the scratch runtime directory. Their absolute paths document this run; they are evidence copies rather than app build scripts to execute from this directory.

The initial test command, executed by the temporary-profile wrapper, was:

```sh
flutter test --no-pub --reporter json \
  test/archive_lzfse_codec_test.dart \
  test/archive_lzfse_license_test.dart \
  test/archive_dmg_reader_test.dart \
  test/archive_adc_codec_test.dart \
  test/archive_hfs_reader_test.dart \
  test/archive_iso_reader_test.dart \
  test/archive_iso_multiextent_test.dart \
  test/archive_format_registry_test.dart \
  test/archive_container_dispatch_test.dart
```

The follow-up command was `flutter test --no-pub --reporter json test/archive_dmg_reader_test.dart`. Strict analysis used `flutter analyze --no-pub --fatal-infos --fatal-warnings` with the 11 explicit paths listed in its receipt. `native-evidence-sha256.json` checksums these native evidence files. The independent Apple oracle and actual compiled JavaScript acceptance records are maintained separately in the adjacent `lzfse-*` evidence.
