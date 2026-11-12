# Linked text boxes and native reflow

The parser resolves a textbox story through its FTXBXS first shape, validated
FSPA anchors, OfficeArtClientTextbox story/chain indices and `hspNext` links.
The DOCX writer emits the editable story once in the first box, empty linked
successors, and the actual source positions. It does not split the text at
guessed line lengths or duplicate the story in every box. A receiving Office
layout engine performs reflow through that chain.

Explicit OfficeArt inner margins, vertical anchors, text flow, wrap setting
and fit-shape-to-text setting are retained. Missing margins use the documented
0.1/0.05/0.1/0.05-inch defaults; zero margins remain zero. Text wrapping inside
a shape is separate from FSPA wrapping of surrounding document text.
Automatic text margins, independent font-direction behavior, arbitrary
nonrectangular text regions and unsupported effects remain limitations.
Original OfficeArt and declared textbox layout are kept as evidence. Editable
links are not a claim of exact cross-renderer reflow or pagination.

## Independent native fixture

`tool/fidelity/authored_cases.py` authors `linked-textboxes.docx` directly in
OOXML, with two positioned boxes, different margins and 24 numbered words.
It does not invoke the parser or converter. The native harness measures the
OOXML-to-DOC bridge separately from DOC import and conversion.

The pinned `test/fixtures/word_native/linked-textboxes.doc` was exported from
that input by the already installed LibreOfficeDev 26.8.0.0.alpha0. Its FTXBXS
declares a one-shape chain while two ClientTextbox records and an explicit
`hspNext` establish a two-shape chain. This violates the documented count
constraint. The parser recovers only the specific count-one mismatch when
all indices are unique and contiguous, the first shape agrees, every forward
link is explicit and correct, and the terminal link is absent or zero.
Other mismatches, missing links, gaps, duplicates and cycles are rejected.
`declaredChainLength` retains the original value, `chainLength` describes the
resolved chain, and an unsupported-formatting warning plus both counts in
the evidence manifest disclose the recovery.

The native binary and malformed mutations are tested in
`test/legacy_word_native_textbox_test.dart`; model-level layout behavior is
tested in `test/legacy_word_textbox_layout_test.dart`. Native render reports
compare the actual word positions and page rasters, in addition to checking
that text occurs exactly once. Alternate representations must not be counted
as independent text stories.

## Format references

- Microsoft [FTXBXNonReusable](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5aaa54b6-f38c-440a-82b1-8d61beb95b31)
  defines the declared chain count and its required agreement with the shapes.
- Microsoft [Spa](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fcafc0-554b-46bc-aebf-c755276c77a4)
  defines source rectangles, origins and surrounding-text wrapping.
- Microsoft [MSOANCHOR](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fabbbc36-61b4-45da-9cb6-5aa695f411c9),
  [MSOTXFL](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/7e4ea24f-316d-45d2-aab0-f97b9a6fa49f)
  and [MSOWRAPMODE](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/893723db-1a02-4790-9418-dbfefc30571d)
  define source text layout values.
- Microsoft [VML inset](https://learn.microsoft.com/en-us/windows/win32/vml/msdn-online-vml-inset-attribute)
  and [Office textbox behavior](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/da04f6ea-a025-4e81-92c4-adfa5ab603fb)
  define margins and supported text properties in the output representation.
