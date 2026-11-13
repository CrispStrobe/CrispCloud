# File Viewer compatibility follow-up

13 November 2026. This checkpoint merges compatibility implementation
`22f2dafeeb28a5a469cf436d26dca0e0da7a7730` with canonical parser source
`419864b3076cea56f3f4d170a3ace88cfc397027`. The exact tested library bytes are
in [source-hashes.json](source-hashes.json). The canonical source's picture
scaling, Line Number style, textbox geometry, ink decoding, native evidence and
notices are preserved. This is an additional portable compatibility check;
it does not replace the canonical native-layout acceptance program.

## Results

- **1,019/1,019 Dart tests pass**, including 27 newly authored compatibility
  controls. [Actual complete output](dart-tests.log).
- **Full Dart analyzer: no issues found.** [Actual output](dart-analyze.log).
- A fresh run of the same **19 immutable DOC/DOT inputs** accepts **19/19**
  in this parser and **19/19** in File Viewer at
  `d264009ca6efb3daed79a39d1ae63133e0f25558`. Nine cases have equal normalized
  main-preview text. The original comparison accepted 16/19 native cases and
  recorded eight equal-text cases; all three explicit native rejections are
  now covered. [New results](results.json) · [Input identities](fixture-manifest.json).
- The real `template.dot` still has equal normalized main-preview text:
  235 paragraphs, one table, 15 cells and 11,135 normalized characters.

These are selected compatibility and text-projection measurements, **not a
representative success rate or a page/layout-fidelity score**. Both engines
were executed again. File Viewer's source hashes are verified against the
earlier pinned source identity. This run does not execute a browser,
Flutter, Microsoft Word, LibreOffice, screenshot comparison or native DOCX
round trips. The new authored tests do inspect generated DOCX evidence and
confirm that recovered external names do not become resource relationships.

## Three independent recovery rules

| Original failing input | Exact recovered case | Remaining limits and guards |
| --- | --- | --- |
| `image-linked.doc` | Legacy PICF mapping mode 94 with a nonempty, exact length-prefixed external filename. Five paragraphs and two inert picture records now survive. | Header, declared extent, name length, characters and exact scaled dimensions still validate. Original bytes, source CP and unavailable-image notices remain. No resource is opened or fetched, no OfficeArt shape is fabricated, and other mapping modes still reject. |
| `github-34-wps-table.doc` | An old `sprmTSetBrc80` nil diagonal mask is immediately followed by the identical valid modern `sprmTSetBrc` nil border. The redundant invalid old operand is skipped and the valid one is applied. The original input retains 81 paragraphs, 16 rows and 80 cells, with equal normalized text to File Viewer. | Both cell endpoints remain bounded. Only a singleton diagonal mask 0x10 or 0x20, exact nil old/new values, identical range and immediate adjacency qualify. Invalid masks, different values/ranges and missing corroboration still reject. `recoveredLegacyDiagonalBorder` explicitly reports this producer recovery. |
| `github-171-textbox-resume.doc` | Six nonreusable singleton textbox ranges have no matching FSPA anchor. The parser retains all 15 stories and their declared shape identities; recovered references have `placementUnresolved=true` and no anchor. | Text ranges, CR guards, unique recovered shape IDs and ordinary formatting remain validated. Unknown header placements, zero/oversized/multiple-shape chains and duplicate missing-shape references reject. Placement and shape visibility are not asserted. Conversion stores unpositioned text in evidence rather than assigning it to another shape. |

The linked-file source record is identified as `PICFLinkedFileName` and retained
as a `binaryData` artifact. The historical `officeArtArtifactId` API field is
kept for compatibility and documented as a picture-data artifact reference;
it does not claim that a mode-94 record contains OfficeArt.

The textbox recovery does not change the parser's main-only `plainText` and
`safeHtml` contracts. Consumers can display the recovered auxiliary stories
with their role and an unpositioned-content notice. The converter does not
invent layout: original text is present in `word/textboxEvidence*.xml`, and
the evidence manifest retains the declared shape ID and unresolved status.

The MS-DOC definitions remain the strict baseline:
[MFPF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/0e8d24a8-95f9-4435-9fdf-4bb08c66567b),
[ItcFirstLim](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/61341a2c-b8da-4e52-ba62-b2b0d5efadc4),
[TableBrcOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d8a2205c-93cd-4f79-a0be-2656cd6d6fcc),
and [FTXBXS](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d0a81fe8-f9e8-4130-9233-84732e3d9420).
The three exceptions above are disclosed compatibility behavior rather than
a claim that those source encodings satisfy every current specification rule.

## Reproduction

Use this exact source snapshot and a checkout/extraction of the pinned File
Viewer commit. `DART` is Dart 3.13.7, `NODE` is Node 24.22.1, and `TSC` points
to TypeScript 6.0.3's `lib/tsc.js`. Resolve this package's normal dependencies
with `dart pub get` first. The receipt retains the actual
[dependency resolution](resolved-pubspec.lock); the new code adds none.

```bash
PARSER=/path/to/legacy-doc-parser
UPSTREAM=/path/to/file-viewer
PROBE_BUILD=/path/to/disposable/probe
EVIDENCE="$PARSER/doc/evidence/file-viewer-compat-20261113"
mkdir -p "$PROBE_BUILD/upstream"
cp "$EVIDENCE/upstream_probe.mjs" "$PROBE_BUILD/upstream_probe.mjs"
cd "$UPSTREAM"
"$NODE" "$TSC" --ignoreConfig --target ES2022 --module NodeNext \
  --moduleResolution NodeNext --lib ES2022,DOM --skipLibCheck --strict \
  --outDir "$PROBE_BUILD/upstream" --rootDir packages/renderers/doc/src \
  packages/renderers/doc/src/msdoc/parser.ts packages/renderers/doc/src/render/html.ts
python -c 'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("{\"type\":\"module\"}\n")' \
  "$PROBE_BUILD/upstream/package.json"
"$DART" compile exe --packages="$PARSER/.dart_tool/package_config.json" \
  "$EVIDENCE/native_probe.dart" -o "$PROBE_BUILD/native_probe"
python "$EVIDENCE/run_probe.py" --native "$PARSER" --upstream "$UPSTREAM" \
  --build "$PROBE_BUILD" --output "$PROBE_BUILD/results.json" --node "$NODE"
```

The probes originate in CrispCloud's 13 November diagnostic comparison; this
native follow-up also reports concrete media-notice names and unpositioned
textbox counts. The runner verifies input and library source hashes before
and after execution, limits concurrency to two cases and each subprocess to
20 seconds, and stores only structural counts and text hashes. The originals
remain in their source repositories with their original fixture licenses.
No external fixture document or its raw text/HTML is redistributed here.

The 27 independently authored controls are in
[`test/legacy_word_preview_compatibility_test.dart`](../../../test/legacy_word_preview_compatibility_test.dart).
They run offline as part of the normal Dart suite. No fallback disables the
CFB, stream, text, property, image, recursion or output-allocation budgets.
