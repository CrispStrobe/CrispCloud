# Bundled font notices and provenance

The PDF editor, `pdf_cos`, `pdf_document`, `pdf_graphics`, and
`dart_pdf_editor_assets` package code is Apache-2.0. The font binaries have
their own licenses; they are not all MIT, BSD, or Apache licensed.

| Font families | License |
| --- | --- |
| DejaVu Sans, Serif, Sans Mono | Bitstream Vera; DejaVu changes are public domain; the Sans face also carries the Arev/Tavmjong Bah notice. |
| Fira Sans, Spectral, Lobster, Carlito | SIL Open Font License 1.1, including each font's copyright and reserved-name conditions. |
| TeX Gyre Heros, Termes, Cursor, Adventor | GUST Font License, referring to the LaTeX Project Public License 1.3c or later. |
| The app's existing Roboto and Roboto Mono files | Apache License 2.0. |
| The app's existing Material Icons notice | Creative Commons Attribution 4.0 International, as recorded in `assets/fonts/MaterialIcons_LICENSE.txt`. |

These font licenses retain their own redistribution and modification
conditions. They do not change the license labels of the separate PDF package
code. No font files are modified by this notice-distribution change.

## Exact sources

The six `*-LICENSE.txt` notices named DejaVu, FiraSans, Spectral, Lobster,
Carlito, and TeXGyre were copied without alteration from:

https://github.com/ben-milanko/dart-pdf/tree/87adaa022c5ed6b22ca3232b6cae4a03e8389e98/packages/dart_pdf_editor_assets/assets/fonts

That is the source commit for `dart_pdf_editor_assets` 14.0.0. The three
`DejaVu*-font-metadata-LICENSE.txt` files preserve each bundled font's complete
name-table ID 13 verbatim. The font metadata is used for the displayed DejaVu
license entries because it includes the applicable font notices. The copied
Debian copyright file also includes a GPL-2+ stanza specifically for
`debian/*` packaging files; that stanza does not license the bundled fonts.

`FONT-COPYRIGHTS.txt` preserves name-table ID 0 copyright strings from every
bundled PDF font and the existing app font binaries. This also preserves any
copyright year differences between a font's metadata and its accompanying
notice. Existing Roboto, Roboto Mono, and Material Icons license text files
are bundled directly from `assets/fonts` without alteration.

The complete LPPL 1.3c text was obtained verbatim from the LaTeX project's
official copy (version 1.3c, 2008-05-04):

https://www.latex-project.org/lppl/lppl-1-3c.txt

Original font projects and complete font distributions:

- DejaVu: https://dejavu-fonts.github.io/
- Fira: https://github.com/mozilla/Fira
- Spectral: https://github.com/productiontype/Spectral
- Lobster: https://github.com/impallari/The-Lobster-Font
- Carlito: https://github.com/googlefonts/carlito
- TeX Gyre: https://www.gust.org.pl/projects/e-foundry/tex-gyre

The application bundles these notices and exposes them through its existing
About / Licenses page using `registerPdfFontLicenses`. Package-level Apache
license notices continue to be collected by Flutter separately.
