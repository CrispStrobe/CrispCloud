# An omitted terminal paragraph-mark format

Some LibreOfficeDev 26.8.0.0.alpha0 binary exports end their CHPX bin table and
its final formatting page immediately before the last main-story CR. The CLX
still references that complete character, and PAPX still covers it. The source
contains text but supplies no character formatting for its terminal mark.

This is a reported interoperability recovery, not a reinterpretation of the
binary format. [MS-DOC §2.4.6.2, Direct Character Formatting](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/be58bf9c-d1d3-40cc-91ee-36452d7939b2)
defines both the BTE and CHPX page ends as exclusive and treats an FC at those
ends as invalid. [ChpxFkp](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f5f10f04-d4cc-4ebd-86df-0de6d227675c)
does not authorize inheriting an absent run's properties. In the pinned
OfficeArt example, the preceding character is a drawing anchor; copying its
properties would invent the wrong mark state.

## Exact recovery boundary

The parser leaves `LegacyWordParagraph.mark` null and reports both
`terminalMarkFormattingUnavailable` and `revisionMetadataIncomplete`. The
writer consequently reports partial formatting and revision limitations; it
does not write a fabricated paragraph-mark style, insertion or deletion.

All of these conditions must hold:

- The missing character is the final main-story CR, with at least one earlier
  character in the same CLX piece.
- There are no declared auxiliary stories, no additional CLX character beyond
  the main story, and no PRM on that final piece.
- The final CHPX bin and its actual final physical page end exactly at the
  missing CR's FC. The preceding complete code unit belongs to a valid run.
- The final PAPX bin and physical page end exactly after the complete CR and
  explicitly cover it. An absent-format fallback cannot establish this.

Ordinary lookup remains exclusive and strict. Interior holes, non-CR endings,
more than one missing code unit, partial UTF-16 units, clipped bins whose
physical pages continue farther, unmatched paragraph boundaries, and sources
with auxiliary-story ambiguity are rejected. The source buffer is never
modified. A source whose terminal revision state matters should still be
checked in its original application; that state cannot be recovered here.

## Native evidence and regressions

The five failing imports had these independent byte boundaries. All are
uncompressed UTF-16, with no auxiliary stories or piece properties.

| Native case | Import stage | Terminal CP | Terminal FC / CHPX end | PAPX end |
| --- | --- | ---: | ---: | ---: |
| OfficeArt shapes | Initial binary export | 84 | 2216 | 2218 |
| EMF vectors | Initial binary export | 64 | 2176 | 2178 |
| WMF vectors | Initial binary export | 64 | 2176 | 2178 |
| Continued list | Binary import of converted DOCX | 14 | 2076 | 2078 |
| Restarted list | Binary import of converted DOCX | 17 | 2082 | 2084 |

[The native check receipt](terminal-mark-native-check.json) pins the five input
hashes, parsed block counts and conversion checks. The 10 KiB
[`officeart-terminal-mark.doc`](../test/fixtures/word_native/officeart-terminal-mark.doc)
is the unchanged native export of the package-authored
[`officeart-shapes.docx`](../test/fixtures/fidelity/officeart-shapes.docx), generated
by [`tool/fidelity/authored_cases.py`](../tool/fidelity/authored_cases.py) and
converted by the isolated native harness. Its SHA-256 is
`2f9942934f293acf7ac3df6daada81c0e4799e0433a071166a8ab193b1846b6d`.
The native renderer was LibreOfficeDev 26.8.0.0.alpha0,
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. The authored content and binary
fixture use the package's MPL-2.0 license and contain no third-party document
text, macros or external links.

[`legacy_word_terminal_mark_test.dart`](../test/legacy_word_terminal_mark_test.dart)
checks the exact native structures, preserves all three shape occurrences,
checks that source bytes remain unchanged, and exercises positive and
malformed-boundary cases assembled independently of the parser. Recovery of
this specific omission does not establish general layout fidelity or make a
malformed binary document conform to MS-DOC.

## Reconciliation with the stricter shape writer

The pinned OfficeArt binary also has a `pVertices.op` length that excludes the
six-byte `IMsoArray` header. Only an exact stored element-width × count match
allows that bounded normalization; the complete FOPT record still has to
validate. The media catalog and conversion evidence report
`recoveredVertexArrayLength` with the original FOPT source location. Original
OfficeArt bytes are retained. Compressed custom paths and unmodeled shape
properties remain subject to the existing strict shape gate; terminal mark
recovery does not certify their editable rendering.
