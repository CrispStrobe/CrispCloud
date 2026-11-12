# Source kerning and native text widths

`LegacyWordCharacterStyle.kerningThresholdHalfPoints` retains the resolved
`sprmCHpsKern` choice from MS-DOC. Zero disables kerning and is the binary
format's default; positive thresholds are 1–3276 half-points. Negative,
out-of-range and truncated operands are rejected. Paragraph/character style
inheritance, sequential `CIstd`/`CPlain` resets, piece properties and previous
formatting-revision snapshots all retain this property.

The DOCX writer emits the threshold in `w:kern` for ordinary runs, paragraph
marks, numbering markers and previous `rPrChange` formatting. Explicit zero
matches the observed LibreOffice native exporter and preserves the source's
disabled choice in that consumer. Microsoft's [MS-DOC character-property
specification](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18)
explicitly defines zero as disabled. Its [OOXML Kern documentation](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.kern?view=openxml-3.0.1)
describes threshold and style-inheritance behavior without spelling out a
special zero case. Microsoft Word native validation was not available here;
this is not a claim that every consumer interprets zero identically.

The HTML preview uses `font-kerning:none` when disabled or below a known
threshold, and `normal` when a known font size reaches the threshold. A positive
threshold without a resolved font size uses `auto` and carries
`data-word-kerning="threshold-unresolved"` plus the half-point threshold. Browser
font shaping remains an approximation; no Word pagination is implied. Hidden
runs and private field content remain suppressed.

## Measured linked-textbox correction

The authored `word_native/linked-textboxes.doc` fixture contains 24 numbered
words across two linked boxes. Before this change, all body words and box line
starts matched the native source, but missing kerning-off formatting shortened
textbox word widths; accumulated drift reached **1.74 points**. Adding only five
`w:kern w:val="0"` elements to a controlled DOCX copy removed that drift. The
actual parser/converter implementation then matched **all 36 word bounding
boxes**, including the 24 textbox words, against the independent source-DOC
snapshot with **0.00-point maximum drift**.

The [empirical receipt](../test/fixtures/word_native/kerning-layout-receipt.json)
pins the source, controlled change, native outputs, font environment and
LibreOffice revision `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. The comparison uses
one page rendered by that installed build with Liberation Serif. It does not
establish raster equality or universal layout fidelity. Existing source-chain
recovery warnings and unrelated conversion limitations remain visible.

`test/legacy_word_kerning_test.dart` independently exercises binary bounds,
inheritance/reset order, piece precedence, noncoalescing different thresholds,
current/previous native XML, list markers, safe-preview behavior and this
authored native source.
