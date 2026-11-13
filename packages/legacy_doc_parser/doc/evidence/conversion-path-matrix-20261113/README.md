# Attributed conversion paths and alternate-input controls

This evidence separates an original source, competing DOC importers, native
OOXML-only resaves, binary round trips, and text-oriented projections. A
successful command means that the observation completed. It does not mean
that the document is correct, equivalent, or free of parser defects.

**Incremental checkpoint:** the five-input historical baseline and all auxiliary
controls below are sealed. The new eight-input measurement at the fixed source
is still running and is not included or claimed here. Its completed artifacts
will be added separately without replacing the baseline.

## Exact source identities

| Measurement | Source identity | What that identity means |
|---|---|---|
| Historical baseline | `c05f187b99e46b6d8d1b6aed6610307f33e1725c`, tree `f8dc52c5a9f0f6b7b25e598be2136d6d5d01d420` | Clean measured harness/source checkpoint. Its entire parser `lib/` tree is byte-identical to original runtime `c5ff75e76163d9abbdd44a9f2a7c5ad210929289`. It remains the old parser measurement. |
| Read-only replay helper | `1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1`, tree `8b826eb2239438565faefa718bd42da61107d95e` | Final harness verifies the original artifacts. Running this verifier does not rerun or relabel the baseline. |
| Note-order auxiliary | Original baseline parser executable | Four explicitly authored alternative inputs. The original fixture and every measured output remain separate. |

The baseline retains all **154 measured compiler/harness inputs**, plus its
five actual original fixture files. There are 157 committed Git files and two
generated resolution inputs (`pubspec.lock` and package configuration) in this
159-file source snapshot. The Git option below checks committed bytes against
their immutable source objects. Generated resolution inputs retain their exact
measured hashes and are identified as generated, rather than claimed as Git
objects.

The complete source path set is derived from the immutable Git tree and the
recorded `source_receipt` selection contract, including both generated inputs.
Its exact count and path-set digest are pinned for offline verification, then
independently rederived when Git checking is requested. Removing a compiler
input from every mutually consistent receipt and its retained source copy
therefore fails, even after resealing the archive.

The original schema-5 `oracle.py` and `structure.py` are retained and checked
against the baseline source receipt before replay. The final schema-6 observer
does not overwrite those original observations. The six exact final replay
modules are also retained, with their hashes bound before they are loaded.

## What the baseline measures

The five original inputs are `word.docx`, `note-markers.docx`, authored
`locked-fields.docx`, authored `note-joins.docx`, and native `formatting.doc`.
The four OOXML sources retain a direct OOXML resave path as well as a binary
DOC bridge. Each binary source is read independently by the parser and
LibreOffice. Each resulting DOCX then has a native DOC export followed by both
importers again. Original and regenerated DOC files also receive a separate
Antiword text read.

Every DOCX has Pandoc reads under explicit `accept`, `reject`, and `all`
revision views. Its actual JSON AST is written to ordinary Markdown and read
back. The original AST, Markdown and reread AST remain retained.

| Baseline observation | Count |
|---|---:|
| Input cases | 5 |
| Retained document nodes | 53 |
| Recorded commands | 410 |
| Attributed path comparisons | 59 |
| DOCX/revision-view Pandoc projections | 114 |
| Measured Pandoc path comparisons | 147 |
| Equal body AST comparisons | 69 |
| Equal Markdown comparisons | 66 |
| Explicit Antiword reader errors | 10 |
| Blocked path comparisons | 0 |

The ten Antiword errors remain errors, with exact stderr and exit receipts.
They do not become empty equal text or automatic parser failures. All document
conversion paths and Pandoc projections in this retained run completed.

Equality has important limits. On the original unordered note-join source,
the parser and native importer have equal Pandoc body projections while both
differ from the authored source. On the locked-field source, equal cached
body content does not establish that the original field instruction survived.
Those are reasons to keep original-source, typed XML and field observations
alongside the text projection. The separate
[field recovery proof](../hyperlink-fields-20261113/README.md) retains the raw
binary field diagnosis, before/after outputs and targeted native acceptance.

## Independent note-ID and part-order experiment

The original fixture references note IDs **19 then 7**, with semantic content
`NOTE-A:α` then `NOTE-B:β`; the note part stores those notes in the opposite
order. All four authored variants preserve that semantic contract initially.
Only the stated note-ID substitutions and/or note-element reordering are made;
the verifier compares every OPC part to the original plus those exact changes.

| Authored input | Native OOXML resave | Native DOC → native DOCX | Native DOC → old parser DOCX |
|---|---|---|---|
| Original IDs and part order | Notes swapped | Notes swapped | Notes swapped |
| Rename both sides: 19→1, 7→2 | Original joins preserved | Original joins preserved | Original joins preserved |
| Reorder the note part only | Notes swapped | Notes swapped | Notes swapped |
| Rename IDs and reorder the part | Original joins preserved | Original joins preserved | Original joins preserved |

