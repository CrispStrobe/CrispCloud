# Independent Word binary position fixtures

The following files are unmodified public LibreOffice QA fixtures, renamed
only to identify their purpose here. Credit belongs to the LibreOffice
contributors. The upstream Mozilla Public License 2.0 is reproduced in
`COPYING.LibreOffice`; upstream source and licensing are available from
https://github.com/LibreOffice/core/tree/9a3be2502bf7762400fd0b655b6e42714cf2bb36.

| Local file | Upstream source path | Git blob SHA |
| --- | --- | --- |
| word14-margin-origin.doc | sw/qa/extras/ww8export/data/tdf101826_xattrTextBoxFill.doc | 206f4830958aac1e3fa429b74edd4697d5876f13 |
| word16-page-origin.doc | sw/qa/extras/ww8import/data/tdf124601.doc | a07bae1f01494e746f56591a7afaf20ab8c4c958 |

These files identify Microsoft Office Word 14.0 and 16.0 in their own property
sets. They support the raw position-enum investigation; they are not evidence
that Microsoft Word was run in this environment. The Word 14 source exercises the explicitly diagnosed recovery of its global
textbox spare-range sentinel. SHA256 hashes and exact
raw-property observations are recorded in
`doc/evidence/officeart-position-sources.json`.

`word16-page-origin-lo-blip-count.doc` is a derived native round-trip specimen,
not an unmodified Word-authored file. Its original source is
`word16-page-origin.doc` above. The producing parser/native stages, hashes and
constant BStore-count defect are documented in
`doc/blip-store-count-recovery.md`.
