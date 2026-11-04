# pdf_operations

Typed PDF workflows for a Flutter host, a web application, and a standalone
Dart CLI. The package is Apache-2.0 and uses the pure-Dart `pdf_document` and
`pdf_graphics` engines. It has no Flutter, `dart:ui`, `dart:io`, network, file
picker, credential-store, or persistence dependency.

## Operations

| Method | Result |
| --- | --- |
| `inspect` | Page sizes/rotations, encryption/signature/XFA flags, named form schema |
| `text`, `search` | Existing searchable text and page-space match bounds |
| `merge` | Ordered inputs and optional per-input page selections |
| `extract` | A fresh PDF containing the selected pages in the requested order |
| `reorder`, `deletePages`, `rotate` | Page organization |
| `insertImage` | PNG/JPEG placement on selected pages |
| `watermark` | Foreground text or logo on all/selected pages, opacity and rotation |
| `fillForm` | Strict typed values for known AcroForm field names |
| `applyOcr` | Invisible searchable text from externally recognized page spans |
| `recognize` | Host-supplied `PdfRecognitionBackend` followed by `applyOcr` |

The service is synchronous except for the optional asynchronous OCR backend.
Run larger jobs in a worker/isolate appropriate for the host. Byte-size and
page limits constrain inputs and outputs, but are not a bound on peak parser,
font, image-decoding, or serialization memory.

## Shared API

```dart
import 'package:pdf_operations/pdf_operations.dart';

const service = PdfOperationsService();
final source = PdfInput(sourceBytes, name: 'report.pdf', password: password);

final information = service.inspect(source);
final rotated = service.rotate(source, pages: '2-4,7', degrees: 90);
final extracted = service.extract(source, pages: '7,2-4');
final merged = service.merge([
  PdfMergeInput(source, pages: '1-3'),
  PdfMergeInput(PdfInput(appendixBytes), pages: 'all'),
]);
final marked = service.watermark(source,
  watermark: const PdfWatermarkOptions(
    text: 'DRAFT', opacity: .2, angleDegrees: -35,
  ),
);
final filled = service.fillForm(source, values: {
  'customer.name': 'Anna Müller',
  'terms.accepted': true,
  'delivery': 'Express',
  'interests': ['Books', 'Music'],
});
// The host previews/reviews warnings and decides where to save filled.bytes.
```

Every mutation returns `PdfOperationResult`: an immutable byte snapshot,
page count, warnings, and (for filling) names of applied fields. Its `toJson()`
returns metadata without PDF bytes, field values, or document passwords.
`PdfInput` owns an immutable copy of its bytes. Reuse it across previews.

`PdfPageRange.parse('4-2,1', 4)` returns `[3, 2, 1, 0]`. Ranges are inclusive
and one-based; `all` selects every page. Input order is retained. Empty
components, invalid/out-of-bounds numbers, and repeated pages are rejected.
Reordering requires every page exactly once; extraction accepts a subset.
Typed model `pageIndex` values are zero-based; JSON additionally includes a
one-based `page` number.

## Forms and authored Unicode

`inspect(source).fields` reports full field names, types, on-state names,
choice export/display pairs, page indices, read-only/required/password flags,
multi-select support, and maximum text lengths. Password values are excluded
even when the source already stores them.

`fillForm` accepts strings for text/radio/single choices, booleans for
checkboxes, and arrays of strings for multi-select lists. It validates the
entire map before modifying its private document. Unknown or ambiguous names,
wrong types/options, invalid text, excessive lengths, read-only/password/
signature/push-button fields, and unsupported field scripts reject the whole
request. Checkboxes are set deterministically; repeat filling does not toggle
them. Recognized Acrobat text validation/normalization and calculation helpers
run; arbitrary JavaScript does not. Filling a known field is not automatic
visual form detection or authoring of missing fields.

For text outside the Latin-1 appearance path, pass a covering font:

