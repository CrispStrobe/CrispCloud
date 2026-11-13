# Independent DOC and DOCX reader probes

This is a retained research checkpoint, not a new fidelity pass. It records actual
Antiword and Pandoc executions against exact files from the sealed
[`native-corpus-c5ff75e7`](../native-corpus-c5ff75e7/README.md) acceptance corpus.
The parser observations therefore describe runtime
`c5ff75e76163d9abbdd44a9f2a7c5ad210929289`; the research was prepared from repository
head `43027f9ddb626a4f8fccbef1c41c7f2ea9fccf47`. No source fixture was rewritten to
agree with an importer. The source archive hash and every selected member hash
are retained in `probe-inputs.json` inside the archive.

## Tools actually run

| Implementation | Actual version/source | Paths exercised | What it can establish here |
| --- | --- | --- | --- |
| Antiword | 0.37; `grobian/antiword` commit `82515aad16ceedc1061ae3777acb99c90d3d3e08` | Binary DOC → UTF-8 text and DocBook XML | Independent C implementation reads body text, table cells and note content. Its output is a lossy view, not a layout or complete story oracle. |
| Pandoc | Installed executable 3.1.11.1, SHA-256 `0336f5db0c5db91d3b7e29e3adc226bebd76d074bf28a907e50fc148bded3e8b` | DOCX → JSON AST / Markdown; two DOCX → DOCX → AST probes | An independent DOCX semantic projection. This executable has no binary DOC input or output format. AST equality does not establish Office package fidelity. |
| LibreOffice | Existing retained native corpus, separately versioned there | DOCX → actual binary DOC → native DOCX | Native import/export reference already used by the corpus. New probes did not rerun its conversions. |

Antiword was built in the workspace, without installation or edits to its tracked
source, using `make -f Makefile.Linux -j2 antiword` and the recorded
`GLOBAL_RESOURCES_DIR`. Its 258,496-byte executable has SHA-256
`c56e8a8bf5423338d7913d7864331a40a3b5ed60354b64a209d377cfe8cfbcdf`.
All 178 tracked source/resource files are retained, with their exact Git blob IDs,
along with compiler identity, build command, complete stdout/stderr and mapping
resources. The generated executable and object files are omitted.

The working command was `ANTIWORDHOME=<source>/Resources <source>/antiword -m
UTF-8.txt -t -w 0 <source.doc>`; the DocBook variant uses `-x db` instead of
`-t -w 0`. The exact absolute commands, environments and input hashes are in the
command receipts.

Pandoc initially failed under a 512 MiB virtual-address-space limit. Those failed
attempts remain in `outputs/`. Corrected calls in `outputs-pandoc/` use
`+RTS -N1 -M256m -K32m -RTS`, a 20-second CPU limit and 30-second wall limit,
without an address-space limit. All 16 selected DOCX views then produced AST and
Markdown successfully. Two authored DOCX files also completed a Pandoc DOCX save
and re-import. The initial failures have not been relabeled as successes.

## Observed discrimination and limitations

The six cases are `word`, `table-borders`, `note-markers`, `bookmarks`,
`poi-simple-table2`, and `header-textbox-alias`.

* Antiword succeeded on the first five in both text and DocBook modes. It refused
  the small `header-textbox-alias` DOC with its own "text stream ... too small"
  diagnostic. Both failed attempts are retained. It omitted header/footer stories
  in these probes, rendered body note references as `[?]`, and did not provide a
  complete bookmark or link model. These are limits of this oracle.
* The `word` authored and native DOCX each yield two Pandoc AST `Link` nodes
  (body and footnote). The parser DOCX yields zero. Direct OPC inspection also
  finds no parser hyperlink relationships or field instructions, while the
  authored/native packages retain external body, note and header targets.
  `hyperlink-source.json` records four literal binary DOC HYPERLINK fields and
  their matching CFData/CPicLocation HFD URL monikers: body, footnote, normal
  header and first header. This is a concrete parser investigation candidate,
  independently visible without a rendering comparison.
