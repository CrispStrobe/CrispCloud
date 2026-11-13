# Font-specific symbol glyphs

Binary `sprmCSymbol` was previously unrecognized. A valid symbol anchor stored
as U+0028 was consequently exported as a literal opening parenthesis even when
the binary font index and glyph code identified a different glyph. The parser
now retains a typed `LegacyWordSymbol` on the affected run and exports the exact
font/code pair as `w:sym`.

## Supported source contract

[MS-DOC Character Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18)
defines `sprmCSymbol` (`0x6A09`) as a symbol designation. Its
[CSymbolOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d950b816-1794-4adf-bc44-1f1be8027f9e)
contains an unsigned 16-bit font-table index and 16-bit character operand.
The documented symbol anchor is U+0028. WordprocessingML's
[SymbolChar](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.symbolchar)
selects a glyph from its own `w:font`/`w:char` operands independently of run fonts.

The implementation resolves the source font index without substituting an
ordinary run font. Missing/invalid indices, an empty font name, malformed
operands and invalid public-model metadata fail closed. The underlying ordinary
run formatting and original source CPs remain available. Glyph runs contain one
U+FFFC opaque position per occurrence; they do not invent a Unicode character
equivalent for a font-specific glyph. DOCX receives the exact hexadecimal glyph
operand. HTML uses the declared glyph font and retains a `data-word-symbol`
attribute; operands that cannot form standalone HTML text keep an opaque position.

Ordinary parentheses and existing private-use text with ordinary font formatting
remain separate representations. This change does not reinterpret them merely
to match a native renderer's DOCX serialization.

## Ordering and explicit qualifications

A symbol designation works without a separate `CFSpec=true` operand and after an
earlier `CFSpec=false`. The independent
[Apache POI character-property implementation](https://github.com/apache/poi/blob/e0658769cb7f7da25ec09178805e04069dedc6ed/poi-scratchpad/src/main/java/org/apache/poi/hwpf/sprm/CharacterSprmUncompressor.java)
also sets the special-character flag when applying `CSymbol`; this corroborates
the designation behavior. Its fetched source blob is
`f253e7020cf6b2a8973a0f14a17086d7f0c9b8cc`.

A **later** explicit `CFSpec=false` remains qualified. The current MS-DOC wording
does not resolve that contradictory combination as explicitly as the ordinary
designation. POI applies the later flag, while the pinned
[LibreOffice symbol reader](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8par6.cxx)
maintains a separate symbol state and renders the glyph in the retained control.
The parser preserves the underlying literal source text, reports
`unsupportedFormatting`/`partialFormatting`, and retains the original binary
evidence. This is not a claim of correct ordinary-literal or native parity for
that unresolved combination.

Other limits remain explicit: symbol designation on a non-U+0028 character,
glyph content inside a nested field's instruction result, and a prior glyph
change that cannot be represented by `rPrChange`. Current glyph content is not
silently replaced by a guessed historical glyph. Hidden and tracked glyphs keep
their visibility and insertion/deletion wrappers; changes are not accepted.

## Independent control and observed result

The committed [binary control provenance](../test/fixtures/word_native/symbol-source-control.provenance.json)
identifies an **authored binary control**, not a Word-authored source corpus file.
The untouched parent is a LibreOffice export of the independently authored
[`symbol-glyphs.docx`](../test/fixtures/fidelity/semantic-contracts/symbol-glyphs.docx).
The patch replaces exactly one private-use text occurrence with U+0028 plus
`CSymbol(fontIndex=1, character=F061)`, rebuilds its referenced CHPX page, and
retains every other stream byte-for-byte. The parent, exact operands and stream
hashes are retained in the receipt.

Native DOC import selects `Symbol/F061`; the former parser emitted `(`. With the
fix, that first line has the same extracted text, word box and decoded RGB pixels
as the native DOC reference. Its mismatch changes from **92 pixels to 0**.
The whole-page mismatch changes from **1,300 to 1,208 pixels**. Pixels below the
first line and all later word boxes are identical before/after the fix.

At the CSymbol-only checkpoint, the remaining whole-page maximum word drift was
**2.7 pt**, associated with the unchanged Wingdings private-use/font control.
That observation remains in the original evidence. The subsequent
[source font charset fix](font-charsets.md) traced and removed this independent
omission without changing the private-use text. Stable repeats alone had not
established its first-export correctness.
Two actual DOCX→DOC→parser import repeats are raster-exact to their own binary
inputs with **0 pt** drift, while retaining the same residual to the original
source at that checkpoint. Full-page raster equality was **not** claimed for the
CSymbol-only change; the separate charset proof records the later exact result.

## Checks

- Ten new regression methods cover typed operands, CPs, adjacent/repeated text,
  inherited/direct properties, explicit flags, ordinary PUA text, hidden content,
  insertion/deletion wrappers, bookmark event splitting, malformed operands,
  invalid font indices, public-model validation and glyph-history qualification.
- The four targeted Dart suites passed **41 tests**; static analysis passed.
- The separate VM and compiled-JavaScript module passed **9 cases / 18 checks**.
  Its check uses explicit exceptions and executes the actual parser/converter.
- Two required schema cases (`symbols/plain`, `symbols/deleted`) produced real
  `w:sym` output and passed the retained Open XML SDK 3.3.0 validator with zero
  errors. This bounded check reused the already-built validator; the full
  combined acceptance gate will build and validate its complete corpus separately.

The initial test fixture mistakenly used compressed text with UTF-16 FC ranges;
that authoring error was corrected to an explicit uncompressed piece. The native
binary counterexample and its original parser failure were retained unchanged.
