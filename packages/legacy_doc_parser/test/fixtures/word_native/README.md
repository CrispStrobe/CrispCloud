# Installed Office conversion fixture

`formatting.doc` is an authored Word 97–2003 binary fixture, generated from
CrispCloud-owned text and a small drawing by
`test/support/create_installed_office_fixture.py`. It contains Unicode body
text, bold/color/font-size and italic formatting, a table, an embedded PNG,
a header, a footer and a footnote. It has no executable macros or external links.

The initial binary was exported by installed LibreOfficeDev 26.8.0.0.alpha0.
It is deliberately small and carries no third-party document content. The
builder requires an existing LibreOffice executable, python-docx and Pillow;
none is fetched by the script or by the application.

`linked-textboxes.doc` is another package-authored input, exported from the
independent `test/fixtures/fidelity/linked-textboxes.docx` by the same installed
LibreOfficeDev version. It has two linked boxes with different inner margins
and 24 numbered words. The stale declared chain count in this native file is
intentional regression evidence; see `doc/textbox-fidelity.md`.

Both authored binaries are covered by the package's MPL-2.0 license. They have
no third-party document content. The new textbox OOXML generator is
`tool/fidelity/authored_cases.py`; the original formatting fixture's builder
belongs to CrispCloud, rather than this standalone package.

Run `tool/fidelity/run.py` with already installed `soffice` and Dart paths to
measure native rendering, DOCX conversion and a second binary import. Inputs
are hash-pinned in `tool/fidelity/corpus.json` and never overwritten. Results
are written to a new output directory; these fixtures are not a universal
layout-fidelity certification or a macro-execution test.

`linked-textboxes-compact.doc` retains the independently authored eight-marker
textbox input from the parallel preservation branch (`71025ea`). Its distinct
bytes and regression remain available alongside the 24-word reflow probe. The
old identical filename was renamed during integration so neither input is lost.

`list-continue.doc` and `list-restart.doc` are independently assembled binary
inputs from `test/support/list_sequence_fixture.dart`, not converter output.
They retain the five-item shared-LSID continuation and six-item restart/resume
controls, so the native corpus checks editable labels after future changes.
Their original native checks are recorded in `doc/list-sequence-native-check.json`.

`officeart-terminal-mark.doc` is the unchanged native binary export of
`test/fixtures/fidelity/officeart-shapes.docx`. Its final CR is referenced by
CLX/PAPX but omitted from the final CHPX range. The fixture retains three
authored shapes and pins this narrow interoperability regression; its hash,
provenance and strict recovery limits are in `doc/terminal-mark-formatting.md`.