```dart
final font = PdfEmbeddedFont.parse(ttfOrOtfBytes);
final filled = service.fillForm(source,
  values: {'customer.name': 'Жук'}, appearanceFont: font);
final marked = service.watermark(source,
  watermark: PdfWatermarkOptions(text: 'Αθήνα', font: font));
```

An existing embedded form font may also be reused. Unrecoverable/custom simple
font encodings require an explicit covering appearance font: the same byte can
mean a different glyph in a subset font. Missing glyphs are errors, not silent
replacement spaces. A font's coverage is not a full shaping
engine: Arabic, Indic, and some other scripts require additional layout work;
the service reports a warning for those visible text paths. Verify their
appearance in a representative viewer before using the result.

## Geometry and watermarks

Watermarks are foreground overlays. They fit the displayed crop area of each
page, including 90/180/270-degree rotations, nonzero crop origins, and mixed
page sizes. `widthFraction` limits their initial width; `margin` is in points.
The nine `PdfPlacementAnchor` values select a corner, edge-center, or center.
`angleDegrees` is clockwise on the displayed page. Text size can shrink to
fit the rotated box. PNG/JPEG watermarks keep the source image aspect ratio.

`PdfImagePlacement` uses fractions of the displayed crop area, with the origin
at its top-left. Omitting `height` preserves the source image aspect ratio.
An explicitly supplied height uses that box, including deliberate stretching.
Rotated images that extend outside the crop box report a clipping warning.

With `flatten: true` (default), only the newly added mark is baked into page
content. Existing form fields and comments remain interactive. `flatten: false`
leaves an editable FreeText/Stamp annotation. Neither mode is a secure
watermark removal deterrent, a document signature, or redaction.

## Encryption, extraction, and history

Mutating a complete PDF keeps its encryption. Merge uses the first whole input
as its base: later sources use that base's password/encryption and metadata.
If the first input is a subset, it is extracted into a new PDF first.
Extraction produces unencrypted output. Extracting an encrypted input, or
merging an encrypted source into an unencrypted result, therefore requires
explicit `allowDecryption: true`. A wrong password and missing password have
separate `PdfOperationException.code` values.

Imported pages retain their content/resources/annotations and supported form,
bookmark, destination, and layer data. Colliding form/destination names are
renamed. Links to pages omitted from a selection may be removed. The first
complete source supplies the catalog; attachments and JavaScript from later
sources are not merged. Extraction does not carry attachments or arbitrary
document JavaScript, and a source signature does not certify the result.
XFA editing is refused.

Page deletion changes the live page tree. Incremental save leaves historical
bytes in the output, so deleted pages can be recoverable. These operations
do not provide secure erasure or redaction. Hosts should retain signed source
files separately and save modifications as new files.

## OCR interchange

The package does not include a recognition model, rasterizer, or network client.
Import recognition from a chosen OCR backend using this JSON shape:

```json
[
  {
    "page": 1,
    "spans": [
      {"text": "Example", "bounds": [72, 700, 130, 718], "confidence": 0.98}
    ]
  }
]
```

`PdfOcrPage.fromJson` converts each page entry. Coordinates are PDF points
`[left, bottom, right, top]`, not raster pixels. The host/backend must transform
its pixel boxes into the source PDF's space. `applyOcr` skips pages that already
have text by default, validates page/bounds/confidence values, and writes
invisible text. Non-Latin text requires a covering embedded font. Recognition
quality remains the backend's responsibility. `PdfRecognitionBackend` lets a
host supply local or remote recognition explicitly; the service never contacts
a backend unless the caller provides one.

## Verification

```sh
cd packages/pdf_operations
dart test
dart run tool/emit_validation.dart /path/to/output
```

The tests cover ordered page selection, preservation of form functionality,
strict batch validation, encrypted merge/extraction policy, Unicode appearance
text, selective watermark flattening, rotated/cropped geometry, image placement,
and externally supplied OCR. The emitter writes generated PDFs and a metadata
manifest for independent-parser and visual checks. Fonts used by tests have
their own notices in `test/fonts/`.
