# Textbox stroke default: retained native counterexample

Word's OfficeArt `lineWidth` property (`0x01CB`) defaults to `0x2535` EMU,
or 0.75 points. Materializing that width on VML textboxes at checkpoint
`832b51ace136c3a15fa8ac668dd401cfca2924a7` improved initial Word 14 word
placement, but caused a larger repeat-import regression. The automatic default
output has therefore been withdrawn. Explicit source widths remain preserved.

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

The current writer does not force an absent textbox stroke width. It continues
to emit explicit zero, explicit hairlines and other supported explicit widths,
and disabled strokes remain disabled. The specification-backed validation is
retained: negative, out-of-range and complex binary line-width operands remain
unsupported evidence; caller-built invalid widths reject conversion. Source
coordinates, insets, table depth and existing goldens are unchanged. The
explicit-border correction derives VML frame dimensions from those retained
source coordinates only for its verified subset.
