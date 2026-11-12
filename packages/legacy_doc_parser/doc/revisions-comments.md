# Tracked revisions and comment fidelity

The parser retains revisions; it does not accept or reject them. This is a
bounded reconstruction of the documented binary records, not a claim of full
Word revision fidelity.

## Formatting and text revisions

- `sprmCWall` / `sprmPWall` capture the resolved formatting immediately before
  the wall. Later properties remain the current formatting. A false wall clears
  the previous snapshot. Style changes and `CPlain` preserve the saved state.
- Character and paragraph `PropRMark` records retain the author-table index,
  raw DTTM, resolved author and wall-clock date. Current-formatting previews
  mark supported changes without displaying old hidden text.
- Native DOCX `w:rPrChange` and `w:pPrChange` contain the supported previous
  properties. Missing snapshots remain disclosed evidence; the writer does not
  fabricate an empty prior style and call it a recovered change.
- Insertions and deletions have separate provenance, even when both apply to
  the same range. Revision-save IDs are retained when supplied. The original
  `revisionAuthor` / `revisionTime` fields remain a compatibility view.
- A paragraph mark has its own formatting and insertion/deletion state.
  `w:pPr/w:rPr/w:ins` or `w:del` represents that state independently of the
  paragraph text. The HTML preview shows a marked paragraph symbol; plain text
  keeps its existing content and paragraph boundaries.

The binary timestamp has no time zone. DOCX dates omit a zone instead of
asserting UTC. Missing authors or invalid dates stay missing and produce the
revision-metadata limitation. Unsupported pre-wall properties also produce that
limitation, even when the supported subset can be exported.

## Section formatting revisions

`sprmSWall` captures the supported section properties before subsequent SPRMs
modify the current state. `sprmSPropRMark` supplies the author and source date;
`sprmSRsid` retains the section save identifier even without an active revision.
The public section model exposes the prior state separately, and DOCX writes
native `w:sectPrChange` with a complete prior set of the supported properties.
Page size, orientation, margins, equal/unequal columns, section numbering,
document grids and title-page state can therefore be rejected independently of
the current settings. Prior section properties are validated too: a valid
current value cannot hide a malformed historical snapshot. Missing or unmarked
snapshots stay explicit evidence rather than fabricated history.

A binary section's break type terminates that section, whereas OOXML places the
break type on the following section. The writer shifts both the current break
and its prior value. If the receiving section already has a separately authored
layout revision, one `sectPrChange` cannot express both independent authors.
The local layout revision remains native; the incoming break revision remains
disclosed evidence. A changed terminal binary break likewise has no following
OOXML section and is disclosed. These cases are not reported as full fidelity.
Header/footer references remain outside `sectPrChange`, as required by the
native previous-section schema. The parser does not invent revision history for
header/footer relationships that the section SPRMs do not encode.

## Comment threads and ink evidence

Validated `ATRDPost10` / `AtrdExtra` records map to native `comments.xml` and
`commentsExtended.xml` parts. Reply relationships join the *last paragraph's*
`w14:paraId` for each comment. Multi-paragraph comments retain all paragraphs;
public model input may list a reply before its parent. Binary records follow the
specified pre-order and exact depth/relative-parent relation. Cycles, missing
parents, excess depth, wrong record lengths and non-preorder binary trees are
rejected.

The original 18-byte extended record is immutable in the public model and copied
into an inert evidence part with its Table-stream offset. The ink-annotation bit
is retained. Already supported referenced images/objects in comment stories use
the normal media paths; the ink bit alone is never turned into invented strokes
or an active `o:ink` element. Proprietary pen-stroke data is not decoded. The
record does not encode a resolved/done state, so none is fabricated in the native
thread part. A hidden/private parent keeps its reply branch inert as well.

## Document tracking, review and protection settings

Existing revision records and document-wide editing policy are separate format
features. The supported records above survive conversion, but the following
settings are **not reconstructed**:

| Source setting | Meaning and output gap |
| --- | --- |
| `DopBase.fRevMarking`; `Dop2007.fRMTrackFormatting` / `fRMTrackMoves` | Whether later edits are tracked, and whether formatting/moves receive their own revision records. The model has no corresponding policy fields; the writer omits `w:trackRevisions`, `w:doNotTrackFormatting` and `w:doNotTrackMoves`. |
| `DopBase.fRMView` / `fRMPrint`; `Dop2002.fAcetateShow*`; `Dop2003.fAcetateShowInkAtn` | Saved revision display/print preferences and annotation-type visibility. No `w:revisionView` or equivalent saved print policy is reconstructed. HTML explicitly marks supported revisions instead of reproducing the saved Word review mode. |
| `fLockRev`, `fLockAtn`, `fProtEnabled`, `lKeyProtDoc`; later protection mode/enforcement/style-lock settings | Enforced tracking, comments/forms/read-only restrictions, password-verifier metadata and formatting restrictions. These, permitted editing ranges and section form protection are not reconstructed as `w:documentProtection` or related native controls. |
| `FibBase.fReadOnlyRecommended` / `fWriteReservation` | The read-only recommendation and write-reservation state are not mapped to `w:writeProtection`. |
| `Dop2003.fFilterDttm` | The annotation date-removal preference is not mapped to `w:removeDateAndTime`; available revision dates remain preserved as described above. |

