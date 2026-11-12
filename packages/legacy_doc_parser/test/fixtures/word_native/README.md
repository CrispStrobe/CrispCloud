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
