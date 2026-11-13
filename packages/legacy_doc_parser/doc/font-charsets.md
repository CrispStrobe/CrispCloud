# Source font charsets

Binary FFN font definitions carry a charset as well as a font name. The parser
previously retained only the name and emitted no WordprocessingML font table.
That omission changed the interpretation/substitution of an ordinary Wingdings
private-use run even after explicit `CSymbol` glyph handling was corrected.

The parser now exposes every FFN source index, primary name and unsigned charset
byte through `LegacyWordDocument.fontTable`. The converter writes qualified
definitions to `word/fontTable.xml` with a normal font-table relationship and
content type. Text, source CPs, run font names and existing `w:sym` operands are
unchanged. No Unicode or private-use glyph mapping is introduced.

## Source contract and bounded projection

[MS-DOC FFN](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/ff407d64-3478-4b56-9b98-6dbcfc66a4ae)
defines `chs` as the font's charset byte. Its values include ANSI `0`, default
`1`, symbol `2`, and the listed script/code-page charsets. WordprocessingML's
[FontCharSet](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.fontcharset?view=openxml-3.0.1)
represents this property as `w:charset`. The property informs font substitution;
omitting it does not preserve an explicitly stored symbol charset.

The converter applies these rules:

| Source definitions for a font name | Output and qualification |
| --- | --- |
| One recognized charset, including repeated identical entries | Emit the exact byte as two hexadecimal digits. |
| Exactly `DEFAULT_CHARSET=1` and `SYMBOL_CHARSET=2` | Emit the explicitly stored symbol charset. Retain the default alias and the qualification in evidence. This is the independently verified Symbol/Wingdings alias case. |
| Any other mixture of different charsets | Retain the operands and an ambiguity explanation; do not pick a charset. |
| An unrecognized charset byte | Retain it as source evidence; do not infer a known code page. |
| A structurally retained FFN with an empty primary name | Keep its index/charset and an explicit qualification, without emitting an unnamed font. |
| Case-variant names that collapse to the same case-insensitive group | Retain the separate source definitions and omit that group's font-table entry. |
| No source font metadata | Do not invent a font table. |

`DEFAULT_CHARSET` is locale-dependent, as defined by the primary
[CharacterSet enumeration](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/0d0b32ac-a836-4bd2-a112-b6000a1b4fc9).
The qualified `1/2` alias rule is not a general claim that default and explicit
charsets are equivalent. In particular, `1/0`, `1/128`, `0/2`, and `1/2/0`
remain guarded. A guarded name does not suppress unrelated unambiguous fonts.

The package's `sourceFontCharsets` evidence record retains **all** source
indices, names and charset bytes, plus each projection decision. Duplicate
source indices, out-of-range public operands and invalid name code points fail
closed. An empty name remains evidence, preserving previously accepted source
records without treating them as usable font definitions.
The existing package/XML/evidence budgets apply. Other FFN properties, alternate
names, embedded fonts and general font substitution equivalence remain outside
this change; `partialFormatting` remains accurate.

## Independent causal check

The retained native parent and authored binary `CSymbol` control use the same
unmodified FFN table. It contains Wingdings at source index `5` with charset `1`
and at source index `6` with charset `2`. The ordinary private-use run selects
index `6` for ASCII/non-ASCII and index `5` for the other script slots. The native
DOCX font table contains Wingdings charset `02`; the former parser output had no
font table. The source/run operands remain separately retained.

Two counterfactual packages added only a font-table part and its OPC metadata.
Their `word/document.xml` bytes were unchanged. Charset `02` removed the full-page
mismatch; charset `01` preserved the **2.7 pt** drift. This isolates the missing
font property without changing glyph text or guessing a glyph equivalence.

The actual implementation then reproduced that result on the retained binary
control:

| Measurement on the pinned native renderer/fonts | CSymbol-only checkpoint | With source font charset |
| --- | ---: | ---: |
| Maximum word-box drift from the original DOC | 2.7 pt | 0 pt |
| Full-page decoded RGB equality | No | Yes |
| Extracted layout-text equality | Yes | Yes |
| Two actual DOCX→DOC→parser cycles against their own DOC | Exact | Exact |
| Those two cycles against the initial DOC | Residual remains | Exact |

The earlier whole-page mismatch was **1,208 pixels** after the CSymbol fix. Its
report remains unchanged; the successful charset result has no differing pixels.
This is a bounded result on the recorded renderer and font environment, not a
claim that any installed renderer will substitute every font identically.
Repeat stability alone missed the original first-export defect.

## Checks and retained observations

Eight new regression methods cover source FFN extraction, unmodified CPs/PUA,
exact charsets, duplicate/default cases, explicit conflicts, case collisions,
unknown bytes, independent fonts, package bindings, absent metadata and invalid
public inputs. The three targeted Dart suites initially passed **27 tests**, static analysis
was clean, and both VM and real compiled JavaScript passed **7 cases / 35 checks**.
Five initial schema fixtures passed the retained Open XML SDK 3.3.0 validator
with zero errors; this bounded run reused the existing validator build.

The combined JavaScript gate then exposed an existing empty-name FFN in
`formatting.doc` (source index `6`, charset `1`). The initial writer rejected
that newly surfaced metadata and blocked conversion. The follow-up preserves
the raw record as evidence and omits only its unnamed font-table entry. An actual
fixture regression and an authored empty-name case extend the required schema
cohort to six cases and the JS cohort to eight cases / forty checks. The original
failed gate and its cause remain separate from the corrected full-web result.
The corrected targeted suites passed **28 tests**, static analysis remained
clean, all six schema outputs had zero SDK errors, and the full JavaScript gate
passed its existing document/media/ink cohorts plus the symbol and charset
cohorts. This is broader than the earlier charset-only JavaScript check.

The source control, untouched native parent, before/after packages, paired
counterfactuals, source receipts, PDFs, text/word boxes, compressed raw rasters,
and actual two-cycle DOC intermediates are retained with the separate native
evidence checkpoint. The first counterfactual attempt was rejected by the native
application after an XML serializer changed OPC namespace spelling; that attempt
is retained as a failed setup observation. Its failure is not silently replaced
by the later successful, namespace-preserving package construction.