The [binary-source reader](../lib/src/legacy_word_binary_source.dart) reads
selected header, tab, note and layout-compatibility settings. The
[document model](../lib/src/legacy_word_structured_model.dart) and
[settings writer](../lib/src/word_story_writer.dart) do not carry the policies
listed here. The retained Copts source blocks are selected compatibility
substructures, not a full DOP settings backup. This gap has no dedicated
per-setting diagnostic; a general partial-formatting warning is not proof that
the original policy was detected or preserved.

OOXML defines omission of `trackRevisions` as not generating revisions for
later edits, omission of `revisionView` as showing all annotation types, and
omission of `documentProtection` / `writeProtection` as applying neither kind
of protection. Thus the converted copy does not preserve the source's automatic
tracking, review visibility or editing restrictions. Omitting these settings
does not accept or reject the existing revision records. Annotation visibility
does not itself remove persisted annotations. Hidden text and private field
content continue to follow their separate suppression rules.

Editing restrictions and write reservation are distinct from encryption.
Encrypted/obfuscated DOC inputs remain unsupported by this parser; it does not
decrypt them. These policy gaps are established by source/specification review,
not by a Microsoft Word run or an Open XML SDK validation result.

Primary references:

- [MS-DOC DopBase](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e)
  defines tracking, review/print and legacy protection flags.
- [Dop2002](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/4ba592e9-dff6-466e-b13d-257c325c4d8a),
  [Dop2003](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8783a51d-da22-4e5f-a8f0-d98ae25215c5)
  and [Dop2007](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/a97f1d2f-b260-4c55-9984-9f08021d1db5)
  define the later annotation, protection and tracking preferences;
  [FibBase](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fb6c06-4e5c-4778-ab4e-edbf26a545bb)
  defines the read-only recommendation and write-reservation flags.
- OOXML [trackRevisions](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.trackrevisions),
  [doNotTrackFormatting](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.donottrackformatting),
  [doNotTrackMoves](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.donottrackmoves),
  [revisionView](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.revisionview),
  [documentProtection](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.documentprotection)
  and [writeProtection](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.writeprotection)
  specify the separate output semantics and omission defaults.

## Remaining limits

Table/row/cell formatting history, moves, list-numbering revision
records, display-field revisions, and multi-step editing history are not
reconstructed as native tracked changes. One binary wall contains one prior
property snapshot, not an arbitrary revision log. Revision reasons are exposed
as source codes; they are not converted into invented user-visible edits.
No change is accepted automatically. Formatting histories for unsupported
properties remain a limitation even when a native revision element is written
for the supported subset.

Section decoding follows [MS-DOC section properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e),
and native history follows [SectionPropertiesChange](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.sectionpropertieschange)
and [PreviousSectionProperties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.previoussectionproperties).
`test/legacy_word_section_revisions_test.dart` independently assembles the binary
records and applies accept/reject property rules to parsed XML to verify both
states, including section-break ownership, unequal columns, conflicting authors,
missing snapshots and malformed historical values. These are semantic tests;
they do not certify Microsoft Word's pagination or its user-interface behavior.

## Specification and tests

The implementation is authored against Microsoft [MS-DOC Character
Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18),
[PropRMark](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2380efe1-d272-44cf-896f-9ead7f576dc9),
and [MS-DOC §§2.6.1–2.6.2 (2019 published
revision)](https://officeprotocoldoc.z19.web.core.windows.net/files/MS-DOC/%5BMS-DOC%5D-190319.pdf).
The older paragraph-record opcode is also documented in Microsoft's
[Word 97–2007 binary-format
specification](https://download.microsoft.com/download/0/b/e/0be8bdd7-e5e8-422a-abfd-4342ed7ad886/word97-2007binaryfileformat%28doc%29specification.pdf).
Native markup follows the Open XML specification's
[revision model](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-accept-all-revisions-in-a-word-processing-document);
that guide is used as a structural reference, not to accept changes.

`test/legacy_word_revisions_test.dart` independently assembles binary SPRMs,
FKPs and author records. It checks current/previous properties, style-reset
ordering, overlapping authors, paragraph marks, malformed lengths/Boolean
operands, privacy, and the independently parsed output XML.

Thread serialization follows [MS-DOC AtrdExtra](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1b6a50f8-de0c-4020-bce0-06e24660c928),
[ATRDPost10](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/19181fe7-a62a-4e70-9a5f-a0cb1ebe0921)
and the current Open XML [CommentEx last-paragraph
join](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2013.word.commentex?view=openxml-3.0.1).
`test/legacy_word_comment_threads_test.dart` uses independent binary records and
ZIP/XML assertions for the join, content types/relationships, source bytes,
privacy, input order and malformed graphs. Native ink uses a separate
[Ink Serialized Format](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/05ab37ae-e14e-424c-808e-6748b131c121);
the current comment-record evidence is not a reconstruction of that format.
