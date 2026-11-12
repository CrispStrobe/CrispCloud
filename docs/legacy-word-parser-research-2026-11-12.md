# Binary Word parser references

Reviewed on 2026-11-12 for the extension of CrispCloud's built-in DOC/DOT
preview and DOCX conversion. The source revisions below were inspected,
including their licenses and implementation files. Repository descriptions
alone were not used to establish support.

| Project | Reviewed revision | License | Use for CrispCloud |
| --- | --- | --- | --- |
| [legacy-doc-recover](https://github.com/graemewilsonnz/legacy-doc-recover/tree/aa7cc91e62be02db9374f0979ef638ee7fde5767) | `aa7cc91e62be02db9374f0979ef638ee7fde5767` | [0BSD](https://github.com/graemewilsonnz/legacy-doc-recover/blob/aa7cc91e62be02db9374f0979ef638ee7fde5767/LICENSE) | Recovery diagnostics and adversarial test ideas. Its tolerant recovery behavior is not adopted for ordinary viewing/conversion. |
| [wps2md](https://github.com/listeng/wps2md/tree/c4ae028156e44ed8b57ef879dc7bd1d14750c0f1) | `c4ae028156e44ed8b57ef879dc7bd1d14750c0f1` | [MIT](https://github.com/listeng/wps2md/blob/c4ae028156e44ed8b57ef879dc7bd1d14750c0f1/LICENSE) | Paragraph-property, table and list references. Its contiguous-text assumptions cannot replace the existing logical piece-table decoder. |
| [JSDoc](https://github.com/Alpaq92/JSDoc/tree/821695a884e0c0bb8592a635d9524bb3e116cd67) | `821695a884e0c0bb8592a635d9524bb3e116cd67` | [0BSD](https://github.com/Alpaq92/JSDoc/blob/821695a884e0c0bb8592a635d9524bb3e116cd67/LICENSE) | The most useful reference for structured binary Word parsing: formatting pages, styles, paragraph/run properties, tables and sections. |

## JSDoc

The reviewed [`src/docToText.js`](https://github.com/Alpaq92/JSDoc/blob/821695a884e0c0bb8592a635d9524bb3e116cd67/src/docToText.js)
contains a real FIB/CLX reader, CHPX/PAPX formatting-page readers, stylesheet
inheritance, fonts, table/section properties and richer document models. Its
public APIs include text, story text, styled HTML, a paragraph/run model and
embedded PNG/JPEG extraction. This is substantially more useful to a portable
DOC importer than scanning for printable bytes or invoking an installed Word
application.

It is still a partial implementation, not a compatibility certificate for
arbitrary Word documents. In particular, its ordinary reading view accepts
tracked changes by keeping insertions and dropping deletions. CrispCloud's
structured conversion must instead retain the supported insertion/deletion
state in its model and generated WordprocessingML, and explicitly disclose
revision features it does not reconstruct. The JavaScript writer is a binary
DOC writer; it does not itself supply a DOCX converter.

The repository and its tests are useful implementation references under 0BSD.
CrispCloud does not add a JavaScript runtime dependency, execute the demo or
bundle its binary-DOC writer. The Dart parser and the existing OPC writer are
the application implementation; source provenance belongs alongside any
adapted parsing code.

## wps2md

The reviewed [`src/wps2md/core.py`](https://github.com/listeng/wps2md/blob/c4ae028156e44ed8b57ef879dc7bd1d14750c0f1/src/wps2md/core.py)
has more functionality than its README currently describes: it reads paragraph
style indices and table/list flags and emits basic Markdown tables and lists.
It requires Python and `olefile`; neither is added to CrispCloud.

Several implementation choices prevent using it as a general DOC decoder:

- It reads contiguous `fcMin..fcMac` text and does not interpret the CLX piece
  table. A normally edited DOC can contain text pieces in a different physical
  order, with compressed and UTF-16 pieces mixed together.
- It prefers `0Table` when present instead of selecting the table specified by
  the FIB's `fWhichTblStm` flag.
- Paragraph text is decoded as UTF-16 in physical formatting-page order.
- Its zero-byte PAPX length variant omits the final two property bytes. The
  independent CrispCloud fixture exercises that boundary.
- List rendering uses simplified counters, and Markdown tables treat the first
  row as a header. Those decisions do not establish original Word numbering or
  header-row semantics.

The useful lesson is how paragraph properties lead to headings, rows, cells
and list membership. CrispCloud retains logical CP-to-FC mapping and reads
formatting against the actual selected pieces. It does not infer table headers
or list start values from Markdown presentation rules. These findings do not
establish support for every WPS format or justify accepting another format
merely because it uses an OLE container.

## legacy-doc-recover

This is an experimental damaged-file text recovery tool. The reviewed
[`recover.py`](https://github.com/graemewilsonnz/legacy-doc-recover/blob/aa7cc91e62be02db9374f0979ef638ee7fde5767/src/legacy_doc_recover/recover.py)
and [`cfb.py`](https://github.com/graemewilsonnz/legacy-doc-recover/blob/aa7cc91e62be02db9374f0979ef638ee7fde5767/src/legacy_doc_recover/cfb.py)
can tolerate damaged metadata, fall back to contiguous sectors and perform raw
text scanning. Those are recovery-policy choices, not evidence that the
result is the current logical document. In an ordinary viewer/converter they
could expose stale, deleted or unrelated embedded text.

The reviewed [`text.py`](https://github.com/graemewilsonnz/legacy-doc-recover/blob/aa7cc91e62be02db9374f0979ef638ee7fde5767/src/legacy_doc_recover/text.py)
also selects compressed-text code pages from a language ID, decodes UTF-16
pieces separately with replacement on errors, and removes field delimiters
without distinguishing instructions from results. CrispCloud keeps the
documented compressed-character mapping, preserves UTF-16 code units across
piece boundaries and shows stored field results without instruction text.

No recovery fallback is enabled by this extension. A future explicit recovery
tool would need separate user-facing confidence/provenance and output, and
must not silently supply the content used for ordinary DOCX conversion.

## Authoritative format references

Implementation and independent fixtures are checked against Microsoft's
published structures rather than treating another parser as the specification:

- [MS-DOC formatting](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/fdd9ab7e-a3cb-4014-ab9b-b507ddfd23d2).
- [MS-DOC document parts and CP ranges](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5f0c4329-8718-4d67-8cc7-60d8968c5127).
- [MS-DOC table overview](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5b45f0e7-7760-4fdb-af88-0146de2feb4c).
- [MS-DOC section properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e).
- [WordprocessingML inserted runs](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.insertedrun)
  and [deleted runs](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.deletedrun).

The installed Microsoft Word/LibreOffice conversion route remains available
for documents requiring broader preservation. The built-in conversion creates
a separate derivative and describes its partial support before saving.
