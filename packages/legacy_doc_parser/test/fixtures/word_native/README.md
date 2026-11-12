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

Run `tool/verify_installed_office_converter.dart` with an installed `soffice`
path to exercise the production converter for both DOCX and DOCM. This is a
structural acceptance case, not a universal layout-fidelity certification or
a macro-execution test. Converted files remain temporary and are deleted.

## Linked textbox regression

`linked-textboxes.doc` is an independently native-exported binary of the
authored small-box case in `test/support/linked_textbox_fixture.dart`. It has
eight unique text markers in one story flowing through two fixed frames.
It was saved through installed LibreOfficeDev 26.8.0.0.alpha0,
revision `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, using the isolated-profile
`MS Word 97` filter in `tool/fidelity/textbox_reflow.py`.

SHA-256: `04c12a92a08341111d0bcc29075503e3e9e0642e4b52af3deb256df902f37119`.

The native writer stores `FTXBXS.cTxbx=1` despite two explicit, contiguous
OfficeArtClientTextbox indices and a matching `hspNext` link. The parser
discloses its narrow recovery as `recoveredTextboxChainLength` and retains
the original declared count separately. The fixture is not an exact-layout
golden. The native probe also checks marker positions and resize-driven
reflow so preserving only the link XML cannot pass its native gate.

## Separate header textbox occurrences

`header-textbox-duplicate-chain.doc` retains the original native import failure
and its independently authored source. The original red receipt is unchanged.
`header-textbox-first-enabled.doc` is the exact activation control from the
sealed header-alias archive: only the first-page-header setting is enabled,
leaving the textbox range and drawing identities intact. Its adjacent JSON
records the source, output and archive hashes. Both are required native corpus
and SDK cases; neither is an automatically adopted layout golden.

See [the header alias contract](../../../doc/header-textbox-aliases.md) for the
narrow recovery, seven native paragraph controls and reproduction commands.
