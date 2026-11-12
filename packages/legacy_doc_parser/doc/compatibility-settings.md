# Source compatibility settings

The parser exposes `LegacyWordDocument.compatibility`. It records explicit
layout choices from the referenced DOP's Copts60, Copts80 and Copts blocks, with
immutable copies of those small source blocks and their provenance. An absent
option is unspecified; a present `false` remains an explicit disabled option.

Structured conversion writes 61 fixed layout options as native `w:compat`
children in `word/settings.xml`, including both `w:val="1"` and `w:val="0"`.
The supported set covers Word 97 object/footnote wrapping, table row alignment,
table spacing and fitting, East Asian line breaking, tab/numbering interactions,
printer/font metrics, and legacy line/paragraph spacing. Six binary flags have
the opposite meaning in OOXML and are inverted explicitly. The source blocks
are also retained as inert evidence, including non-layout and reserved bits.
Mail-merge escaping, field-selection behavior and forced black printing are
not emitted. No compatibility mode, application version, field update, link,
macro, or protection policy is inferred from these bits.

## Bounds and conflicting copies

FIB extension lengths and versions select the DOP layout. Complete DOPs use the
documented minimum lengths; historical 84/88-byte prefixes remain readable with
an explicit `partialLegacyDop` issue. Partial compatibility blocks and truncated
advertised structures are rejected. Word 2007/2010/2013 share the decoded Copts
prefix; later unrelated fields have no inferred semantics.

The specification requires repeated Copts60/Copts80 copies to agree. When they
disagree, the parser keeps agreeing flags and leaves each disputed flag absent
from the native settings. `ambiguousFlags`, `issues`, source block bytes, and
inert conversion evidence make that loss of certainty visible.

One bounded interoperability recovery matches the authored native fixture and
LibreOffice's pinned writer: `nFib=0x101`, 136 FIB pairs, `cswNew=0`, and exactly
610 DOP bytes. The complete options at offsets 84 and 508 must agree, ignoring
the reserved bit 9. Only then is the unadvertised extended block decoded. When
the oldest meaningful low word is zero and both later low words are exactly
`0x2000`, the later `fExpShRtn` choice is used. Both recovery and conflicting-copy
issues remain recorded; this is not a claim that the source was conforming or
that its original author's intent is known. Other disputed bits remain
unspecified. Arbitrary trailing bytes do not identify an extended Copts block.

The parser adds `unsupportedFormatting` when recovery, partial or ambiguous
settings are encountered. Native DOCX consumers may implement these historic
options differently. The HTML preview does not emulate a Word pagination
engine; native option preservation does not establish equal line breaks,
table widths or page counts, particularly when fonts or printer metrics differ.

## Sources and tests

- Microsoft [Fib](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9aeaa2e7-4a45-468e-ab13-3f6193eb9394)
  and [Dop version selection](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/841b5f72-487e-4fe7-8657-ec90d5af8750).
- Microsoft [DopBase](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e),
  [Dop95](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/6de53c75-87cf-47bc-9283-ba84b3eb2ec5),
  [Dop97](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2feeb178-f901-4151-bf5c-8496d5a0700b),
  and [Dop2000](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/fb0ce92e-36c9-4060-a37e-45708860d997):
  Copts60 at offset 8 (2 bytes), Copts80 at 84 (4 bytes), Copts at 508 (32 bytes).
- Microsoft [Copts60](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8b8c7ac1-c424-40c2-8645-ba719af38bf9),
  [Copts80](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/6ada042e-d11e-4c6f-9c7e-6cc27281ed3d),
  and [Copts](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/93788691-b8f0-44a8-8fee-a8d6491dc0c4):
  bit positions, six opposite meanings, and native option names.
- Microsoft [WordprocessingML Compatibility](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.compatibility)
  and [Settings](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.settings).
- LibreOffice [WW8Dop read/write at revision 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8scan.cxx):
  the read path applies complete later copies, and the write path emits the
  610-byte form with options repeated at 84 and 508. This was researched for
  interoperability; no LibreOffice code was copied.

`test/legacy_word_compatibility_test.dart` uses independently authored binary
fixtures for every supported bit, disabled/inverted values, all supported DOP
versions, duplicate conflicts, malformed bounds, reserved/non-layout bits,
empty stories, model immutability, native XML ordering, and evidence payloads.
It also checks the existing authored `word_native/formatting.doc` fixture's
observed recovery and source options. These tests do not certify pagination.
