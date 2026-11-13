# Independent nonempty WPF ISF oracle

The six controls in [`test/fixtures/ink_wpf`](../../../test/fixtures/ink_wpf)
were authored, serialized, decoded and rendered by actual Windows WPF
`System.Windows.Ink.StrokeCollection`. They establish independent valid
nonempty ISF inputs and decoded geometry/paint observations for subsequent
portable-parser work. This checkpoint does not modify the production parser,
model or document writer.

## Exact execution and retained inputs

| Identity | Recorded value |
| --- | --- |
| Successful helper commit | [`5da4906ac8ccc76583329af23467e135dd3698a9`](https://github.com/CrispStrobe/legacy-doc-parser/commit/5da4906ac8ccc76583329af23467e135dd3698a9) |
| Helper tree | `4ccb56b1de7e0b49e391afb8a038d89edbdadc37` |
| Windows workflow | [run 43382035366](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43382035366), job `131741781381`, all steps successful |
| SDK/runtime | .NET SDK `8.0.428`; actual process `.NET 8.0.34` |
| Windows | Server 2025 runner, runtime reports `Microsoft Windows 10.0.26100`, x64 |
| Actual WPF assembly | `8.0.34-servicing.26522.17+c45b7b239ce0d0b210c0c7b48862804f4a038c78` |
| WPF assembly SHA-256 | `cc1664768c1852d209f7c1121285c5bcc94262f9e60e38860d0143f8e28c0d11` |
| Downloaded artifact | `14016459874`, 70,184 bytes, 96 members |
| Artifact SHA-256 | `098ea413a50f21a686eb6ad75150658ea93cc6138d66d612e8972abfe8c54539` |
| Published fixture checkpoint | [`fab015718528b6fb4560bfd777474cf171e730ff`](https://github.com/CrispStrobe/legacy-doc-parser/commit/fab015718528b6fb4560bfd777474cf171e730ff) |

The workflow checked out the exact helper commit and recorded a clean tree
before building. `provenance.json` retains the GitHub run, job, step and
artifact responses; `successful-job.log` preserves the returned job log.
`successful-run.zip` is the original download, whose bytes were checked
against the GitHub artifact digest before extraction. Its 92 oracle files
are copied without modification into the fixture directory. The other four
members are the original build, runtime, checkout-status and execution logs.

The fixture directory contains **24 nonempty ISF files**, **30 PNGs** and
**38 JSON records**, totaling **154,603 bytes**. The ISFs themselves occupy
only **1,550 bytes**. Twelve are initial WPF saves; twelve are their second
saves after WPF reload. The manifest inventories the other 91 files, totaling
138,204 bytes; the additional 16,399 bytes are the manifest itself. Scoped
Git attributes preserve the original Windows JSON line endings as exact bytes.

The source was authored independently for this test. No Dart parser, custom
ISF encoder, Office file, external artwork, font or user document contributes
the controls. The five helper/workflow sources are retained under `source/`
and can be checked against the successful Git commit.

## Observed behavior

Authored positions and pen dimensions are in Himetric (1/100 millimeter),
converted to WPF device-independent pixels using `96/2540`. Every case uses
`FitToCurve=false`, identity tip transform and ordinary ink (not highlighter).
Original objects, first reloads and second reloads are all retained.
The two compression modes have the same decoded observations and rendered
pixels for each case, although four cases have different serialized bytes.

| Control | Authored content | First ISF bytes, uncompressed / compressed | First reload observation |
| --- | --- | --- | --- |
| `polyline-solid` | Five black polyline points, 53-Himetric circular pen | 48 / 47 | Coordinates, pressure, attributes and pixels unchanged |
| `single-dot` | One blue point, 212-Himetric circular pen | 42 / 42 | Visible dot; coordinates, attributes and pixels unchanged |
| `paint-ellipse-alpha` | Three points, `#804080D0`, 212 × 106-Himetric ellipse | 49 / 47 | Alpha color, asymmetric tip, coordinates and pixels unchanged |
| `multiple-strokes` | Three separate red/green/blue strokes; green rectangular tip | 129 / 129 | Stroke order, separate paint, geometry and pixels unchanged |
| `pressure-ramp` | Five points with pressures 0, 0.125, 0.5, 0.875 and 1 | 66 / 62 | Pressure normalization changes 39 pixels; coordinates and drawing attributes unchanged |
| `signed-quantization` | Signed fractional and half-Himetric coordinates; 79.5-Himetric pen | 57 / 57 | Maximum coordinate normalization 0.5 Himetric; 73 pixels changed; drawing attributes unchanged |

The pressure metric is 0–1023. WPF retains the original integer packet values
`0, 127, 511, 895, 1023`, but the reloaded floating pressure factors are
`0, 0.12414467, 0.49951124, 0.8748778, 1`. The maximum recorded pressure-factor
difference is `0.0008553266525268555`. The original and reloaded values remain
separate; the original authoring values have not been rewritten as a golden.

The signed case reloads authored Himetric points
`(-635.49,-317.5), (-0.5,0.5), (635.49,317.5), (1270.5,635.5)` as
`(-635,-318), (0,0), (635,318), (1270,636)`. This measures the chosen boundaries;
it is not a universal rounding assertion for every ISF producer. Its maximum
DIP difference is approximately `0.018897637795277`. The 79.5-Himetric pen
width and height remain exact in the recorded WPF attributes.

Every second save is byte-identical to its corresponding first ISF. Every
second reload has unchanged decoded observations and zero changed pixels
relative to the first reload. The first four controls also match their
original object at every stage; the pressure and signed-coordinate changes
remain explicitly visible.

## Rendering and scope

WPF draws strokes onto an opaque white 256 × 192 image at 96 DPI with a fixed
32-DIP translation. The process requests software rendering. Each receipt
keeps the encoded PNG hash, raw BGRA pixel hash, nonwhite pixel count and
bounds. All measured ink is visible and lies strictly inside the viewport.
The Python verifier decodes the actual bounded PNG bytes, checks chunk CRCs
and reconstructs BGRA pixels to recalculate those hashes and changed-pixel
counts. It does not replace WPF with another ink renderer.

These are WPF ISF encode/decode and WPF ink-render observations. They do not
establish Microsoft Word rendering, OfficeArt ink placement, document editing,
handwriting recognition or arbitrary ISF extension support. A portable
implementation must reject or explicitly report unsupported content instead
of silently treating these six cases as proof of complete ISF support.

The separately inspected WPF reference source is commit
[`e7acf467c05e51901b17684b1f2c330e7dc5fc4d`](https://github.com/dotnet/wpf/tree/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/MS/internal/Ink/InkSerializedFormat).
That source reference is not substituted for the actual runtime assembly
identity recorded above. Public API references and the reproduction command
are in [`tool/ink_oracle/README.md`](../../../tool/ink_oracle/README.md).
The [StylusTip API](https://learn.microsoft.com/en-us/dotnet/api/system.windows.ink.stylustip)
identifies rectangle as 0 and ellipse as 1; the authored JSON retains those
actual enum values and the decoded snapshots also include readable names.

## Verification and the first build attempt

```sh
python3 doc/evidence/wpf-isf-oracle-20261113/verify.py --check-git .
python3 -O doc/evidence/wpf-isf-oracle-20261113/verify.py --check-git .
python3 doc/evidence/wpf-isf-oracle-20261113/test_verifier.py
python3 -O doc/evidence/wpf-isf-oracle-20261113/test_verifier.py
```

The verifier binds the downloaded ZIP to the successful GitHub identity and
digest, exact fixture copies, original per-file manifest, authored inputs,
decoded counts/units/attributes, ISF bytes, coordinate and pressure differences,
and decoded PNG pixels. `receipt.json` inventories the retained evidence
files, including the verifier sources. Checks remain active under optimized
Python. Ten semantic corruption controls reject wrong source identity,
missing ISF, forged coordinate or pixel differences, stale geometry or pixel
hashes, changed authored paint, false compression/roundtrip claims and altered
pressure normalization after the inner manifest hashes are resealed.

The initial helper commit `4f548588` failed to compile in
[run 43381529727](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43381529727)
because the WPF SDK does not implicitly import `System.IO`. The follow-up
added that explicit import. `first-run.zip`, `first-job.log` and
`first-jobs.json` preserve the original failure; the 2,191-byte ZIP matches
GitHub SHA-256 `1dad60c3499b57ff43cd690eba55f9ae6124abd783a97efc3db7d4c793b9f1b1`.
It contains no ink fixture and is not labeled successful acceptance. The
successful run did execute the unchanged six authored controls.
