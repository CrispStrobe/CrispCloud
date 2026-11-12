# Native table-style PAPX framing evidence

During reconciliation of the parallel parser branch, its table-style PAPX
reader removed the two-byte `istd` prefix. The existing reader retained it.
An independent binary document supports retaining the existing behavior:

- Source: Apache POI `test-data/document/simple-table2.doc`, retrieved from
  [the upstream fixture](https://github.com/apache/poi/blob/trunk/test-data/document/simple-table2.doc).
- Git blob SHA: `1a5ff5f7109fcc8352530ace3d8c0b2c3bcd75aa`.
- SHA-256: `8aea59b70c19a150d657065f254c5e10db08a51518d1c7fce33fc8f75ab6c6cc`.
- Retained bytes: `test/fixtures/word_native/poi-simple-table2.doc` (unmodified).
- Upstream license and notices are retained in
  `third_party/apache-poi-fixtures-LICENSE.txt` and
  `third_party/apache-poi-fixtures-NOTICE.txt`.

Reading the FIB-selected stylesheet, its two table styles each have three UPX
records. Table Normal (style 11) has PAPX payload `0b 00`; Table Grid (style 15)
has PAPX payload `0f 00`. These are the corresponding style indices, with no
following paragraph SPRMs. They cannot be interpreted as a complete SPRM array.
The regression test inspects the source bytes independently of the production
style decoder and also verifies that both native table-style identities parse.

Microsoft's [UpxPapx definition](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/659f448a-473a-44c6-8b69-a25984af3645)
labels `istd` optional and requires a present index to equal the current style.
That wording does not justify assuming it is always absent from table styles.
This document demonstrates a present prefix; it does not establish the presence
rule for every producer and format version. The reconciliation therefore keeps
the existing table PAPX framing and does not replace it with the recovered
branch's unconditional raw-SPRM interpretation.
