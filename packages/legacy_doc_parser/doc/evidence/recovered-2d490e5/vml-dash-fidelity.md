# VML dash keyword interoperability

The native OfficeArt review on 2026-11-12 found that a dotted rectangle in
`test/fixtures/fidelity/officeart-shapes.docx` became solid after the fixture's
native DOC bridge was converted by this package. The source dash enum was
retained, but the generated VML used `dashstyle="shortDot"`.

The writer now emits lowercase VML dash keywords, separately from DrawingML's
case-sensitive names such as `sysDot` and `dashDot`. Microsoft's
[VML stroke examples](https://learn.microsoft.com/en-us/windows/win32/vml/web-workshop---how-to-use-vml-on-web-pages-----stroke--element)
and [Open XML SDK stroke example](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.vml.stroke?view=openxml-3.0.1)
use lowercase VML tokens. The legacy
[DashStyle reference](https://learn.microsoft.com/en-us/windows/win32/vml/msdn-online-vml-dashstyle-attribute)
lists display names in title case but also serializes its example in lowercase.
The writer follows the lowercase XML form rather than those display names.

## Controlled native check

The existing final corpus output from package `b03747396878518d0d623599baf9b376df776e3d`
was copied, changing only the single `shortDot` attribute to `shortdot` in
`word/document.xml`. Rendering both files with LibreOfficeDev
`26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, the same fonts and 72-DPI
RGB rasterization restored the dotted outline. The only changed pixels were
inside the rectangle's bounds `(65, 129)–(187, 213)`. Text positions, the ellipse,
and the cubic shape were unchanged.
Converting the same DOC through the corrected source produced ZIP members
identical to the controlled mutation and the same raster hash.

| Input or output | SHA-256 |
| --- | --- |
| Authored source DOCX | `f95be8f8d4283f7d2fd4cfc178cbd108300ea99b1be9a14ab1dd56bf1897f53b` |
| Native DOC bridge | `2f9942934f293acf7ac3df6daada81c0e4799e0433a071166a8ab193b1846b6d` |
| Solid-outline raster before correction | `dce7d4ba6a14cf9f2ac2821f9725bd603992d2bb4b4e3c48d79b77d39ac17e5f` |
| Dotted-outline raster after controlled mutation | `c546d486eb9990145679e6984f58f927c8401b7b00314046a7d3fd25e88ff220` |

This is an outline-style correction, not a claim of exact native raster fidelity.
The corrected raster still differs from the DOC source; LibreOffice's own
DOC-to-DOCX output also differs. No Microsoft Word runtime was available.
The regression test constructs binary OfficeArt records for all 11 dash enums,
then independently checks the emitted VML and DrawingML attributes. It also
parses every generated XML part, although schema well-formedness alone cannot
detect this error because VML `dashstyle` is a string.
