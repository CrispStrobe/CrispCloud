# Active footnote separator converter fixtures

These six ODT files are untouched outputs from LibreOfficeDev
26.8.0.0.alpha0 (`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`).
The manifest binds each exact byte stream to its producer, preset and save.
They are synthetic Zotero documents with two active citations: one in the body
and one in an authored footnote. They preserve unknown item, citation and
document-preference metadata.

The source generator is `tool/zotero/footnote_separator_acceptance.dart`.
For each custom, zero-gap and hidden-rule preset, the external converter saved
the source as ODT. Quds then reopened it, performed a controlled Zotero refresh,
and completed two native DOCX/ODT cycles. LibreOffice saved that result again.
Neither set of returned converter files was edited afterward.

The regression reopens every retained file, verifies its SHA-256, checks the
separator geometry and citation ownership, performs another controlled refresh,
and follows two further DOCX/ODT cycles. This is separate from an installed
Zotero plugin or Microsoft Word session. The source, all commands, PDFs, images
and failed custom-DOCX converter probes are retained in the
[work record](../../../../../../docs/validation/zotero-footnote-separators-20261121/README.md).
