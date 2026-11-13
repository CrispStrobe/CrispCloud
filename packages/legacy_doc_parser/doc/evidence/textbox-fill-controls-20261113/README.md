# Scaled-gradient textbox controls

The archive retains **737 files**, **58 lossless 72-DPI RGB raster pages**,
**7 initial observations**, and **15 repeat cycles** from three completed runs.
The observations are source-hashed exploratory builds based on
`ae8a938b8aae13fa9268e171afeb886836268f69`; the original dirty-worktree identities
and every recorded build input remain retained. Repeated controls across runs
are counted as observations, not additional independent test designs.

## Source authoring and results

`probe-1` exposed a false coverage path: an independently authored VML gradient
renders correctly, but native DOC export replaces it with a solid midpoint
color. Both parser versions matched that flattened binary. The original result
is retained unchanged and does not qualify gradient support.

`probe-2` and `probe-3` retain that original binary and use
`tool/fidelity/textbox_property_control.dart` to author declared scalar FOPT
operands into a new copy containing exactly one textbox. The helper removes
superseded operands from the relevant property layers, maintains one primary
FOPT record, updates container lengths, and appends the resulting OfficeArt to
the table stream. The FIB points to the new extent. Original table bytes,
FSPA source coordinates, other streams, and compound directory metadata remain
retained. Requested properties, original operands, commands, hashes, and exact
input/output files are included. This authoring uses the compound-file writer
and the documented source format; it does not call the DOC conversion writer.

| `probe-3` control | Authored OOXML vs controlled DOC | Candidate vs controlled DOC | Prior parser word drift |
| --- | --- | --- | ---: |
| 0% gradient focus | Exact | Exact | 1 pt |
| 100% gradient focus | Exact | Exact | 1 pt |
| 45-degree angle | Exact | Exact | 1 pt |
| -45-degree angle, -50% axial focus | Exact | Exact | 1 pt |
| Unequal 50%/25% opacity | Raster differs; zero word drift | Raster differs; zero word drift | 1 pt |

All five candidate outputs match their independently authored OOXML exactly.
All **15 repeat imports match their own regenerated binary exactly**. The
native DOC bridge flattens the gradient on the first repeat, so no repeat is
exact to the first parser import. Opaque controls stabilize after that bridge
change. The unequal-opacity control continues changing on later native saves;
those observations remain in the report.

The remaining alpha discrepancy has a source-level explanation: the native
VML reader consumes unqualified `opacity2`, but the schema requires
`o:opacity2`. The parser keeps both source alpha operands with the correct
namespace. No bitmap substitution, inferred color adjustment, or invalid
attribute is introduced. See [the runtime contract and primary sources](../../textbox-paint.md#scaled-gradients).
These controls do not certify the complete Word14 document or its implicit
border/frame geometry. Original fixtures, failures, and reviewed goldens are
unchanged.

## Verification

`native-artifacts.tar.xz` is **437,012 bytes**, SHA-256
`e7449e888a46e6bb701133e5e07d9dbe586c505664f8902f4c60fee77394f2dc`.
The manifest binds every archived file and the summary. Original source
packages, native exports, controlled DOCs, parser outputs, PDFs, raw compressed
RGB rasters, comparison reports, logs, and exact build-source bytes are
retained. Native profiles and reproducible converter executables are excluded;
compiler identities, logs, executable hashes, and source inputs remain.

From the repository root, use normal Python:

```sh
python doc/evidence/textbox-fill-controls-20261113/verify.py
```

Verification hashes every member, decompresses and checks all 58 raw pages,
binds them to their original PDFs and reports, checks source-control and repeat
binary/DOCX identities, and recomputes all measured render comparisons. The
verifier explicitly refuses optimized Python; inherited helpers use assertions.
`seal.py` records how these runs were packed and how the two earlier harness
versions were recovered and verified against their original recorded hashes.

Sealed native tools are LibreOfficeDev 26.8.0.0.alpha0 at
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdftoppm` and `pdfinfo` 26.05.0,
and `pdftotext` 25.03.0. Reports retain compiler and font identities.
