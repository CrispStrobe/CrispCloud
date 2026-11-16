# Incoming engine package qualification

At application source `94857cf415965826b8ed08eafd3b05dafc29b353`, the four selected incoming engine suites pass through the engine package’s own declared dev dependency graph. This is separate from the application Flutter graph.

## Commands

Run from `packages/quds_office_engine`:

```sh
../../../toolchain/run dart pub get --offline
../../../toolchain/run dart test --concurrency=2 --reporter=expanded \
  test/zotero_metadata_batch_test.dart \
  test/zotero_client_test.dart \
  test/word_zotero_scaling_test.dart \
  test/word_zotero_citing_test.dart
```

Result: **118 passed, 0 skipped, 0 failed** with Dart **3.13.7**, `test` **1.31.1**, `test_core` **0.6.18** and `test_api` **0.7.12**. All **5,556 watched source, dependency and test files** remain unchanged.

The engine had no existing or tracked package lock. Normal `dart pub get --offline` produced its own package configuration and lock, copied unchanged to `incoming-engine-pubspec.lock`. Application manifests, the production application lock, engine/parser manifests, source files and assertions were not changed. No harness substitutions or dependency overrides were introduced.

## Runtime identity

Every runtime dependency resolves to the exact same package directory as the application graph; hosted package versions and archive digests also match. The normal standalone dev graph adds `package:test` and its tools, which are absent from the application dependency graph.

| Runtime dependency | Standalone engine | Application |
| --- | --- | --- |
| archive | 4.6.0 | 4.6.0 |
| characters | 1.4.1 | 1.4.1 |
| collection | 1.19.1 | 1.19.1 |
| crypto | 3.0.7 | 3.0.7 |
| ffi | 2.2.0 | 2.2.0 |
| legacy_doc_parser | 0.1.0-dev.1 | 0.1.0-dev.1 |
| meta | 1.19.0 | 1.19.0 |
| path | 1.9.1 | 1.9.1 |
| posix | 6.5.4 | 6.5.4 |
| typed_data | 1.4.0 | 1.4.0 |

`incoming-engine-dependencies.json` records all 53 resolved packages, both graphs’ versions/source descriptions/archive digests, normalized package roots and test-only differences. `incoming-engine.json` records exact commands, timings, initial/final production hashes and counts. Logs and the compressed complete source map are adjacent.

The earlier application-graph Flutter attempt could not load these four engine files because that graph does not include `package:test`. Its original failure evidence is retained separately. This successful run uses the unchanged test declarations of the package that owns these suites. It establishes these engine behaviors; broader application and platform acceptance have separate evidence.

No root Flutter test, full web build, CI query or CI wait was performed for this qualification.