This is **20 retained documents and 17 recorded commands**. The original
OOXML-only native resave already swaps the joins, before binary DOC import by
our parser. Renumbering both sides supplies a discriminating alternative input;
it is not a parser repair, an original-source rewrite, or a new sole golden.
Reordering the part alone does not resolve the measured native behavior.

## Markdown metadata control

A real DOCX contains Title-style `KEPT-TITLE`, Author-style `KEPT-AUTHOR`, and
body text `BODY`. The original Pandoc read returns both metadata values.

| Projection of that AST | Body after Markdown reread | Title and author after reread |
|---|---|---|
| Ordinary `--to=markdown --wrap=none` | Preserved | Both absent |
| Same writer with `--standalone` | Preserved | Both preserved in the YAML header |

All five recorded commands succeeded. This establishes a loss in the selected
ordinary Markdown projection. It does not establish a DOC parser defect or
make standalone Markdown a complete document-fidelity oracle. In particular,
Pandoc's `Note` representation does not certify footnote versus endnote kinds,
and equal body ASTs do not certify headers, field behavior, layout or editing
semantics.

The separate earlier reviewer AST-only counterexample is retained with its
original metadata type and output. It is not relabeled as this DOCX-based
experiment. The historical version-1 matrix omitted a Markdown metadata
comparison; the final replay computes that comparison separately from retained
ASTs without changing the old report. The new version-2 harness reports body
and metadata comparisons separately.

## Tool and provenance boundaries

Actual version outputs identify LibreOfficeDev **26.8.0.0.alpha0**, source
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`; Pandoc **3.1.11.1**; and Dart
**3.13.7**. The Antiword executable matches the separately retained 0.37 source
build and mapping-resource setup in
[independent reader evidence](../independent-readers-20261113/README.md).
The matrix itself retains the Antiword version-command output as observed,
including its empty stdout; it does not invent a version banner.

LibreOffice import, export and resave paths belong to one implementation family.
Pandoc's reader and writer belong to another. Antiword is a separate binary
DOC text reader with documented omissions and actual failures. Repeated
agreement within one family is not an additional independent vote.

The matrix records argv, working directory, exit/timeout status, output streams,
source manifests, document hashes before/after use, and the compiled parser's
exact bytes. It does not provide a hermetic environment or independently attest
the compiler. The recorded native executable hash identifies the invoked
launcher; its version output identifies the observed native build. Native
profiles are omitted as incidental state; the exact source retains the initial
profile settings, including disabled macros and link/field updates.

The auxiliary experiments are prototypes with narrower receipts. Note-order
commands retain argv, cwd, status and stream hashes, plus document hashes and
the source-unchanged result; they do not have the matrix's full per-edge input
receipt structure. The Markdown prototype retains all five argv/exit records
and relevant output hashes, but omits cwd, environment, timestamps and complete
before/after input receipts. Verification binds what was actually recorded
and recomputes the package/AST claims; it cannot reconstruct missing process
provenance.

No PDF, raster or layout measurement is part of this bundle. Main portable,
SDK and full native corpus gates are separate evidence. No converter,
document field, macro, hyperlink or external image is activated during replay.

## Retention and replay

| Archive | Exact retained files | Raw bytes | Compressed bytes |
|---|---:|---:|---:|
| `baseline.tar.xz` | 1,872 | 66,728,432 | 3,634,848 |
| `auxiliary.tar.xz` | 106 | 555,479 | 69,348 |

Each archive has an exact path/size/mode/SHA-256 manifest. Both the retained
baseline parser executable and its build receipt are present. The archive also
retains original reports, source snapshots, source documents, intermediate
documents, raw command outputs, XML facts, ASTs and Markdown. Excluded native
profiles and Python caches have explicit path/hash inventories. No document,
AST, parser executable, command receipt or observed error is excluded.

Historical verifier failures and fixes remain in `auxiliary/independent-review`:
an accepted substituted native executable, its corrected rejection, an
accepted invented parser-executable hash, its corrected rejection, and the
equal-body metadata-loss control. Their exact prior verifier sources are
retained. They are historical observations, not claims that the final verifier
still has those gaps.

From the repository root:

```sh
python doc/evidence/conversion-path-matrix-20261113/verify.py --repository . --self-test
python -m unittest discover -s doc/evidence/conversion-path-matrix-20261113 -p test_verifier.py -v
python -O -m unittest discover -s doc/evidence/conversion-path-matrix-20261113 -p test_verifier.py -v
```

The wrapper verifies the complete archive, source identities, immutable replay
code, original fixture identities and auxiliary claims, then calls the exact
final `verify_path_matrix.py` with the retained observer source. Eight matrix
corruption controls reject altered derived values/roles, executable argv,
Markdown input, parser-byte identity, summary values and erased reader errors.
Thirteen additional resealed source/auxiliary corruptions plus the positive original
control pass normally and under optimized Python. All guards are explicit and
remain active under `python -O`.

`build_evidence.py` packages already completed measurements; it invokes no
document tools. `seal.json` binds this README, the helpers, archive manifests,
archives and the exact replay outcome. A passing replay establishes integrity
and consistency of these observations, not universal correctness of any parser
or converter.
