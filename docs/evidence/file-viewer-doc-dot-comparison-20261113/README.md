# Binary Word differential probe

This receipt supports [the DOC/DOT comparison](../../file-viewer-doc-dot-comparison.md). It measures parser results and generated HTML for 19 selected, unchanged fixtures. It does **not** run a browser, Flutter, Microsoft Word, LibreOffice, screenshots, or DOCX round trips.

## Results and identities

- File Viewer: `d264009ca6efb3daed79a39d1ae63133e0f25558`; 19 parser/HTML results.
- CrispCloud reference: `9b9af856d4352c0d9d8d51aaffcd70aeb7ff3aad`; local `packages/legacy_doc_parser` tree `704da2021d56a963cbba46a095900d97d2b02ec3`; 16 parser/HTML results and three explicit format rejections.
- Eight of sixteen mutually accepted cases have equal normalized generated preview text.
- Upstream `final`/`original` revision projections match the independently saved accepted/rejected binary references after the same text normalization.
- Runtime: Node 24.22.1; Dart 3.13.7 native executable; TypeScript 6.0.3. The compiler tarball was extracted without install scripts and verified against registry integrity metadata; its identity is in `compiler-evidence.json`.

`results.json` contains input paths and SHA-256 values, compact structure counts, warnings/errors, output text hashes and lengths. It deliberately omits the fixture text, HTML, and timing measurements. `source-hashes.json` identifies the inspected native library and upstream DOC/Word source files. These results are a diagnostic selection, not a representative success rate or a visual-fidelity score.

The native package was resolved through the app's local dependency override. The app also declares standalone Git ref `fee9b84bdca8ae25a1839f7ef29690150115abe7`; that declaration does not replace the local tree identity above.

## Reproduction

Use sibling `CrispCloud` and `file-viewer` checkouts at the source identities above. A newer app checkout can be used only if its parser source and fixtures still match the hashes. Resolve the app's normal dependencies first; this probe does not modify or install app dependencies. Use the specified compiler versions, or record any toolchain change separately.

Create a disposable build/output directory outside the repository. `TSC` below is the path to the extracted TypeScript 6.0.3 `lib/tsc.js`; `DART` and `NODE` identify genuine executables. The TypeScript build is the original parser/HTML subset, with no runtime-source patch or stub.

```bash
WORKSPACE=/path/to/sibling/checkouts
PROBE_BUILD=/path/to/disposable/doc-probe
TSC=/path/to/typescript-6.0.3/lib/tsc.js
DART=/path/to/dart
NODE=/path/to/node
HARNESS="$WORKSPACE/CrispCloud/docs/evidence/file-viewer-doc-dot-comparison-20261113"
mkdir -p "$PROBE_BUILD/upstream" "$PROBE_BUILD/tmp"
cp "$HARNESS/upstream_probe.mjs" "$PROBE_BUILD/upstream_probe.mjs"
cd "$WORKSPACE/file-viewer"
"$NODE" "$TSC" --ignoreConfig --target ES2022 --module NodeNext \
  --moduleResolution NodeNext --lib ES2022,DOM --skipLibCheck --strict \
  --outDir "$PROBE_BUILD/upstream" --rootDir packages/renderers/doc/src \
  packages/renderers/doc/src/msdoc/parser.ts packages/renderers/doc/src/render/html.ts
python -c 'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("{\"type\":\"module\"}\n")' \
  "$PROBE_BUILD/upstream/package.json"
TMPDIR="$PROBE_BUILD/tmp" "$DART" compile exe \
  --packages="$WORKSPACE/CrispCloud/.dart_tool/package_config.json" \
  "$HARNESS/native_probe.dart" -o "$PROBE_BUILD/native_probe"
python "$HARNESS/run_probe.py" --workspace "$WORKSPACE" \
  --build "$PROBE_BUILD" --output "$PROBE_BUILD/output" --node "$NODE"
```

The runner verifies all retained source and fixture hashes, executes no more than two cases concurrently, gives each parser subprocess a 20-second timeout, and checks each fixture's bytes again after execution. Its scratch `raw/` output contains document text/HTML for local investigation and should not be committed. The checked-in result is the content-reduced receipt only. Input fixtures remain in their original repositories with their original license/provenance files; this directory does not redistribute those binary documents.

HTML text normalization decodes character references, introduces whitespace at selected block/table/break boundaries, and collapses whitespace. It intentionally loses typography and spacing distinctions. Image/table counts are HTML-element counts, not rendered correctness. Per-story text lengths are separately measured and need not add to normalized HTML lengths.

The report's existing native test/native-render counts are citations to older retained receipts. This probe does not claim to rerun those suites.
