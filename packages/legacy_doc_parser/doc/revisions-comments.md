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

## Remaining limits

Table/row/cell and section formatting history, moves, list-numbering revision
records, display-field revisions, and multi-step editing history are not
reconstructed as native tracked changes. One binary wall contains one prior
property snapshot, not an arbitrary revision log. Revision reasons are exposed
as source codes; they are not converted into invented user-visible edits.
No change is accepted automatically. Formatting histories for unsupported
properties remain a limitation even when a native revision element is written
for the supported subset.

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