* The `note-markers` Pandoc DOCX save has **exactly equal before/after ASTs**, yet
  six source footnotes plus three endnotes become nine footnotes and zero
  endnotes. Thus an AST equality check alone can silently miss a substantive
  Office distinction. The `word` Pandoc save also removes header/footer parts and
  changes its endnote to a footnote.
* The table counts differ across paths. In `note-markers`, the parser retains a
  note table that native LibreOffice flattens. In `table-borders`, authored body
  tables are already merged by the binary bridge, and the native output flattens
  a note table. These observations require source/DOC/output attribution; a
  majority vote between semantic readers is not sufficient to blame the parser.

## Practical next references

| Candidate | Primary source and independence | Practical scope / caveat |
| --- | --- | --- |
| AbiWord / wv | [AbiWord source](https://github.com/AbiWord/abiword/tree/6940426ea7fd3810f1aa5477fa93c2d4278dea7d); [wv project](https://wvware.sourceforge.net/) | AbiWord's binary DOC importer calls wv. They are one importer family, not two independent votes. Local wv dependencies (`libgsf`, GLib and libxml2 development files) are absent, so neither was run here. wv source commit is `4ccc6a152e42668f65a659e2a9a31499b0b04250`. |
| AbiWord DOC export | Exact pinned `ie_impexp_Register.cpp`, `ie_exp_RTF.cpp`, importer and build-list excerpts are retained | The active `.doc` exporter is an RTF compatibility wrapper. Its unbuilt `ie_exp_MsWord_97.cpp` source is incomplete. Any roundtrip harness must inspect output magic and must reject RTF renamed `.doc` as a binary DOC edge. |
| LibreOffice regression fixtures | [Writer import/export test framework](https://github.com/LibreOffice/core/blob/master/sw/qa/extras/README) | Candidate native DOC fixtures include `changes-in-footnote.doc` (leading-tab/track-change predicate) and `ooo92948-1.doc` (header anchored table). Retain the exact fixture, test commit and asserted property; these are not automatically Word-rendered pixel goldens. These new fixtures have not been downloaded or executed in this checkpoint. |
| Apache POI HWPF | [Official component](https://poi.apache.org/components/document/); [HWPFDocument API](https://poi.apache.org/apidocs/6.0/org/apache/poi/hwpf/HWPFDocument.html) | Separate Java DOC implementation with story/table/field access and limited write support. The existing `SimpleTable2.doc` native fixture is already included in this probe. No Java SDK/Maven toolchain was available to execute HWPF here. |
| Catdoc | [Author's project page](https://www.wagner.pp.ru/~vitus/software/catdoc/) | Another DOC text extractor; limited formatting/table model. Not installed or run. It would add text decoding discrimination, not a document-layout oracle. |
| Mammoth | [Maintainer's README](https://github.com/mwilliamson/mammoth.js/blob/master/README.md) | Independent DOCX-to-semantic-HTML view with notes/tables/textboxes, intentionally omitting several layout details. Not installed or run. |

Pandoc's [manual](https://pandoc.org/MANUAL.html) explicitly describes conversion
through its less expressive intermediate representation. The decisive loss
control here is the actual retained note-type collapse, rather than a claim
based solely on documentation. The Antiword source is a maintained fork of the
original 0.37 distribution; this receipt does not call the fork the original
author's website.

## Retention and verification

Run `python doc/evidence/independent-readers-20261113/verify.py` from the repository.
The verifier checks the exact archive/member inventory, source and command
input/output bindings, all successful Pandoc results, both retained Antiword
rejections, the differing link counts and the AST-equal note-type loss control.
It also recomputes every retained Antiword source Git blob ID. No converter,
external link or active document object is executed by the verifier.

`records.tar.xz` preserves complete probe logs, command receipts, all selected
source/native/parser packages, AST/Markdown/DocBook/text outputs, failed attempts,
runner/inspection source, Antiword tracked source/resources and pinned source
reference excerpts. `manifest.json` records every byte. The archive is a frozen
research observation; later parser fixes must retain this before-state.
