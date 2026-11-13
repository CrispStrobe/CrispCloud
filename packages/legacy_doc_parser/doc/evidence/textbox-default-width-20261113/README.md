# Qualified absent-width textbox frames

Two original native runs retain **653 archived files**, **50 lossless RGB
pages**, **5 initial observations** and **15 repeat cycles**. The candidate
source is based on `7356e9a9ecbf0c4f7857c6e9859dc7319f1cc258`
and was published as `cc475608db0812f63f6f9411cba8659d9ffe2696`. The measured
dirty-worktree identities and exact source snapshots are preserved. These are
paired source controls, not a new full-corpus or Word14 acceptance run.

## Discriminating controls

| Control | Prior baseline vs source DOC | Candidate vs source DOC | Candidate vs authored OOXML |
| --- | --- | --- | --- |
| True absent width, enabled plain line | Raster differs, 0.35 pt word drift | Exact | Exact |
| Explicit 0.75 pt line | Exact | Exact | Exact |
| True absent width, enabled dashed line | Raster differs, 0.35 pt word drift | Exact | Exact |
| True absent width, literal disabled line | Raster differs, 0.05 pt word drift | Same as baseline | Exact |

The first three controls remain exact against both their first import and
regenerated native DOC through all **9 cycles**. The literal disabled control
matches the prior parser exactly and does not emit a default stroke or change
the source frame. Its existing native bridge moves by 0.05 pt in the first
repeat, then stabilizes; that limitation remains in the report.

The fifth observation is the first disabled-control attempt in `probe-1`.
Its independently authored nested `v:stroke on="f"` is rewritten by native
DOC export to `fLine=true`. Source inspection confirms that it is an enabled
absent-width source, so it is not disabled-source coverage. The original
failure of that authoring assumption remains unchanged. `probe-2` uses the
outer VML `stroked="f"` and separately authors the literal source used-false
line operand. Both inspection outputs are retained. All **15 repeated parser
imports match their own regenerated binary exactly**; that does not mean all
native bridge cycles preserve the first appearance.

The source helper removes property `0x01CB` from all textbox FOPT layers and
rejects any inherited operand that would survive removal. It preserves the
native DOC export, source FSPA coordinates and other source table bytes,
writing the control to a new compound file. The source control records bind
the declared operands and exact input/output bytes. The corrected negative
control also sets `fUsefLine=true` and `fLine=false`. The helper does not call
the DOC conversion writer.

## Runtime boundary and remaining Word14 work

The qualified runtime uses the documented 9,525-EMU source default only when
the line is explicitly enabled and the existing complete frame qualification
passes. It emits that width together with the seven-twip outside-border
conversion. The model's absent width remains null; evidence records source and
emitted widths separately. Disabled, zero, invalid/complex, unspecified-line,
rotated, aligned and otherwise unresolved contexts remain distinct. See the
[source contract](../../textbox-stroke-defaults.md#qualified-enabled-line-with-an-absent-width).

Read-only inspection of the retained original Word14 file finds the same
remaining blockers on all six textboxes: `0x033F` shape booleans, `0x03A9`
alternative `metroBlob`, `0x03BF` group booleans, and `0x07C0`, `0x07C1`,
`0x07C4`, `0x07C5` relative sizing operands. This bounded change leaves those
guards intact. Fill paint support is documented separately, including native
tile placement and secondary-opacity consumer differences. This archive does
not certify full Word14 geometry. Original failures, fixtures and goldens are
unchanged.

## Verification

The manifest binds the archive, every member, summary and support file.
`native-artifacts.tar.xz` is **417,684 bytes**, SHA-256
`d83a601ff9608546d6f1bea557dfaf0051d0cde05d177e45162ad74bc37f3529`.
Source packages, original/controlled DOCs, parser outputs, PDFs, lossless
compressed 72-DPI RGB pages, execution logs, compiler/font/tool receipts and
exact build-source snapshots are retained. Native profiles and reproducible
converter executables are excluded. The read-only source inspector and its
Word14 source hash are retained alongside the **949 passing tests** log.

Use normal Python from the repository root:

```sh
python doc/evidence/textbox-default-width-20261113/verify.py
```

Verification refuses optimized Python, checks every archived byte and raw
raster, binds source-control/repeat inputs and outputs, recomputes render
comparisons, and verifies that the literal-disabled output remains exact to
the baseline. Native versions are LibreOfficeDev 26.8.0.0.alpha0 at
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdftoppm` and `pdfinfo` 26.05.0,
and `pdftotext` 25.03.0.
