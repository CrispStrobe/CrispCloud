# Bounded ISF stroke inspection

`LegacyWordOfficeArtInk.decoding` and `decodeLegacyWordInk` inspect supported
nonempty Ink Serialized Format streams. They expose immutable ordered stroke
and point collections, RGB/alpha, pen dimensions, tip shape, drawing flags and
normal-pressure packets. Original ISF bytes remain unchanged. Coordinates and
dimensions use HIMETRIC (1/100 millimeter), independently of the Word shape's
placement. Points expose original integer `packetX`/`packetY` as well as the
transformed `xHimetric`/`yHimetric`; each stroke retains its selected immutable
transform and pressure metric.

The implementation validates the complete stream before returning strokes.
Unsupported records, encodings, transforms or properties return an explicit
`unsupported` result with no partial stroke list; malformed structure returns
`invalid`. Resource ceilings return `limitExceeded`. The existing header-only
status stays separate. Matching a version/extent is not sufficient to claim a
complete stroke decode.

## Supported subset

- Version-zero ISF framing with exact byte extents and bounded unsigned/signed
  variable-length integers.
- X/Y channels and the optional normal-pressure channel with default or explicit
  zero-based unitless pressure ranges at unit resolution. Absent pressure stays
  distinct from explicit samples and has factor 0.5. Explicit pressure retains
  its raw value and is normalized by its selected source maximum.
- Signed Gorilla bit packing and the eight built-in indexed Huffman tables,
  including bounded delta-delta reconstruction.
- Drawing attribute blocks/tables and descriptor selection, ordinary RGB,
  transparency, integer/thousandth pen dimensions, elliptical/rectangular tips,
  drawing flags and supported raster operation values.
- Affine, isotropic/anisotropic scale, compact offset and scale/offset transform
  records (tags 16, 17, 18, 20, 21), tables and stroke selection. Matching
  double-precision extensions retain precision beyond the corresponding float.
- Pressure metric blocks/tables and selection, including compact records that
  omit trailing default fields. Every present field takes effect. Other packet
  metrics, nonzero pressure minima, nonunit resolution, unknown units, rotation
  shorthand and unmatched transform extensions remain inert.

Bounds per ISF are 16 MiB, 100,000 total points, 4,096 strokes, 512 table
entries/properties and 16,384 stream records. Bit decoding uses bounded exact
integer arithmetic on the Dart VM and JavaScript. Unknown extensions are not
silently discarded. Transform coefficients are bounded to magnitude 1,000,000
and transformed coordinates to JavaScript's exact-integer range. Fractional
coordinates retain the source transform's floating-point precision. Repeated or
late transform/metric definitions are unsupported; valid indices select an
already validated table. A decoder result never invents an ink/comment link.

## Aggregate conversion limits

Conversion shares one allowance of 100,000 attempted points and 4,096 attempted
strokes across inline and floating ink. Each stroke reserves its declared point
count before packet arrays are allocated. Work already performed on a payload
that later proves malformed or unsupported remains charged. A payload exceeding
the remaining allowance has no partial decoded strokes; its exact ISF bytes
remain inert evidence with `strokeDecodeStatus: limitExceeded` and an explicit
aggregate-limit reason.

Repeated references to the same immutable ink model reuse one conversion
inspection. Conversion inspects source bytes under its own allowance, independent
of the model's standalone cached `decoding` result, so caller-predecoded models
cannot bypass the limit. Conversely, an exhausted conversion does not change a
later standalone inspection. Callers inspecting multiple payloads directly can
pass one `LegacyWordInkDecodeBudget` to successive `decodeLegacyWordInk` calls;
its nonnegative point/stroke limits may be lower than, but cannot exceed, the
per-stream ceilings. Failed work remains charged to that shared budget too.

`inkPayloads`, `decodedInkPayloads` and `decodedInkStrokes` count preserved
occurrences. Repeated references therefore contribute to those counters even
when their decode work is shared. They are distinct from the aggregate work
allowance and do not certify Word placement or rendering. The binary regression
in `test/legacy_word_ink_budget_test.dart` and the VM/compiled-JavaScript
acceptance in `tool/ink_web_acceptance.dart` check limited and retained payloads
independently of the native WPF evidence below.

## Independent oracle and limits

The test fixtures were written and reloaded by actual Windows WPF
`System.Windows.Ink.StrokeCollection` on .NET 8.0.34. Six authored cases cover
polylines, dots, opacity, unequal pen dimensions, multiple strokes, rectangular
tips, pressure and signed coordinate quantization. Both compression modes and
both save cycles provide 24 actual ISF inputs. Tests compare every point,
pressure value and supported drawing attribute with WPF's independently
decoded JSON, retaining WPF's own quantization rather than comparing against
unserialized input floats.

A second independent Windows run applies 16 controlled headers to those exact
WPF packet bodies, preserving both inputs and native round trips (32 ISFs).
Native point, pen and pressure observations agree for the qualified transforms
and full pressure metrics. Two distinctions are explicit in the tests:

- ISF's compact tag 20 specifies a **zero linear matrix**, so all points become
  its offset. Ordinary translation uses tag 16 with identity linear coefficients.
  The original pre-execution conventional-translation hypothesis is retained in
  the oracle evidence, alongside the specification and native result.
- WPF saves the 0..2047 pressure range as compact bytes `19 05 38 03 00 fe 1f`,
  then reloads its maximum as 1023. The ISF Metric Block definition says only
  omitted fields inherit defaults. This decoder therefore preserves 2047 in
  both forms. The unchanged native JSON and its measured rendering difference
  remain in the evidence; tests explicitly verify the specification departure.

Table switching, affine cross terms, finer double precision, partial metric
prefixes and malformed/resource-bound controls also have authored byte-level
tests. These supplement the recorded Windows cases; they do not imply native
rendering coverage for every possible transform or tablet configuration.

This is stroke inspection, not a Word rendering or editing certificate. The
converter preserves raw payloads, source occurrence/flags and decode status,
counts fully decoded nonempty payloads/strokes, and still emits no active
`o:ink`. General tablet metrics, remaining transform forms, custom properties, native
OfficeArt placement, pressure-sensitive outline rendering and full ink/comment
association require further independent controls. No guessed stroke image or
shape placement substitutes for the source.

## Primary implementation references

- [Microsoft ISF specification](https://download.microsoft.com/download/0/B/E/0BE8BDD7-E5E8-422A-ABFD-4342ED7AD886/InkSerializedFormat(ISF)Specification.pdf).
- [Microsoft specification preserved by the Library of Congress](https://www.loc.gov/preservation/digital/formats/digformatspecs/InkSerializedFormat(ISF)Specification.pdf), printed pages 12–14 and 31: transform definitions and metric-prefix inheritance.
- [.NET WPF ISF implementation at e7acf467](https://github.com/dotnet/wpf/tree/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/MS/internal/Ink/InkSerializedFormat): `InkSerializer`, `StrokeSerializer`, `DrawingAttributeSerializer`, `AlgoModule`, `GorillaCodec`, `HuffCodec`, `Codec` and `ISFTagAndGuidCache`.
- [WPF DrawingAttributes defaults](https://github.com/dotnet/wpf/blob/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/System/Windows/Ink/DrawingAttributes.cs).

The WPF reference algorithms and Huffman table constants are MIT-licensed by
the .NET Foundation and contributors. The original license is retained in
`third_party/wpf-isf/LICENSE.txt`; this bounded implementation is part of the
MPL-2.0 parser. The oracle records its actual installed WPF assembly separately
from the reference source revision, so those identities are not conflated.
