# Separate header occurrences of one textbox range

The retained `header-textbox-duplicate-chain.doc` was an import failure in the
textbox-separator checkpoint. Its normal and first-page header shapes both
reference one single-frame text range. The converter now preserves those two
stored header occurrences for a bounded, explicitly diagnosed case. It keeps
the original text range, shape IDs, anchor CPs and chain index zero. It does not
invent a second FTXBXS or a text-flow link.

## Source evidence and native corroboration

The exact source SHA256 is
`4e8a4388d0a509836760d84c8ef28158ee90018518928a93f4c01980e5387624`.
The independently authored DOCX, source receipt and original failing DOC are
retained under `test/fixtures/word_native/header-textbox-duplicate-chain*`.
The earlier red measurements remain in
`doc/evidence/textbox-boundary-native.json.gz`.

| Source record | Observed value |
| --- | --- |
| Real `PlcfHdrtxbxTxt` range | CP `[0,7)`, including the separator CR |
| FTXBXS count and first shape | `cTxbx=1`, `lid=1025` |
| Normal-header raw range | Header-relative `[2,5)` |
| Normal-header drawing | Shape `1025`, header-relative CP `2` |
| First-header raw range | Header-relative `[5,8)` |
| First-header drawing | Shape `1026`, header-relative CP `5` |
| Both `OfficeArtClientTextbox` records | `0x00010000`: source index 1, chain index 0 |

[MS-DOC OfficeArtClientTextbox](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ea806f3-8ff6-4ce4-8cb2-3ba732af4ec4)
defines the high and low words as those two indices.
[FTXBXS](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d0a81fe8-f9e8-4130-9233-84732e3d9420)
identifies the first shape using `lid`.
[FTXBXNonReusable](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5aaa54b6-f38c-440a-82b1-8d61beb95b31)
defines `cTxbx` as the number of shapes through which the text flows.
[Header Textboxes](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/73923196-74e1-4e69-88b8-d2cc9ac8093b)
describes the separate header textbox document and its reference tables.
These definitions do not make two chain-index-zero shapes a conforming
two-frame chain. The recovery is an observed compatibility case, not a global
reinterpretation of those fields.

The initial source has the first-page-header option inactive. A native DOCX
export therefore exposes the normal header only. The control in
`tool/fidelity/header_textbox_titlepage.dart` enables only `sprmSFTitlePage`,
copying the existing one-section SEPX and updating its pointer/stream length
when the flag was absent. It preserves all header ranges, FSPA, OfficeArt and
FTXBXS bytes. LibreOffice then exports **both** normal and first headers with
the same authored textbox paragraphs. This independently corroborates shared
text in separate header occurrences without changing a drawing or textbox ID.
The helper is test infrastructure; the production converter never enables the
first-page-header flag on the user's behalf.

## Recovery boundary

The parser and public-model writer use the same corroboration checks:

- Exactly two real shapes reference one `cTxbx=1` record. Both have chain index
  zero, no next-shape link, distinct IDs and distinct anchor CPs. One matches the
  FTXBXS first-shape identity and anchor exactly.
- The shapes lie in separate normal and first headers of the same section.
  Main-story duplicates, duplicates within one header, footer aliases,
  cross-section aliases and additional occurrences are not recovered.
- Both are ordinary textbox shapes with the required source context. Hidden,
  inserted, deleted, grouped, child, master and OLE occurrences are excluded.
  Public-model occurrences carrying independent insertion or deletion metadata
  are also excluded when their revision flags are false. Alias recovery rejects
  that inconsistent provenance instead of normalizing or discarding it.
- The shared content contains unnumbered paragraphs and supported character/
  paragraph formatting. Intentional leading, interior and trailing empty
  paragraphs remain content.
- Tables, fields, bookmarks, note/comment references, nested media, numbering
  and character/paragraph review histories are excluded. Identity-bearing
  inline events are not replayed as independent review or bookmark identities.

`LegacyWordTextboxReference.anchors` remains the one-frame flow chain;
`headerAliases` holds the separate source occurrence. The warning
`recoveredHeaderTextboxAlias` and the DOCX evidence record `headerTextboxAlias`
identify the recovery and retain both owning header stories, source IDs and CPs.
The output emits neither an invented `mso-next-textbox` link nor a second copy
inside one frame. The existing contiguous-chain validation remains in force.

## Reproduction

The focused alias/boundary/compact-chain/extended-chain suite passes 67 Dart
tests, including 30 alias and activation controls. Ten Python oracle tests
include six new occurrence checks. Open XML SDK validation reports zero errors
for 21 packages: seven literal controls and fourteen default/first-enabled
native-input conversions. Its positive and negative controls pass. Both runs of
the literal producer yield identical bytes for all 15 files.

The [native receipt](evidence/header-textbox-alias-native.json.gz) and
[schema receipt](evidence/header-textbox-alias-schema.json) retain their exact
source and output hashes. The [audit manifest](evidence/header-textbox-alias-audit.json)
hashes every member of the 276,220-byte
[input/result archive](evidence/header-textbox-alias-inputs.tar.xz). It includes
all seven original red controls, their activated variants, native/parser
outputs, the 21 schema inputs and the exact measured parser/tool source.
The native measurement preceded the production commit and is honestly marked
as a dirty snapshot. Every measured production source file matches the saved
production commit. A later brace-only lint cleanup affected the activation
control tool; its original measured source is retained separately in the archive.

`tool/fidelity/header_textbox_alias_fixture.dart NEW_DIRECTORY` emits seven
deterministic DOC/DOCX controls: `header-alias-content`, `header-alias-empty`,
`header-alias-leading-blank`, `header-alias-interior-blank`,
`header-alias-trailing-blank`, `header-alias-two-trailing-blanks` and
`header-alias-two-content-paragraphs`. These literal binary fixtures test parser
and schema behavior; they are not advertised as native drawing oracles.

The native probe starts with independently authored literal DOCX files, exports
them to DOC, and checks each header occurrence against its authored paragraph
sequence. It also checks first-page-activated DOC and native projections of the
parser's DOCX. Equal text in two parts is counted twice; missing first headers,
extra boxes, dropped empty paragraphs and changed activation flags fail
independently. All seven controls pass those routes in this increment.

```sh
python3 tool/fidelity/header_textbox_alias_probe.py \
  --office /path/to/soffice --dart /path/to/dart \
  --output build/header-textbox-alias-native
```

To reuse the exact earlier red controls, also supply `--existing-controls` and
`--existing-receipt doc/evidence/textbox-boundary-native.json.gz`. The probe
verifies each authored DOCX, binary DOC and native DOCX hash before use, saves
every completed case and retains original errors separately. Its result concerns
textbox paragraph content and header occurrence semantics. It does not certify
exact page layout, arbitrary shape effects or general shared textbox editing.

The retained controls can be restored without a new DOCX-to-DOC bridge:

```sh
python3 -m tarfile -e doc/evidence/header-textbox-alias-inputs.tar.xz \
  build/header-alias-evidence
python3 tool/fidelity/header_textbox_alias_probe.py \
  --office /path/to/soffice --dart /path/to/dart \
  --existing-controls build/header-alias-evidence/controls \
  --existing-receipt doc/evidence/textbox-boundary-native.json.gz \
  --output build/header-alias-recheck
```

For an exact measured-source rebuild, `measurement-source/` contains the parser,
lockfile, compiler adapter and native activation/probe sources. The archive's
`schema-inputs/` contains the exact 21 packages accepted by the recorded SDK
binary. Run the validator's `--self-test` before revalidating that directory.
