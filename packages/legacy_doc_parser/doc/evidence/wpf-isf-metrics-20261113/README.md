# Independent Windows WPF transform and pressure-metric observations

Sixteen controls were actually loaded, rendered, saved and loaded again by
Windows WPF. They start from the exact retained uncompressed `polyline-solid`
and `pressure-ramp` ISFs and change only transform/metric records and enclosing
lengths. Every drawing-attribute, stroke-descriptor and stroke-packet byte
stays unchanged in the authored inputs. This evidence does not modify or
evaluate the production parser.

The central findings are **successful initial decoding of the scale, full
affine and pressure-metric controls**, and two distinct interpretation issues:
compact tag 20 follows the specification's zero linear matrix, while WPF's
reload of its own compact pressure metric loses a specified maximum. The
original pre-run predictions and all native results remain separate.

## Exact source and execution

| Identity | Recorded value |
| --- | --- |
| Base independent oracle | `db1e2755a2a4ac98bf2df1e84e86d3c6f1716415` |
| Measured helper commit | [`bb23b6c7a3de66d1402ae7286e563b3951aa88ca`](https://github.com/CrispStrobe/legacy-doc-parser/commit/bb23b6c7a3de66d1402ae7286e563b3951aa88ca) |
| Measured tree | `9481131016f842f5b14800d313f00a328a8a23c7` |
| Windows run | [43384946189](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43384946189), job `131751112801`, all steps successful |
| SDK / actual runtime | .NET SDK `8.0.428` / `.NET 8.0.34` |
| Windows / architecture | `Microsoft Windows 10.0.26100` / x64 |
| Actual WPF informational version | `8.0.34-servicing.26522.17+c45b7b239ce0d0b210c0c7b48862804f4a038c78` |
| Actual WPF assembly SHA-256 | `cc1664768c1852d209f7c1121285c5bcc94262f9e60e38860d0143f8e28c0d11` |
| Original downloaded artifact | `14017873774`, 105,562 bytes, 142 members, 389,309 uncompressed bytes |
| Original artifact SHA-256 | `79561a6936904aa3268d4220852707c30d999ebee86fc2b57fd51e27434d381a` |

The helper was saved remotely before the Windows run. `successful-run.zip`
is the original download and matches GitHub's artifact digest.
`provenance.json` retains the original run/job/artifact responses and
`successful-job.log` the returned job log. The workflow recorded clean Git
status before and after execution. It built with zero warnings and errors.

The 116 native output files are copied byte for byte into
[`test/fixtures/ink_wpf_headers`](../../../test/fixtures/ink_wpf_headers):
32 ISFs, 32 PNGs and 52 JSON files, totaling 294,115 bytes. They include both
original source baselines, every mutated input and its complete before/after
record inventory, each native second save, both native snapshots/renders and
the summary. The ZIP additionally retains the 18 author-stage input files and
eight build/runtime/source-status logs. The duplicated author-stage inputs are
verified equal to what the native runner actually loaded.

The Windows checkout uses CRLF for eight text sources. `source-inventory.json`
records their actual pre-run Windows sizes and hashes. The retained `source/`
copies are reconstructed from the exact Git blobs with LF→CRLF conversion,
then checked against those observed hashes. `checkout-source-binding.json`
records both byte identities explicitly. The two original binary ISFs require
no conversion. `--check-git` verifies all ten sources against the measured Git
commit. This is an exact byte binding, not an assumption that the Windows
checkout and Git blobs have identical line endings.

## Transform results and the initial hypothesis

Each of the following six cases was authored as a float-only transform and
again with the same initial float values plus matching extended-double tag 31.
All six pairs have identical decoded snapshots and **zero differing pixels**.
Coordinates below are in Himetric (1/100 mm), before the fixed `96/2540` DIP
conversion. Drawing attributes remain unchanged.

| Transform | Initial WPF result | Later WPF save/reload |
| --- | --- | --- |
| Tag 17, isotropic `2` | `(2x, 2y)` exactly | No coordinate or pixel change |
| Tag 18, anisotropic `2, 0.5` | `(2x, 0.5y)` exactly | Half-Himetric values such as `317.5` become `318`; maximum 0.5 Himetric; 25 changed pixels |
| Tag 20, compact `100, -50` | Every point becomes `(100,-50)` | No further coordinate or pixel change |
| Tag 16, full affine `1,0,0,1,100,-50` | `(x+100, y-50)` exactly | No coordinate or pixel change |
| Tag 21, `2,0.5,100,-50` | `(2x+100, 0.5y-50)` exactly | Half-Himetric values such as `267.5` become `268`; maximum 0.5 Himetric; 35 changed pixels |
| Tag 16, full affine `2,0,0,0.5,100,-50` | Same result as tag 21; zero pairwise differing pixels | Same 0.5-Himetric / 35-pixel normalization |

The author had recorded the conventional translation hypothesis for compact
tag 20 as `(x+100,y-50)` before execution. WPF disagrees with that hypothesis
by up to 3,175 Himetric, and its raster differs from the full affine
translation by 459 pixels. The field named `sourceFormula` in the original
records retains that **pre-execution hypothesis**; it is not a current claim
about the tag's specification semantics.

The subsequently checked primary Microsoft
[ISF specification, Transform Block and BNF sections](https://www.loc.gov/preservation/digital/formats/digformatspecs/InkSerializedFormat%28ISF%29Specification.pdf)
explicitly assigns **zero to all four linear coefficients for tag 20**. The
inspected WPF `LoadTransform` implementation and the measured runtime agree
with that definition. Therefore the compact-tag collapse is **not evidence
of a WPF defect or dropped source translation**. The explicit full affine
matrix is the demonstrated encoding for a conventional translation. Neither
the original hypothesis nor the observations were rewritten after this finding.

## Pressure metric results

The baseline pressure packets are `0,127,511,895,1023`. Both metric controls
leave the stroke descriptor and these encoded packets byte-identical. A
complete entry stores minimum, maximum, unit `None` and resolution 1.

| Input | First WPF load | First vs baseline pixels | WPF save/reload |
| --- | --- | --- | --- |
| Implicit default metric | Minimum 0, maximum 1023 | 0 | Stable |
| Explicit full `0..1023` | Same default metric and factors | 0 | Stable |
| Explicit full `0..2047` | Minimum 0, maximum 2047; factors `0,0.062042013,0.24963361,0.4372252,0.49975574` | 799 | Native compact entry reloads with maximum 1023, original default-range factors and 799 changed pixels |

The full `0..2047` metric record is `19 0a 38 08 00 fe 1f 00 00 00 80 3f`.
WPF saves it as `19 05 38 03 00 fe 1f`: tag 25, block length 5,
NormalPressure tag 56, entry length 3, minimum 0 and maximum 2047. The units
and resolution are omitted. WPF's next reload reports maximum **1023** even
though those compact bytes still encode **2047**. All raw pressure property
values stay unchanged; the maximum observed pressure-factor difference is
`0.5002442598342896`.

The specification's Metric Block section permits omitted trailing metric
values and gives an explicit minimum/maximum-only example: the supplied range
is retained and only the omitted unit/resolution take defaults. Thus the
compact record still specifies maximum 2047. The first and second WPF results
document a native reload departure for this specific compact record. A
portable reader should preserve the encoded range; these observations do not
justify rewriting the source metric to 1023.

## Scope and verification

The runner compiles the prior WPF helper unchanged and reuses its load/save,
snapshot and difference methods. The new 512 × 256 white canvas, at 96 DPI
with a 32-DIP translation and software-rendering preference, fits the doubled
polyline without clipping. PNG bytes, decoded BGRA pixels, nonwhite counts and
bounds are verified separately from geometry. The verifier reconstructs PNG
pixels; it does not replace WPF with a custom ink renderer.

```sh
python3 doc/evidence/wpf-isf-metrics-20261113/verify.py --check-git .
python3 -O doc/evidence/wpf-isf-metrics-20261113/verify.py --check-git .
python3 doc/evidence/wpf-isf-metrics-20261113/test_verifier.py
python3 -O doc/evidence/wpf-isf-metrics-20261113/test_verifier.py
```

The verifier binds the exact GitHub run/artifact, original ZIP, exact fixture
copies, ten source identities, every mutation inventory and unchanged stroke
record, native argument list, snapshots, pressure metrics, declared formula
differences and all 12 raster comparisons. Eighteen semantic corruption
controls recompute inner manifest hashes before checking rejection. They
cover source/command substitution, rewritten hypotheses, changed packets,
erased translation/pressure observations, altered paint and false pixel or
serialization claims. In particular, both native loads must retain the exact
source pressure packets; explicit packet factors must match their reported
metric, and a transform alone cannot alter the implicit default pressure
metric. All checks remain active under optimized Python.

The measured scope is Windows WPF ISF decoding and ink rendering. These
controls do not establish Microsoft Word rendering, OfficeArt placement,
document round-trip fidelity or arbitrary transform/metric support. The
inspected WPF source revision remains `e7acf467c05e51901b17684b1f2c330e7dc5fc4d`,
distinct from the actual assembly recorded above. See the
[isolated helper and primary source references](../../../tool/ink_metrics_oracle/README.md)
for the byte author and reproduction commands.
