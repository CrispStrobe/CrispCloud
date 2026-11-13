# Independent WPF transform and pressure-metric controls

**Measured interpretation update:** the
[retained Windows results](../../doc/evidence/wpf-isf-metrics-20261113/README.md)
show that compact tag 20 collapses the points to its offset. The subsequently
checked Microsoft 2007 ISF specification explicitly gives that tag zero linear
matrix coefficients, consistent with WPF. The conventional translation in the
table below is the unchanged pre-run hypothesis, not the specification's tag-20
contract. Full affine tag 16 is the demonstrated encoding for a conventional
translation. The original helper README bytes are retained with the measured
source receipt; this interpretation note does not rewrite the experiment.

This isolated author/runner keeps the existing Windows WPF oracle and every
original fixture byte unchanged. It modifies only documented ISF transform
records, pressure-metric records and their enclosing lengths in two exact
retained uncompressed WPF files. It contains no production parser reference
and does not encode, recompress or replace a stroke packet.

`author_controls.py` requires the original SHA-256 hashes, checks the exact
source record inventory and retains every before/after byte in
`controls.json`. Each case also inventories record offsets, hashes, lengths
and the identical drawing-attribute, stroke-descriptor and stroke records.
The author writes its source-formula predictions before WPF runs. A WPF
disagreement is a recorded result and never changes those predictions.

## Sixteen deliberately separated controls

The two unchanged baselines are `polyline-solid` and `pressure-ramp` from
[`test/fixtures/ink_wpf`](../../test/fixtures/ink_wpf), originally produced by
the successful WPF helper commit `5da4906ac8ccc76583329af23467e135dd3698a9`.
The new branch starts at the complete independent-oracle checkpoint
`db1e2755a2a4ac98bf2df1e84e86d3c6f1716415`.

| Source control | ISF tag | Coefficients | Intended Himetric mapping |
| --- | --- | --- | --- |
| Isotropic scale | 17 | `2` | `(2x, 2y)` |
| Anisotropic scale | 18 | `2, 0.5` | `(2x, 0.5y)` |
| Compact translation | 20 | `100, -50` | `(x+100, y-50)` |
| Full affine translation | 16 | `1, 0, 0, 1, 100, -50` | `(x+100, y-50)` |
| Scale and translation | 21 | `2, 0.5, 100, -50` | `(2x+100, 0.5y-50)` |
| Full affine scale and translation | 16 | `2, 0, 0, 0.5, 100, -50` | `(2x+100, 0.5y-50)` |

Each transform has a float-only form and a form with a matching
`ExtendedTransformTable` (tag 31) of little-endian doubles. The source
identity transform and its extended identity are replaced together; the
float-only control explicitly removes the old extended identity. Coordinates
are converted from Himetric to DIP with exactly `96/2540` after the matrix.

Two additional controls insert a complete NormalPressure metric entry in
`MetricBlock` (tag 25), immediately before the unchanged pressure stroke:
explicit default `0..1023` and nondefault `0..2047`, unit `None`, resolution
1. The unchanged pressure baseline has the implicit default metric. The
property tag is 56 (known GUID base 50 plus NormalPressure index 6). Metric
payloads are signed minimum, signed maximum, unsigned unit, and little-endian
float resolution; signed integers use magnitude shifted left and the low sign
bit. The raw pressure packets stay `0, 127, 511, 895, 1023`. Both raw values and
WPF's observed pressure factors/property values remain in the records.

The inspected WPF source initializes all six matrix coefficients to zero
and only sets the offsets for compact tag 20. The full affine translation
control distinguishes that behavior from the intended translation formula.
This is a reason to measure the installed WPF runtime; it is not a rewritten
expectation or a claim that the installed assembly necessarily behaves the
same way.

## Actual native execution

`InkMetricsOracle.csproj` compiles the original `tool/ink_oracle/Program.cs`
unchanged and reuses its snapshot, load, save and difference methods by
reflection. The new runner uses a 512 × 256 white canvas, with the same
96-DPI, 32-DIP translation and software-rendering preference, so scaling the
full original polyline by two remains unclipped. This larger renderer repeats
the original rendering operations without transforming the decoded strokes.

Each control is loaded by actual Windows WPF, snapshotted and rendered,
saved uncompressed, loaded again, snapshotted and rendered again. Every
serialization, coordinate, pressure and pixel difference is retained. Source
formula disagreement does not fail the run; malformed inputs, missing
strokes, nonfinite points, invisible/clipped rasters or changed source objects
do. No Microsoft Word, OfficeArt placement, portable-decoder correctness or
arbitrary ISF support is asserted by this runner.

```powershell
cd tool/ink_metrics_oracle
python author_controls.py ../../build/ink-metrics-input (git rev-parse HEAD)
dotnet build InkMetricsOracle.csproj --configuration Release --output ../../build/ink-metrics-bin --property:BaseIntermediateOutputPath=../../build/ink-metrics-obj/
../../build/ink-metrics-bin/InkMetricsOracle.exe ../../build/ink-metrics-input ../../build/ink-metrics (git rev-parse HEAD)
```

The scoped `ink-metrics-oracle.yml` workflow runs only for changes to this
helper/workflow on `checkpoint/ink-metrics-oracle-20261113`, or explicit
dispatch. It records clean source/tree identities, SDK/runtime and actual
WPF assembly identity, and uploads original input inventories, native
outputs and execution logs even on failure. The first helper checkpoint is
saved remotely before any native execution is accepted as evidence.

## Primary source contract

The inspected source revision is
[`dotnet/wpf` at `e7acf467c05e51901b17684b1f2c330e7dc5fc4d`](https://github.com/dotnet/wpf/tree/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/MS/internal/Ink/InkSerializedFormat).
`ISFTagAndGuidCache.cs` defines the tags/property identity;
`InkSerializer.cs` (`DecodeTransformBlock`, `DecodeTransformTable`,
`LoadTransform`, `DecodeMetricBlock`, `GetStylusPointPropertyInfo`) defines the
record payloads and native interpretation; `SerializationHelper.cs` defines
the integer encodings. This inspected source identity stays distinct from the
installed WPF assembly recorded by the actual Windows process.
