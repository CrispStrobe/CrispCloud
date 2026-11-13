# Independent semantic, symbol and font evidence

This bundle retains the counterexamples that exposed two genuine parser
omissions: explicit binary symbol operands and source font charsets. The final
bounded symbol/font output matches the retained original DOC's decoded page
pixels, layout text and word boxes, including two actual save/import cycles.
The earlier failures remain separate, unchanged observations.

The archive contains **2,359 files**, including all authored inputs, native DOC
intermediates, before/after packages, original setup diagnostics, native profiles,
PDFs, text/word boxes, **16 compressed raw RGB rasters**, and versioned source
copies. The verifier replays **21 historical schema-5 snapshots** using the
matching schema-5 oracle. It also reproduces four old schema-4 false passes and
the separate schema-5 font-charset false pass. These are observed counterexamples,
not automatically updated source goldens.

## Source and implementation identities

| Role | Exact commit or input SHA-256 |
| --- | --- |
| Original parser/runtime baseline | `43027f9ddb626a4f8fccbef1c41c7f2ea9fccf47` |
| Independent inline oracle, schema 5 | `c73749df59d0978c8bcd20710a2ae92184fab11a` |
| Explicit symbol runtime | `9aa9da7c1e378d369c03ed1abcebfd70eb496b0d` |
| Font charset runtime | `d5fa58409ce4be3859b05a40132edbef3c4d54cf` |
| Font-aware oracle, schema 6 | `901f85854592cdf5f27d475da27ea5431d6024d5` |
| Empty-name font compatibility guard | `927c2cb089cf2d037dc009cdcb9c11b9fe125bf9` |
| Combined runtime source | `1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1` |
| Untouched native DOC parent | `c16d1e2f9ac6c7d53a762526553a36feea466231068709f9bb00ea0c129fcdc1` |
| Independently authored binary symbol control | `765f8c5f7a3d4eaf6366419c70a0d0b48b2848009ec9549b34c28b0de0dc549f` |
| Existing formatting DOC used by the full-web gate | `0ad636c6e3597152313055fd5428fb4b70ab483b3853b2666cac52498c953026` |

The first four DOCX inputs were authored directly from literal OOXML and explicit
contracts in
[independent_semantic_cases.py](../../../tool/fidelity/independent_semantic_cases.py).
They cover character controls and Unicode, symbol glyph operands, locked fields,
and note-reference topology. Their expectations were written before native export
and do not come from Dart converter output.

The binary symbol control is an **authored patch to a retained native export**,
not a Word-produced corpus file. Its recipe changes one U+F061 occurrence to the
documented U+0028 symbol anchor and installs `CSymbol(font=1, code=F061)` in its
referenced CHPX interval. The patch receipt identifies the untouched parent,
literal FC, original/replacement properties, source FC boundaries, and every
compound stream hash. A bounded independent CFB reader in the verifier confirms
that the other streams are identical and that the WordDocument changes stay
inside the one code unit and one CHPX page.

The measured symbol and initial font executables were compiled from explicitly
recorded working trees. Their retained library hashes match the corresponding
published runtime commits; the receipts preserve the actual pre-publication
HEAD/dirty state. The final guard build records exact commit `927c2cb` and tree
`4c39f4c912ec542792aa878e014c6040f6ce00fc`. It reproduces the initial and both
cycle DOCX packages **byte for byte**. The existing native measurements therefore
apply to those identical packages; no extra native rerun is implied.

The combined runtime's original-DOC matrix output also matches that already
rendered package byte for byte: **5,687 bytes**, SHA-256
`bd2acb35697fe7b404f7944bd2955a53341230e0b946e4aa97f846ac0db6832d`.
The added `combined-source-equivalence` records retain its actual compiler and
parser command streams, original DOC, output DOCX, both unchanged build-source
receipts, and **159 source-file copies**. The selected source/node projection
records the overall matrix's status at capture; this one-node equivalence does
not claim completion or acceptance of the complete path matrix.

## Findings and source attribution

| Probe | Observed result and attribution |
| --- | --- |
| Nonbreaking/optional hyphens, actual tabs, Unicode and preserved spaces | Native bridge and parser retained the authored text. The former oracle ignored some controls; the new oracle detects their removal. |
| Field instructions with unchanged cached text | The former oracle missed changed targets/quotes. The source/native/parser snapshots retain instructions, nested boundaries, story context and stored results separately. The binary REF-marker loss was handed to the separate field-metadata work; these baseline reports remain unchanged. |
| Footnote anchors with deliberately different part/reference order | The native import/resave path changed the source association before parser export. The parser follows the binary source association. This bundle does not isolate a specific native writer phase. |
| Explicit CSymbol operand | The former parser emitted a literal `(`. Typed source operands and `w:sym` now retain the correct font/glyph without inventing a Unicode equivalence. |
| Ordinary Wingdings private-use text | Preserving the source FFN charset removes the remaining first-export mismatch. The private-use text and document XML remain unchanged. |
| Existing empty-name FFN | The initial font writer rejected a previously accepted source record. The follow-up retains it as qualified evidence and omits the unnamed active font entry. |

The four original oracle controls changed a symbol glyph, a REF instruction, a
resolved note target, or a nonbreaking-hyphen content element. Schema 4 reported
no semantic differences for each. Schema 5 detects all four. The later paired
font packages differed only in the font charset `02` versus `01`; schema 5 again
reported no difference despite the native rendering change. Schema 6 adds a
relationship-bound `fontCharsets` property. Part names, relationship IDs,
declaration order and hexadecimal case normalize; changed or absent charset
declarations and duplicate definitions remain observable.

