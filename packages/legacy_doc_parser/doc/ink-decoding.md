# Bounded ISF stroke inspection

`LegacyWordOfficeArtInk.decoding` and `decodeLegacyWordInk` inspect supported
nonempty Ink Serialized Format streams. They expose immutable ordered stroke
and point collections, RGB/alpha, pen dimensions, tip shape, drawing flags and
normal-pressure packets. Original ISF bytes remain unchanged. Coordinates and
dimensions use HIMETRIC (1/100 millimeter), independently of the Word shape's
placement.

The implementation validates the complete stream before returning strokes.
Unsupported records, encodings, transforms or properties return an explicit
`unsupported` result with no partial stroke list; malformed structure returns
`invalid`. Resource ceilings return `limitExceeded`. The existing header-only
status stays separate. Matching a version/extent is not sufficient to claim a
complete stroke decode.

## Supported subset

- Version-zero ISF framing with exact byte extents and bounded unsigned/signed
  variable-length integers.
- X/Y channels and the optional normal-pressure channel with the default
  0..1023 metric; absent pressure remains distinguishable from explicit samples.
- Signed Gorilla bit packing and the eight built-in indexed Huffman tables,
  including bounded delta-delta reconstruction.
- Drawing attribute blocks/tables and descriptor selection, ordinary RGB,
  transparency, integer/thousandth pen dimensions, elliptical/rectangular tips,
  drawing flags and supported raster operation values.
- Explicit identity scale transforms and their double-precision extension.
  Unsupported transforms and metric overrides remain inert.

Bounds are 16 MiB per ISF, 100,000 total points, 4,096 strokes, 512 table
entries/properties and 16,384 stream records. Bit decoding uses bounded exact
integer arithmetic on the Dart VM and JavaScript. Unknown extensions are not
silently discarded. A decoder result never invents an ink/comment link.

## Independent oracle and limits

The test fixtures were written and reloaded by actual Windows WPF
`System.Windows.Ink.StrokeCollection` on .NET 8.0.34. Six authored cases cover
polylines, dots, opacity, unequal pen dimensions, multiple strokes, rectangular
tips, pressure and signed coordinate quantization. Both compression modes and
both save cycles provide 24 actual ISF inputs. Tests compare every point,
pressure value and supported drawing attribute with WPF's independently
decoded JSON, retaining WPF's own quantization rather than comparing against
unserialized input floats.

This is stroke inspection, not a Word rendering or editing certificate. The
converter preserves raw payloads, source occurrence/flags and decode status,
counts fully decoded nonempty payloads/strokes, and still emits no active
`o:ink`. General tablet metrics, transforms, custom properties, native
OfficeArt placement, pressure-sensitive outline rendering and full ink/comment
association require further independent controls. No guessed stroke image or
shape placement substitutes for the source.

## Primary implementation references

- [Microsoft ISF specification](https://download.microsoft.com/download/0/B/E/0BE8BDD7-E5E8-422A-ABFD-4342ED7AD886/InkSerializedFormat(ISF)Specification.pdf).
- [.NET WPF ISF implementation at e7acf467](https://github.com/dotnet/wpf/tree/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/MS/internal/Ink/InkSerializedFormat): `InkSerializer`, `StrokeSerializer`, `DrawingAttributeSerializer`, `AlgoModule`, `GorillaCodec`, `HuffCodec`, `Codec` and `ISFTagAndGuidCache`.
- [WPF DrawingAttributes defaults](https://github.com/dotnet/wpf/blob/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/System/Windows/Ink/DrawingAttributes.cs).

The WPF reference algorithms and Huffman table constants are MIT-licensed by
the .NET Foundation and contributors. The original license is retained in
`third_party/wpf-isf/LICENSE.txt`; this bounded implementation is part of the
MPL-2.0 parser. The oracle records its actual installed WPF assembly separately
from the reference source revision, so those identities are not conflated.
