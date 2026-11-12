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

- Exactly two real anchor occurrences reference one `cTxbx=1` record. Both have
  chain index zero, no next-shape link and distinct anchor CPs. One matches the
  FTXBXS first-shape identity and anchor exactly. They either have distinct shape
  IDs, or share the same decoded OfficeArt shape and artifact without an image
  reference. A reused numeric ID never authorizes two conflicting payloads.
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

## Shared shape after a native DOC round trip

The complete `8367ce0` native run exposed a further occurrence case. The first
DOC re-export of `header-textbox-first-enabled` retained header-relative anchor
CPs 2 and 5, but both SPAs referenced shape 1025 and OfficeArt contained only one
textbox shape. The FTXBXS still had `cTxbx=1`, `lid=1025`, and one real text range.
The parser previously stopped at `Ambiguous Word shape anchor.` The exact red
input is retained as `test/fixtures/word_native/header-textbox-first-roundtrip.doc`,
SHA256 `8beb2137004158fe373f032be53cfbbd802b237b308aa87b1802a6f2a979973d`.

[MS-DOC PlcfSpa](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e98fe93c-d57f-4d9b-a519-30e6acbdd414)
requires distinct anchor CPs and associates each with a SPA.
[MS-DOC Spa](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fcafc0-554b-46bc-aebf-c755276c77a4)
identifies its OfficeArt shape through `lid` and supplies the occurrence's
rectangle and wrapping flags. Those definitions do not justify a global
one-anchor-per-shape rule, but they also do not establish arbitrary shared
textbox editing semantics. Recovery therefore remains inside the normal/first,
single-frame, plain-content boundary above.

Parser and writer resolve each occurrence by `(headerStory, shapeId, anchorCp)`.
The two source rectangles differ: `[1447,1447,4311,1871]` and
`[1454,1454,4304,1864]` twips. Both survive separately, including their different
front/behind flags. The model retains the actual shape ID 1025 in both places;
the VML element identifiers append the source CP to distinguish package
occurrences. The additional warning `recoveredHeaderTextboxShapeAlias` and
`sharedShape: true` evidence disclose this recovery. Same-header/main-story
duplicates, a third occurrence, duplicate FSP records, unresolved references,
flow chains and identity-bearing content still fail the applicable guards.

An export-ID hypothesis was tested independently. The unchanged VML, an added
`o:spid`, standard `_x0000_s1025`/`_x0000_s1026` IDs, and both changes together
all produced the **same failed DOC hash** above. No ID spelling change is
claimed to cure the native exporter behavior.

The focused regression suite passes **185 Dart tests** and **12 Python tests**;
analysis and formatting are clean. All seven retained first-enabled controls
pass their initial import and three successive DOC re-exports: **28 parser
imports and 28 independent native DOCX projections** preserve both header
occurrences and the exact expected paragraph sequence. All 29 parser outputs
(those 28 plus the retained red input) pass Open XML SDK validation, with its
positive, invalid-XML, wrong-package-type and exact-discovery controls passing.
These measurements certify the bounded content/occurrence recovery. Native
frame-size and position changes remain measured layout limitations.

The [native receipt](evidence/header-shared-shape-native.json.gz),
[SDK receipt](evidence/header-shared-shape-schema.json),
[archive manifest](evidence/header-shared-shape-audit.json) and
[exact inputs/results](evidence/header-shared-shape-inputs.tar.xz) retain the red
input, all cycle DOC/DOCX files, rejected ID controls and measured source.
The measured snapshot is honestly recorded as a dirty worktree based on
`d28be0a`; all production and probe source hashes remained unchanged during
measurement. Reproduce the seven-case check from the earlier sealed controls:

```sh
python3 -m tarfile -e doc/evidence/header-textbox-alias-inputs.tar.xz \
  build/header-alias-evidence
python3 tool/fidelity/header_textbox_roundtrip_probe.py \
  --office /path/to/soffice --dart /path/to/dart \
  --controls build/header-alias-evidence/results \
  --receipt doc/evidence/header-textbox-alias-native.json.gz \
  --output build/header-shared-shape-recheck
```

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