## Native result, with the original residual preserved

The source page is 612 × 792 pixels at 72 dpi. Measurements use the recorded
LibreOffice/font environment, without a renderer-specific position adjustment.

| Stage | Full-page differing pixels | Maximum word-box drift from initial DOC | Actual repeats |
| --- | ---: | ---: | --- |
| Original parser | 1,300 | Text differs, so a same-word drift comparison is not applicable | Separate later stages below |
| CSymbol correction only | 1,208 | 2.7 pt | Two cycles exact to their own binary inputs, with the original residual still present |
| Source font charset correction | 0 | 0 pt | Two cycles exact to their own binary inputs and to the initial DOC |

The controlled first line changes from **92 differing pixels to zero** after
the symbol fix. All pixels below that line are identical before/after that fix.
The line mask is a full-width row interval, not a source shape boundary.

The source FFN table contains Wingdings at index 5 with `DEFAULT_CHARSET=1` and
index 6 with `SYMBOL_CHARSET=2`; the ordinary private-use run selects index 6
for its ASCII/non-ASCII font slots. Native DOCX carries charset `02`, while the
former parser emitted no font table. The paired counterfactual adds only a
font-table part and OPC metadata: `word/document.xml` and all other content parts
remain byte-identical. Charset `02` removes the full-page mismatch; charset `01`
retains it. The actual serializer then reproduces the `02` result.

The runtime keeps every original FFN index/name/charset in evidence. The exact
`{1,2}` same-name alias is qualified separately from identical definitions and
from conflicting explicit charsets. Other mixed charsets, unknown bytes,
case-colliding names and empty names remain guarded. No PUA mapping, font alias
renaming, inferred code page or font embedding is used. See the primary-source
contracts and limitations in [symbol-glyphs.md](../../symbol-glyphs.md) and
[font-charsets.md](../../font-charsets.md).

## Gates, failures and qualifications

The final bounded follow-up passed **28 targeted Dart tests**, static analysis,
and the complete compiled JavaScript gate. Its JavaScript output includes the
existing DOC, media, ink and ink-header cohorts, plus **9 symbol cases / 18 checks**
and **8 font cases / 40 checks**. The last portable receipt binds **453 tracked
input files** to `927c2cb` and records actual argv, cwd, exit codes and streams.

The archive retains **13 actual schema outputs across three stages**: 2 symbol
outputs, 5 initial font outputs, and 6 final font outputs. All have zero recorded
Open XML SDK errors. These bounded checks reused the previously built SDK 3.3.0
validator with its recorded SHA-256; they are distinct from a freshly built full
combined schema gate.

Original failures are kept explicitly:

- A first native setup/version call failed because this workspace had no `/tmp`;
  later commands used the recorded `TMPDIR` before any native conversion.
- A first metadata counterfactual changed OPC namespace spelling through an XML
  serializer and was rejected by the native application. Its package and fresh
  profile are retained; the original process streams were not saved. The later
  namespace-preserving packages are separate artifacts. No conformance judgment
  about that first package is inferred from the rejection alone.
- The full combined JavaScript gate exposed the empty-name FFN regression. The
  parent supplied a clearly labeled returned-tool-text transcript, not separated
  raw stdout/stderr or a retained compiled JavaScript file. A separate run of the
  retained pre-guard converter reproduces exit 255 and captures real streams.
- An initial new regression assertion compared map identity rather than map
  contents. Its failed targeted-test receipt remains alongside the corrected
  28-test result.

The native renderer is **LibreOfficeDev 26.8.0.0.alpha0**, commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. `pdftoppm` and `pdfinfo` are
**26.05.0**; `pdftotext` is **25.03.0**. Font inventories and file hashes are
retained, as are the tool executable hashes. The bounded native result applies
to that environment. The source `CSymbol` followed by a later explicit false
special-character flag remains qualified: the native serialization is recorded,
but the normative ambiguity and the independent implementation disagreement are
not turned into an ordinary-literal correctness claim.

## Verify and review

From a repository containing the checkpoint objects named above:

```sh
python3 doc/evidence/independent-symbol-font-20261113/verify.py --repository .
python3 doc/evidence/independent-symbol-font-20261113/test_verifier.py --repository .
python3 -O doc/evidence/independent-symbol-font-20261113/test_verifier.py --repository .
```

Verification requires Python's standard library and local Git objects. It does
not run Dart, the SDK validator or the native application. It verifies the exact
archive inventory and bytes, raw CFB operands, source snapshots, PDF/text/raster
bindings, decoded RGB pixels, native comparisons, schema-output bindings,
required test/cohort identities, and final package equivalence. Versioned oracle
code is executed only after matching the exact retained Git source.

The test helper creates **14 genuinely resealed corrupted bundles** and invokes
the real verifier on each. It changes source identity, font operands, old
snapshot versions, native metrics, final package binding, recorded commands,
required JS cohorts, schema errors or original failure status, or removes raw
raster evidence. Explicit exception guards remain enabled under Python `-O`.

The archive omits ten reproducible compiler outputs: four executables and six
JavaScript/build-map files. Their original hashes and sizes are listed in the
manifest, and their source/build receipts remain. Original document inputs,
native intermediates, rendered artifacts and execution observations are retained.
`build_bundle.py` only packages existing bytes; it performs no conversion and
does not update any source golden.
