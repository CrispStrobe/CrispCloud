# Binary metadata in Word hyperlink fields

A picture control character inside a binary DOC field instruction can identify
hyperlink metadata in the `Data` stream. Treating that character as literal XML
instruction text loses the whole field. Dropping every such character would also
be incorrect: it can identify other data or conflict with the literal field.

The converter therefore removes only a qualified metadata marker. It requires a
unique artifact at the exact global UTF-16 CP, produced by the actual
`CFData`/`CPicLocation` reference, with `Data` stream and `NilPICFAndBinData`
identity, bounded extent, matching length/header, HFD class identifier and
serialization version. The decoded target must exactly equal the target already
written in the literal instruction. One space replaces one U+0001, preserving
all field-event and nested-field offsets. The original instruction and binary
artifact remain in the output evidence.

The supported forms are currently:

* Internal `HYPERLINK \\l target`, with the existing bounded HFD location string.
* External `HYPERLINK target`, with one exact URLMoniker, no traversal options,
  display/frame/location extras, or optional serialization trailer. Absolute and
  relative moniker flags are accepted. Quoted and simple unquoted instructions
  retain their original spelling; the converter performs no URL normalization,
  resolution, download or traversal. The target must contain valid, non-control
  UTF-16 text and fit the 32,767-code-unit allocation bound.
* `REF`, `PAGEREF` or `NOTEREF` with an explicit `\\h` switch and a matching
  location-only HFD. The original reference instruction and cached result are
  retained; no bookmark lookup or result recalculation is substituted.

Malformed lengths, missing or ambiguous references, inconsistent targets,
unsupported flags/monikers, unpaired surrogates and unexplained trailing data
retain the original inert field evidence and cached visible result. This is a
bounded mapping, not a general COM-moniker implementation.

Qualified fields use the existing locked DOCX field representation and keep the
source cached result. Conversion does not calculate field results. The package
can therefore contain `HYPERLINK` field instructions rather than `w:hyperlink`
elements. A semantic reader must recognize both representations.

## Existing internal-link regression

The earlier retained `bookmarks` binary carries the internal location `Beta`
both in its literal `\\l "Beta"` target and its referenced HFD string. Its
byte-identical native fixture, source provenance and quoted/unquoted/Unicode
regressions remain in place. The external extension retains this original
qualification and all its malformed-data rejection controls.

These changes preserve navigation semantics. A native renderer can apply a
blue underline or other field presentation separately from the cached result's
explicit character properties; restoring the target does not establish a visual
match or authorize changing source character styles.

## Independently observed external-link loss

The unchanged `word` corpus binary has SHA-256
`2d2943d799d3a48430a90bff0bee68d7ab30fc2e5c26666d793160439e1f483d`.
It carries four HYPERLINK fields: body, footnote, normal header and first header.
Each literal URL agrees byte-for-byte with its referenced HFD URLMoniker. The
prior converter emitted cached link text but no hyperlink field or relationship.
The retained [independent-reader before-state](evidence/independent-readers-20261113/README.md)
documents the loss: Pandoc sees two body/note links in authored and native DOCX,
and zero in the prior parser output.

The exact binary is now a focused regression fixture, with its original archive
provenance next to it. The corrected output retains all four fields. In the
bounded native check, LibreOfficeDev 26.8 imports these fields and exports four
corresponding hyperlink elements with unchanged targets. Pandoc 3.1.11.1 reads two
links directly from the corrected DOCX and two from that native re-export; its
AST does not inspect the header stories. These are semantic checks, not a new
pixel-layout or whole-corpus fidelity certification.

## Separate reference-field producer recovery

An independently authored three-field DOCX (`REF`, internal `HYPERLINK`, `QUOTE`)
uses deliberately distinct cached results. Its unchanged native DOC bridge has
SHA-256 `20b4e506f40b733cd7d9467ec2e6f2844e0efe319a61e8c4822e371facee0292`.
The reference marker at CP32 identifies a 117-byte HFD whose declared location
ends at byte115. The final two bytes are zero. The other internal HYPERLINK HFD
has exactly one string terminator and no extra word.

This extra word is a native producer quirk, not a newly invented MS-OSHARED
field. In the exact source revision of the installed renderer,
[`InsertSpecialChar`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8atr.cxx)
writes a string length including one UTF-16 NUL, then writes a 32-bit zero after
the target text. That produces one additional zero word beyond the declared
HyperlinkString. The original source code and raw field bytes are retained with
the targeted evidence.

Recovery is limited to `REF`/`PAGEREF`/`NOTEREF` with an explicit `\\h`, the exact
location-only HFDBits and Hyperlink Object flags `0x08`, a valid bounded target
equal to the literal reference, and either the exact standard extent or exactly
one additional zero word. Wrong flags, nonzero padding, two extra words,
additional switches, missing references and conflicting targets stay inert.
This does not relax the HYPERLINK forms. A separate `binaryReferenceField`
evidence record includes `recoveredNativeTerminator`; the corresponding count is
`binaryReferenceFields`.

The native bridge had already dropped the authored field locks. Its direct
native DOCX export recalculated the reference result from `CACHED-REF` to
`ANCHOR-α`. Our conversion retains the original binary cached result and emits a
locked reference field. In the targeted native re-export of that corrected
DOCX, the reference field and `CACHED-REF` remain unchanged. The
original authored, binary, baseline parser and native results remain distinct.

## Primary format definitions

* [MS-DOC 2.9.158, NilPICFAndBinData](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5830324c-4f03-462a-b1f7-45707cd4036e)
* [MS-DOC 2.9.115, HFD](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f41daffe-fb3b-4373-a071-d3e86c59409d)
* [MS-DOC 2.9.116, HFDBits](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3bfc60ed-a4c6-4626-ac33-4639b8df10c7)
* [MS-OSHARED 2.3.7.1, Hyperlink Object](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/c0437222-4868-4660-81f8-6b7ee236d3f8)
* [MS-OSHARED 2.3.7.2, HyperlinkMoniker](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/0cc5cf39-2a16-45a9-a7fb-8994ce3f01a5)
* [MS-OSHARED 2.3.7.6, URLMoniker](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/4948a119-c4e4-46b6-9609-0525118552e8)
* [MS-OSHARED 2.3.7.9, HyperlinkString](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/1a9f6231-df63-4a95-b998-5c2b95b82965)
