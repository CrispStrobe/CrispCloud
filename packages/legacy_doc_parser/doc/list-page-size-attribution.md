# Sparse list fixture page-size attribution

The retained `list-continue` and `list-restart` measurements change from an A4
binary-DOC render to a Letter parser-DOCX render. This is a real native rendering
discrepancy, but direct source inspection does **not** establish parser loss of
an A4 page-size declaration.

Both binary inputs have zero `fcPlcfSed` and `lcbPlcfSed` fields at WordDocument
offsets 202 and 206, with FIB language ID 1033. They contain no section property
table, page width/height or margins. The independent fixture builder also shows
that these sparse list inputs were authored without section records.

[MS-DOC section 2.6.4](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e)
defines absent `sprmSXaPage` and `sprmSYaPage` as 12,240 by 15,840 twips
(Letter). It requires explicit left, right, top and bottom margins for
interoperability. The binary fixtures omit those margins as well. Inferring A4
from the native renderer would replace a source default with a renderer-specific
choice, so the runtime and original corpus bytes remain unchanged.

The full before-change evidence remains in the immutable source-attributed
[native corpus receipt](evidence/native-corpus-7308125/README.md), cases
`18-list-continue` and `19-list-restart`. Both source documents, native exports,
parser outputs, PDFs, geometry and rasters are retained there. The measured
source render is 595.303937 by 841.889764 points; the parser output is 612 by 792
points. The 24.909/26.809-point word drift includes different margins, fonts and
line metrics in these underspecified fixtures, not just the page dimensions.

`test/legacy_word_page_size_source_test.dart` independently checks the original
FIB fields, verifies that absent or empty section properties do not invent an
A4 declaration, and verifies explicit A4 portrait, Letter portrait and A4
landscape sizes through the model and generated OOXML. These are additional
controls; no original input, golden, oracle or measured difference is changed.
