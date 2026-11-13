# Textbox stroke default: retained native counterexample

Word's OfficeArt `lineWidth` property (`0x01CB`) defaults to `0x2535` EMU,
or 0.75 points. Materializing that width on VML textboxes at checkpoint
`832b51ace136c3a15fa8ac668dd401cfca2924a7` improved initial Word 14 word
placement, but caused a larger repeat-import regression. The automatic default
output has therefore been withdrawn. Explicit source widths remain preserved.
The later qualified frame path described below couples that documented default
to the corresponding outer-frame conversion; it does not restore the withdrawn
standalone default emission.

## Why the source default alone was insufficient

[MS-ODRAW lineWidth](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fb88b56e-2c2d-41c2-a0c8-98129e913b89)
defines the default and the inclusive range 0 through `0x0132F540` EMU.
The [Microsoft VML implementation notes](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/d019f23f-5977-43d8-b463-99ba8f6784eb)
record differing standard/Office stroke-weight defaults. These facts do not
establish the complete DOC-to-VML frame-border placement contract.

The native Word 14 measurements compare exact original DOC bytes, native DOCX
export and parser DOCX separately. With explicit wrapping clearances retained,
the source's word sequence and layout text match the parser output. Adding the
stroke default reduces initial maximum corresponding-word drift from 0.75 to
0.40 points, but successive imports move another 0.35 points each time and the
third cycle changes reading order. The wrap-only control instead retains the
word sequence through all three cycles, with 0.05 points per cycle and 0.15
points cumulative drift. Neither result is RGB-exact.

The [complete comparison and raw artifacts](evidence/textbox-wrap-stroke-20261112/README.md)
retain all four clean executions, including the unsuccessful candidate. The
candidate passed focused model tests and analysis; those checks did not prove
native layout stability. Its earlier source identity and result are unchanged.

## Remaining frame contract

LibreOffice's pinned
[Word binary importer](https://github.com/LibreOffice/core/blob/9a3be2502bf7762400fd0b655b6e42714cf2bb36/sw/source/filter/ww8/ww8graf.cxx)
contains a source-dependent border transform in `GetEscherLineMatch` and
`MatchSdrItemsIntoFlySet`: simple textbox borders have half their width outside
the shape rectangle, and importing into a native frame adjusts the rectangle
accordingly. For a 15-twip line this involves seven twips, or 0.35 points.
The subsequent [explicit-border frame correction](textbox-frame-borders.md)
now verifies and applies that conversion for a bounded simple, explicit-width
subset with independent source/target controls. It does not apply a global
position correction or extend the conclusion to absent widths, compound
borders, rotation or alignment.

For unresolved frames the writer does not force an absent textbox stroke width.
It continues to emit explicit zero, explicit hairlines and other supported
explicit widths, and disabled strokes remain disabled. Source validation is
retained: negative, out-of-range and complex binary line-width operands remain
unsupported evidence; caller-built invalid widths reject conversion. Source
coordinates, insets, table depth and existing goldens are unchanged. The
explicit-border correction derives VML frame dimensions from those retained
source coordinates only for its verified subset.

## Qualified enabled line with an absent width

A fully resolved type-202 textbox with a used, enabled source line now applies
the source default and the source-to-target frame conversion together. The
effective width is 9,525 EMUs (15 twips), so the outside extent is seven twips.
The model still records `widthEmu == null`; conversion evidence separately
records the source width, emitted width and outside extent. An unspecified
line-enabled flag does not establish this qualification. Explicit false,
zero width, complex/invalid width, rotation, alignment, automatic margins and
the existing unsupported-property guards retain their previous behavior.

The independent paired controls start with an authored 0.75-point VML frame
and retain its original native DOC export. A separate bounded source helper
removes `0x01CB` from every textbox FOPT layer and rejects any inherited
default operand that would remain. This creates a truly absent source width
without changing FSPA coordinates or substituting an explicit default.
The absent plain and dashed controls become exact against both their source
DOC and independently authored OOXML; the prior baseline displaced words by
0.35 points. The paired explicit-width control remains exact. All three remain
exact through three repeated imports, including each regenerated native DOC.

The literal disabled-line control remains exact against both the previous
parser and independently authored OOXML. It does not emit a default width or
move the source frame. Its existing native DOC path differs by 0.05 points and
changes by 0.05 points on the first native repeat; those observations remain
separate from the enabled-line correction. An earlier control using only a
nested `v:stroke on="f"` was rewritten to `fLine=true` by native export. That
original observation is retained and is not counted as disabled-source proof.

The original Word14 file remains excluded from this bounded frame transform.
All six textboxes still retain unresolved shape/group properties and relative
size operands (`0x033F`, `0x03A9`, `0x03BF`, `0x07C0`, `0x07C1`, `0x07C4`,
`0x07C5`). The alternative `metroBlob` is documented as ignorable, but the
current conservative shape guard still retains it; this change does not
silently weaken that guard or claim the full Word14 geometry is resolved.
