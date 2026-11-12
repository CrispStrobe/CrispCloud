# Ebook application validation — 2026-11-12

## Verified source

- App implementation: `ba8e510073c13bedb640804ea6cd942ed00325c6`.
- Final app regression checkout: `f1fc39bd4aab5568a090e84a08a3a4263327b464`;
  only documentation changed after the implementation commit.
- All four shared packages resolve to crisperbooks
  `b5b698ba872cc4a11b0b88f0fae2dc5324faf3c5`.
- Reviewed Git tree: `58b4b20ed06da5677880086f714e0ab17d77c3a9`.
- Source manifest SHA-256:
  `de8dd1ebcde63a31136ba11bd3fbb674d6ad39614ebc7aad1f8e6b6ada157815`.

## Completed gates

| Gate | Result |
| --- | --- |
| Resolved dependency provenance | All **276 files** match the committed Git identities, lengths and SHA-256 hashes; checked before and after the release build and after final app tests |
| Provenance failure paths | **22 tests pass**, including lock/revision mismatch, changed bytes, omitted files, URI redirects, symlinks, traversal, duplicate JSON and ignored/untracked runtime files |
| Final app regression suite | **158 tests pass across 14 files**: editor dialog 23, portable chapter reader 13, remaining 12 files 122; all processes exit 0 |
| Native asset integration | Final pinned Kindling native build hook succeeds; app tests run with the real compiled native asset |
| Actual app web release | `flutter build web --release --no-pub --no-wasm-dry-run` succeeds in **212.3 seconds** |
| Delivered converter bundle | All **13 assets/notices** match the source manifest; all **12 relative module/Wasm references** resolve inside the output bundle |

The delivered bundle includes `conversion_worker.js`, `conversion_runtime.js`,
`kindling_conversion.wasm.gz`, the metadata engine and worker, all five WASI
shim JavaScript modules, `LICENSE-MIT`, and `THIRD_PARTY_LICENSES.txt`. The
compressed converter expands to a valid **4,780,479-byte** Wasm module. The
compiled application references the expected worker URL at
`assets/packages/crisp_ebook_conversion/assets/conversion_worker.js`; both the
separate shim license and its aggregated `browser_wasi_shim 0.4.2` notice ship.

The first concurrent final-pin app attempt has no completion result: output
stopped at +71, and its process session was unavailable after a tool/agent
interruption. Its temporary pubspec hook suffix was checked against the
committed file and removed. The two active widget files then passed in separate
bounded runs (24.3 and 10.0 seconds including startup), and the remaining 122
tests passed in 33.1 seconds. No product changes were needed for these reruns.
The successful bounded runs establish the final 158-test result.

These application gates are separate from native WebKit/WebView input and
platform qualification, which are recorded in the other recovery checkpoints.

## Reproduce the local gates

Use Flutter 3.47.8 / Dart 3.13, Rust and Clang, with system SQLite available to
the existing test wrapper. Set `CI=true BOT=true` for automated Flutter calls.
Run the two widget isolates with a 120-second process deadline each, and the
remaining files with a 180-second deadline; individual tests have 30 seconds.

```sh
export CI=true BOT=true
flutter pub get
python3 tool/verify_ebook_sources.py
python3 -m unittest discover -s tool -p 'test_verify_ebook_sources.py' -v

python3 tool/with_ci_system_sqlite.py \
  timeout --signal=TERM --kill-after=10s 120s \
  flutter test --no-pub --concurrency=1 --timeout=30s --reporter=expanded \
  test/widget/ebook_editor_dialog_test.dart

python3 tool/with_ci_system_sqlite.py \
  timeout --signal=TERM --kill-after=10s 120s \
  flutter test --no-pub --concurrency=1 --timeout=30s --reporter=expanded \
  test/widget/ebook_chapter_reader_test.dart

python3 tool/with_ci_system_sqlite.py \
  timeout --signal=TERM --kill-after=10s 180s \
  flutter test --no-pub --concurrency=1 --timeout=30s --reporter=expanded \
  test/ebook_annotations_test.dart \
  test/ebook_reading_data_test.dart \
  test/ebook_reading_data_files_test.dart \
  test/ebook_library_test.dart \
  test/widget/ebook_library_dialog_test.dart \
  test/widget/ebook_reading_controls_test.dart \
  test/ebook_edit_session_test.dart \
  test/widget/ebook_prose_editor_test.dart \
  test/widget/ebook_kindle_metadata_editor_test.dart \
  test/file_editability_test.dart \
  test/office_document_service_test.dart \
  test/pdf_file_store_test.dart

flutter build web --release --no-pub --no-wasm-dry-run
python3 tool/verify_ebook_sources.py
```

This executor's Rust installation was outside the standard home, so its
documented `crisp_ebook_conversion` hook settings `cargo`, `cargo_home`, and
`rustup_home` were temporarily merged with the SQLite wrapper's settings.
The hooks runner does not inherit arbitrary Rust environment variables. A
scoped compiler wrapper supplied a writable temporary directory, and an
unversioned SQLite loader symlink pointed to the installed system runtime.
The production pubspec was restored byte-for-byte after each completed run;
none of these local toolchain paths is committed to the application.
