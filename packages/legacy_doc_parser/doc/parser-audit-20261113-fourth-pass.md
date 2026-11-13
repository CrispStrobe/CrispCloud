# Parser audit, fourth pass — 13 November 2026

This continues the [third audit pass](parser-audit-20261113-third-pass.md) from
`105901f0bdb8b84e92f6242c827c2de9d295945b` on
`fix/parser-audit-20261113`. The preceding work was merged in PR #8 before this
pass; its hosted checks subsequently completed successfully. Four new runtime
and acceptance checkpoints were saved remotely during this pass. The complete
implementation was tested from clean commit
[`e84f4131ce1515675dc97dfa6442d0c4a8ac77cf`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e84f4131ce1515675dc97dfa6442d0c4a8ac77cf).
The subsequent report/evidence commit changes no tested code or fixture.

## Confirmed defects and corrections

### Render list labels according to the substitutions they actually use

HTML rejected an entire list label when its level used an unsupported numeric
formatter, even if the label was entirely literal, referenced only a supported
ancestor, or used the legal-numbering flag to select decimal formatting.

The renderer now checks each required placeholder substitution. Literal labels
and supported ancestor/decimal substitutions retain their text. An unavailable
self-number or ancestor number still produces an explicit unsupported marker;
the renderer does not emit a partial label. This does not implement additional
numeral systems. The regression covers literal labels for all 55 accepted
numbered MSONFC codes, supported substitutions, and unsupported-number controls.

### Preserve exact TAB characters in native numbering labels

Binary parsing and HTML accepted TAB inside a stored list label, but the native
`w:lvlText` serializer rejected it as invalid text, failing the whole conversion.
The attribute now uses the existing bounded whitespace-preserving serializer.
An independent XML parser verified that all three new TAB cases retain U+0009
exactly; their XML uses character references rather than whitespace that an XML
attribute parser would normalize. Other invalid controls remain rejected.

The two list fixes reproduced eight failing checks before correction. All 61
focused list/numbering tests pass afterward. The shared actual-JavaScript
matrix now contains 15 supported cases and six rejection controls. Six new
DOC/DOCX/HTML fixture sets are included in the exact schema inventory. All 27
previous list artifacts remain byte-identical.

