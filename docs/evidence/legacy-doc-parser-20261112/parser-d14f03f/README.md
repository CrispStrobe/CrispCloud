# Final app integration at parser d14f03f

This receipt binds parser `d14f03f198a9735c660d0f8ae18ba6fc316fcf25` and Quds `78ed85f5fd19d44f672dee11420fed261c974f4a` to the final app mirror.
All 476 parser manifest entries and all
897 Office-managed files verify against their exact
Git source bytes and modes. The separate 279-file ebook
checkout also verifies; its native conversion engine is outside this Word gate.

The app passes **142 Flutter tests across 17 Word conversion/UI suites**,
including attached-content inspection, routing, review, source-bound copy and
localized dialogs. All **101 Python sync/render harness tests** pass. Production
DOC/RTF/PPT/MSG JavaScript acceptance and installed-Office checks for built-in
DOCX and native DOCX/DOCM pass. Native acceptance includes independent PDF
text/images, headers, footers and notes, output inspection and unchanged source
and prepared-package bytes. Complete logs are retained losslessly with hashes.

App implementation/tests and parser/engine/editor runtime bytes equal public
base `b6bc7b13e56fe6bbdeafc1c4f84d405e0a6226c5`. The final pin changes only test, evidence, documentation and
metadata files. Temporary test hooks restored the release pubspec byte for byte;
the dependency lock and existing non-digest policy decisions are unchanged.
`summary.json` records the tested configuration and exact source-binding hashes.

## Upstream fidelity results and limits

The canonical integrated parser gate passes 809 Dart tests, 162 Python tests,
51 JavaScript media checks and all 218 required independent SDK outputs. A
subsequent test-only regression passes 13 focused tests covering all 24 emitted
textbox-table manifests. Quds separately records the complete engine gate and
its full workspace parser run.

The retained native run completes all 24 initial imports and 72 repeat imports;
all initial page counts agree, six initial RGB/text/word-geometry comparisons
are exact, and both reviewed source goldens match. The earlier first-enabled
header import failure is closed for these exact source bytes. All 288 emitted
DOC/DOCX files and prior failed receipts remain available in the package.

Every strict structural comparison still reports differences. Two additional
native header/table controls remain unsupported and are retained separately.
Exact pagination, arbitrary OfficeArt/effects, complete metafiles, all table/list
interactions, general textbox flow, nonempty ink editing and full revision
semantics are not certified. The native renderer was pinned LibreOffice;
Microsoft Word was not executed.
