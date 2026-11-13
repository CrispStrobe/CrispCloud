# Note source attribution — 13 November 2026

The two outstanding note word-sequence differences have identifiable source
semantics. Neither justifies changing source text or restarting a note at a
number specified only by an inapplicable legacy field. This checkpoint adds
independent source inspection and protects the automatic table-note marker;
it makes no parser runtime change.

## Automatic marker versus native question mark

The `note-markers` source is already checked in as
`test/fixtures/word_native/note-floating-table.doc`. Its hash is
`80c3e144945e40e90fc8dac11e9e039e2fc2eef47bac1b7ac7d6ec1ef338cd72`, matching
the binary in the sealed `0c3e596` corpus. Independent CFB, FIB, CLX and note-PLC
decoding finds these literal facts:

| Record | Source value |
| --- | --- |
| Unicode text piece | CP 0–275 at `WordDocument` byte 2048 |
| Sixth footnote reference | Anchor CP 48; automatic index 6 at `1Table` byte 816 |
| Sixth note range | CP 167–206 |
| First character of sixth note | U+0002 at `WordDocument` byte 2382 |
| Question marks in the complete source text piece | Zero |
| Note text after its marker | `Table before  tail`, cell/row terminators, a real blank paragraph, and `After note table` |

The sealed native DOCX instead contains literal `?` text in a generated
textbox's DrawingML choice and equivalent VML fallback. Its binary PDF displays
one `?Table` token. The parser retains the source table, its real following
paragraphs and one `w:footnoteRef`. Its PDF displays `Table`. These are the
only unequal word tokens in the archived initial comparison. The source
contains no question mark to preserve.

The existing floating-note regression now asserts the literal source anchor,
automatic status, all nine note references, one emitted table-note marker and
the exact note text, including the two spaces. The retained table placement,
source paragraph boundaries and original native reports are unchanged.

## Source-defined numbering versus the obsolete DOP field

The unchanged `word-compatibility.doc` fixture has hash
`6c45dd6233904fab4e3583af53d52ac06d294773c01da14992bf3782bfae17dc`.
Its `nFib` is `0x0101` and `cswNew` is zero. At `1Table` byte 1675,
the old DOP footnote word is `0x0011`: restart each section and start at four.
Both active SEPX groups contain `sprmSRncFtn=1` and
`sprmSNfcFtnRef=2` (each-section restart, lower Roman). Neither contains
`sprmSNFtn`.

The old DOP numbering fields apply only through `nFib=0x00D9`. Moreover, a
section's `sprmSNFtn` offset applies only to continuous numbering. The current
source therefore starts each section at one, producing `i`; using its obsolete
DOP word would produce `iv`, as the native binary render does. The existing
native-section regression already protects this source-defined interpretation.
The audit now records all SEPX opcodes and exact byte offsets, so the absence
of an applicable starting-number instruction is independently reviewable.

## Reproduction and limits

Run from the repository root:

```sh
python3 doc/evidence/note-source-attribution-20261113/audit.py
```

The script resolves the repository relative to itself. It checks the exact
two source hashes and sealed-archive hashes, decodes the binary records without
using the Dart parser, verifies the inspected archive members and reproduces
`receipt.json`. It reads archive members in memory without extracting them.
Its deliberately narrow CFB/CLX decoder accepts only the recorded fixture
layouts. `--write` regenerates the derived receipt from those unchanged inputs.

All 35 focused tests passed on Dart 3.13.7:

```sh
dart test test/legacy_word_table_position_test.dart \
  test/legacy_word_native_section_direction_test.dart \
  test/legacy_word_note_layout_test.dart
```

This is an attribution of the retained `0c3e596` measurements, not another
native execution. It does not claim exact note pagination, glyph geometry,
floating-table appearance, or complete `word-compatibility` fidelity. The
native renderer's table/frame substitution and remaining layout differences
remain separate measurements. No authored fixture or golden was rewritten.

Primary interpretation references:

- [MS-DOC Character Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18): U+0002 automatic note reference.
- [MS-DOC DopBase](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e): version scope of `rncFtn` and `nFtn`.
- [MS-DOC Section Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e): `sprmSRncFtn`, `sprmSNFtn` and `sprmSNfcFtnRef`.