Checkpoint: [`4de28d1`](https://github.com/CrispStrobe/legacy-doc-parser/commit/4de28d193faa814991fbaf4278ef191a96b7dc90).
The source contracts remain [MS-DOC list formatting](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1a0bc623-211f-44f6-828b-51993f16e586),
[LVLF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/500d1b05-cd15-46af-bc8f-03bc290d1bdd),
and [XML attribute normalization](https://www.w3.org/TR/REC-xml/#AVNormalize).

### Validate body UTF-16 before filtering fields and controls

The structured parser rejected malformed Unicode, but text-only extraction
could return lone surrogate halves. More subtly, removing a hidden field or
control between two nonadjacent halves could manufacture a valid supplementary
character. Four malformed cases therefore also passed text-only DOCX conversion.

`extractLegacyWordText` now validates the consumed main body before filtering
display controls or hidden instructions. It rejects malformed pairs and a
dangling final high surrogate with a `FormatException`. Proper pairs still
work across physical CLX pieces because validation follows source character
positions. A second half in an auxiliary story cannot complete the main body.
The text-only API retains its scope: it does not newly validate auxiliary text
that it never consumes.

Ten malformed fixtures exercise visible and hidden halves, reversed pairs,
controls/fields between halves, and independent-story boundaries. Three positive
controls retain physical-piece splitting, cached field results, and unconsumed
auxiliary text. The original run recorded 21 failing checks; 45 focused
text/story tests pass after correction. The same extraction and conversion
checks pass in compiled JavaScript. Thirteen exact binary inputs and their
observed extraction outcomes are retained in the evidence bundle.

Checkpoint: [`09c1d5c`](https://github.com/CrispStrobe/legacy-doc-parser/commit/09c1d5cb7de2f556ec133e20bf971e34739bdee0).

### Inspect actual OLE/VBA containers before native activation

Caller-built public models could claim `canEmbed`, `linked: false`, or
`hasRequiredStreams` even when the emitted container was malformed, lacked
required streams, or represented a linked OLE object. Separately supplied
stream metadata could falsely vouch for different emitted bytes. Fifteen
regressions reproduced native activation of unqualified containers.

Conversion now opens the immutable container bytes with the existing bounded
CFB reader and reads every reachable stream. Before native activation it
corroborates the actual root `\x01Ole` identity for an embedded OLE object, or
the actual `PROJECT`, `VBA/dir`, and `VBA/_VBA_PROJECT` stream paths for the
existing VBA completeness contract. Same-name storages and nested lookalikes
do not qualify. Negative metadata remains a veto, and VBA still requires
explicit DOCM output and exactly one project.

Rejected containers retain their exact bytes as inert evidence and report the
existing conversion limitation. Inspection caches successes and failures by
immutable storage identity and has a separate 64 MiB aggregate input allowance.
The predicates extend the existing binary-parser policy to the public-model
boundary; they do not establish full CFB/OLE conformance, validate VBA programs,
or make any claim that embedded code is safe to execute.

All 42 focused public/extended-conversion tests pass. Seventeen shared VM and
JavaScript cases retain two active positive controls and 15 inert negatives,
checking exact output/source bytes, relationships, and limitations. The separate
schema corpus contains 17 DOCM files, raw CFB bytes, and explicit public-model
descriptions; these are not represented as binary DOC inputs. An intermediate
failure revealing the need to catch both reader exception types is retained
alongside the original failures and the final passing run.

Checkpoint: [`fd2b325`](https://github.com/CrispStrobe/legacy-doc-parser/commit/fd2b325151b2655298a0c968dcaf1b78b53e6885).
The bounded identities follow [MS-OLEDS OleStream](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-oleds/e0dc105e-77f1-4072-a938-9aa516dc43e9)
and [MS-OVBA VBA Storage](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ovba/b693e0ba-489f-4ac8-ac9d-6387fb5779bb).

## Clean-checkout acceptance

| Gate | Result at `e84f413` |
| --- | --- |
| Dart suite | **1,361 passed**; 61 added since the third pass |
| Analysis / formatting | No fatal-info issues; **251** maintained Dart files unchanged by formatting |
| Python controls / retained corpus | **162** tests and all **24** source-hash/package-graph checks pass |
| Actual compiled JavaScript | All existing gates plus 13 text-Unicode inputs, expanded 21-case list matrix, and 17 public compound cases pass |
| DOC-derived Open XML SDK corpus | **279 DOCX outputs**, zero errors; source-built validator self-tests, positive/negative controls and exact hashes pass |
| Separate public-model SDK corpora | **24 image DOCX + 17 compound DOCM outputs**, zero errors, with exact hash coverage |
| Determinism | **604** DOC-derived corpus files, **49** public-image files and **35** public-compound files match independent generations |
| Previous output preservation | All **297 prior DOCX outputs** remain byte-identical: 273 DOC-derived and 24 public-image cases; six DOC-derived outputs added, none changed or removed |
| Source identity | Clean tested commit; all **628** portable source hashes and the schema gate's **400** source hashes unchanged |

The complete schema-checked scope is **320 packages**, consisting of 303 DOCX
and 17 DOCM outputs. The runtime environment matches the prior pass: Dart
3.14.0, .NET SDK 8.0.428, Node 24.22.1 and Python 3.12.14. The independent
validator is built from the repository's pinned Open XML SDK 3.3.0 inputs.
The source snapshots, resolved dependencies, command logs and exact output
inventories are retained in the [fourth-pass evidence bundle](evidence/parser-audit-20261113-fourth-pass/README.md).

The integrated web acceptance and validator inventory documentation were saved
in [`e84f413`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e84f4131ce1515675dc97dfa6442d0c4a8ac77cf).
The connected GitHub API saved every checkpoint using expected-head,
non-force updates; each remote tree was checked against the corresponding local
tree. Independent review checked the implementations and recomputed the final
source identities, schema inventories and previous-output comparison.

## Remaining boundaries

Literal binary `%1`–`%9` list-label text remains explicitly unsupported. It is
not confused with true placeholders, escaped using invisible characters, or
flattened into an editable-numbering fidelity claim. Numeric rendering for
unimplemented numeral systems remains an explicit HTML limitation when those
numbers are actually referenced.

The two previously measured LibreOffice field-import differences remain open.
All preceding outputs, including the five field inputs used by those native
probes, remain unchanged. This pass ran no new native Office rendering and
does not claim native Word layout fidelity, complete CFB conformance, complete
OLE/VBA validity, or field evaluation. Original evidence and reviewed goldens
were left intact; the third-pass ZIP's 172-file manifest was independently
rechecked successfully.

This pass performs no package publication or downstream application pin change.
Hosted Actions for the new checkpoints were still queued in the latest
inspection; the completed local acceptance above is recorded separately.
