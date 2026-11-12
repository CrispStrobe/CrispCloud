# Independent vector controls

These small controls are authored for this project under MPL-2.0. Their
generator uses raw MS-EMF/MS-WMF records and hand-authored OPC/WordprocessingML;
it imports neither the parser/converter nor their binary-test builders.

| Input | Records | Native asset | Features |
| --- | ---: | ---: | --- |
| `emf-vectors.docx` | 21 including header/EOF | `emf-vectors.emf`, 540 bytes | Rectangle, ellipse, cubic Beziers, affine triangle, signed anisotropic window mapping, solid pen/brush, saved contexts |
| `wmf-vectors.docx` | 17 including EOF | `wmf-vectors.wmf`, 230 bytes | Rectangle, ellipse, polygon, line, explicit initial mapping, signed window origin, solid objects, placeable-header checksum |

Both images have a 600 × 360 coordinate canvas and an independently specified
6 × 3.6 inch inline extent. They contain no text/font commands, scripts,
external resources or escape records. Every package has one native vector
image. The surrounding text makes PDF text/layout measurements possible.

Regenerate exactly from the repository root:

```sh
dart run tool/fidelity/metafile_cases.dart
```

`test/metafile_corpus_test.dart` checks committed raw bytes against the
independent authoring functions and confirms that each DOCX embeds that exact
asset. The cross-renderer corpus can separately compare the original DOCX,
native DOC bridge, native DOCX reference and this package's output.

An installed LibreOffice acceptance run imported/exported both controls.
The binary DOC retained the exact EMF and removed the WMF's 22-byte placeable
header (leaving 208 bytes). The parser recovered both resulting payloads and generated a complete
bounded SVG for each. That observed bridge change is not an extraction loss.
