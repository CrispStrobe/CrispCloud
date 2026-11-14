# Parser audit follow-up — 14 November 2026

## Baseline and checkpoint policy

This pass continues from `f30c8bfb8a6993e1b58423a4967dc33a5c10bdd7`
on `fix/parser-audit-20261114`, in [PR #10](https://github.com/CrispStrobe/legacy-doc-parser/pull/10).
The prior pass's [hosted run](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43562540391)
subsequently completed successfully. Its 3,688-test and 1,426-package evidence
remains versioned separately.

New tests were saved before repairs. Each coherent repair and acceptance batch
is committed with an expected-head, non-force update and verified remote ref.
The six repair families below are implemented. Combined acceptance passed on
clean commit **`a25e4ea824886327b97bde2873e6ef175a5ab971`**: 3,903 Dart tests,
197 Python tests, 38 compiled-JavaScript acceptance groups and 1,533 SDK-valid
Word packages. Later commits contain documentation and evidence only.
The [complete receipt and compact evidence](evidence/parser-audit-20261114-followup/README.md)
retain the original failures, final logs, source identities and new outputs.

## 1. Public cell shading was silently lost

A cell whose direct shading was supplied through
`LegacyWordTableCellFormat.shading` lost that shading in both DOCX and the
exported public HTML renderer. Both renderers read `cell.shading`; the DOCX
writer then disabled shading when writing the remaining formatting properties.
Parsed binary cells masked the gap because their resolved shading was copied
into both fields.

`LegacyWordTableCell.shading` now returns an explicitly supplied legacy value,
or otherwise the direct formatting value. The constructor remains const and
keeps its named parameter. Explicit legacy values, including `nil` and
unmapped patterns, retain precedence. Unsupported patterns keep their raw
evidence; the existing qualified HTML approximation remains qualified.

Nine independently specified cases check model values, HTML colors, DOCX
properties, absent values, explicit overrides and unsupported-pattern evidence.
Malformed formatting-only patterns and colors now reach the normal validation
path. The new 29 tests reproduced 11 failures before repair; all 56 new and
adjacent focused tests then passed.

## 2. Embedded-object flags used the wrong operand rules

`sprmCFObj` was in the toggle-property map, so values `0x80` and `0x81`
were accepted as relative flags. [MS-DOC Character Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18)
types this operand as [Bool8](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e275f842-a08a-4da4-89ac-b91a6ae0c1dd),
whose values are zero and one.

The flag now uses the Boolean decoder for both direct CHPX and compact Prm0.
Positive object controls contain a typed EMBED separator, the companion OLE
flag and referenced object storage. They do not treat a bare object flag on
ordinary text as a complete valid embedded-object document.

## 3. Built-in headings could become body text

A direct `sprmPOutLvl` could override the fixed outline level of a final
paragraph style index from one through nine. For example, a Heading 1
paragraph with outline operand nine became body text in the model and export.

The final paragraph-style boundary now derives these fixed heading levels
from the final style index. Normal and other styles still honor their
applicable outline property. Each retained PWall snapshot uses its own
previous style index, so historical heading semantics are preserved too.

The rule follows the [MS-DOC paragraph property contract](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/484822ee-a9d9-4af4-8423-29fda67a6a58).
Controls cover current properties, piece properties, previous styles and
ordinary explicit outlines, including emitted DOCX semantics.

## 4. Indirect paragraph properties had incorrect replacement semantics

The parser expanded `sprmPHugePapx` at any position, continued applying
properties after it, and accepted undersized referenced property arrays.
Consequences included overwriting the intended paragraph spacing and
dereferencing a pointer that the format requires the reader to ignore.

The decoder and expansion layer now agree on the source rules:

- A nonfirst PHugePapx is ignored before its Data-stream pointer is read.
- A first PHugePapx replaces the remainder of its containing array, including
  when its expanded properties come from the cache.
- Its referenced PrcData contains at least ten property bytes.
- Cyclic indirection and expanded-property budgets remain enforced.

The new fixtures reach nested arrays through a sole PTableProps in a direct
PAPX. They include ignored unusable offsets, ignored cycles, replacement of a
conflicting tail, the minimum valid length and a mixed indirection chain.

The old expansion-budget specimen repeated PHugePapx within one array, whose
tail must now be ignored. Its replacement uses independent PRC arrays pointing
to one shared cached leaf and asserts the exact expansion-budget failure.
The revised bounds test passes before and after the repair.

The three binary families reproduced 52 failures in 69 new cases. They pass
after repair, along with four bounds controls and 449 adjacent SPRM, scalar,
revision, style, font and table tests.

## 5. Bookmarks could skip validation or move to another story

Hidden field instructions could hide malformed bookmark names, duplicate
identities, reversed/cross-story ranges and incomplete column metadata.
Validation now precedes visibility fallback. The name limit, Unicode/XML
attribute validity, uniqueness, owning story and paired ordered columns are
checked for every bookmark. Hidden evidence retains the column attributes.

The normalized inclusive column domain is zero through 62, from the
[BKC source representation](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b59cbd01-2391-4b70-994c-b58104d3f4c0).
The [native Word name limit](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/da8b8f59-2af1-49d9-8553-f0c1ff2fb18d)
is 40 UTF-16 units. No ASCII-only name grammar or physical table-width
restriction is invented.

Bookmarks represent boundaries rather than character anchors. The writer now
mirrors the parser's bookmark ownership:

- A range wholly within main, including a terminal point, stays in main even
  if an auxiliary story starts at the same position.
- Otherwise, the latest story starting at or before the bookmark start owns
  the range, provided its end fits that story.
- A terminal auxiliary point remains in its story when there is no adjacent
  successor. At a shared auxiliary boundary, the successor takes precedence.
- A point past the preceding story's end in a gap is rejected.

Tests assert the actual containing XML part. They include main/header/note
adjacency, auxiliary terminal points, shared boundaries, valid international
names and hidden column metadata.

## 6. Public textbox references could invent or discard content

The writer trusted ordinary anchor-array order and did not consistently check
chain indices, declared lengths, next links, story ownership or drawing
ownership. It could invent a different flow chain, discard a second owner of
one story, or emit duplicate drawing identities.

Supplied anchors are now copied and ordered by their source chain index;
the caller's list remains unchanged. Story and drawing occurrences have one
owner. Indices, lengths, explicit first-shape positions and nonzero next links
must agree. Supported null/zero links, shared header replicas, aliases and
corroborated declared-one recovery remain supported.

Independent review then reproduced additional mistakes in the first repair:
header textboxes could be placed in main, and singleton fallback could silently
replace a supplied shape ID or move a supplied anchor. Hidden placement could
also skip drawing-client checks. These identities, source domains and drawing
links now validate before visibility or unavailable-placement fallback.

The header source domain includes header/footer and all six Hdd footnote/endnote
separator and continuation kinds. Positive controls cover all eight kinds;
valid separator textboxes are not rejected by a header/footer-only rule.

When a parsed multi-frame story lacks enough client links to establish its
placement, the writer retains inert evidence with its chain metadata instead
of guessing one active singleton. This preserves an existing source recovery
path without asserting unsupported native placement.

The final semantic worktree passes 55 bookmark tests and 58 textbox tests.
Its focused existing/new gate passes 191 tests, and its full suite passes
3,801 tests before the other agents' changes are combined. The second-review
controls independently reproduced 16 failures against the earlier repair.

## Combined acceptance

All commands below returned zero on clean source commit
`a25e4ea824886327b97bde2873e6ef175a5ab971`. The saved SDK receipt records
`gitWorktreeDirty: false`; all 485 gate-selected source hashes are unchanged
after validation. A separate 749-file manifest covers the maintained library,
tests, tools, examples, package declaration and CI workflow at that commit.

| Gate | Result |
| --- | --- |
| `dart test --reporter expanded` | 3,903 passed; 215 more than the preceding pass |
| `dart analyze --fatal-infos` | No issues |
| `dart format --output=none --set-exit-if-changed lib test tool example` | 353 files checked, zero changes |
| `python3 tool/verify_web.py` | 38 compiled-JavaScript groups passed |
| Python fidelity unit tests | 197 passed |
| `python3 tool/fidelity/oracle.py` | 24 retained source hashes and OOXML package graphs verified |
| Open XML SDK 3.3.0, Office2019 rules | 1,114 DOC-derived plus 419 public-model outputs; 1,533 total, zero errors |
| SDK controls and repeated generation | Self-tests passed; one valid and two invalid controls behaved as required; ten corpus groups repeated exactly |
| `dart pub publish --dry-run` | Zero warnings; no package publication |

The SDK run generated each corpus twice and compared 3,028 retained files
byte-for-byte. Independent inventories, output paths, per-file hashes and
all validation reports agree. A separate read-only review rehashed all twelve
SDK report files and all forty stage logs successfully. The deliberately
invalid SDK controls exit one and report two errors; that expected rejection
is separate from the zero-error corpus result. Python's failure-looking log
messages likewise belong to deliberate negative controls; its final result is
197 passing tests.

The freshly built validator used .NET SDK 8.0.428, framework 8.0.34 and the
existing `--cached-nuget` direct SDK compiler path. It used the unchanged
validator sources, pinned NuGet archives, verified reference assemblies and
the full control suite. This pass selected that existing fallback without
reattempting ordinary MSBuild. Dart was 3.14.0, Python 3.12.14 and Node 24.22.1.

### New compiled-JavaScript acceptance

These four groups compile and execute the same shared acceptance helpers that
also run under the VM. The other thirty-four groups remain in the full gate.

| Group | Positive behavior | Malformed controls |
| --- | --- | --- |
| Cell shading | Nine model/HTML/DOCX cases; two unsupported-pattern evidence cases | Two formatting-only inputs rejected |
| Binary property contracts | Four Boolean, forty-eight heading and five indirect-property cases; 57 converted packages | Ten invalid Booleans and two invalid indirect arrays rejected |
| Public bookmarks | Eighteen active cases, including seven auxiliary-owner cases; three hidden-evidence cases; 21 packages | Thirty-four malformed inputs rejected |
| Public textbox references | Seventeen active cases, including eight Hdd-owner cases; three inert cases; 20 packages | Thirty-eight malformed inputs rejected |

The binary helper checks unchanged source bytes. The semantic helpers check
unchanged source metadata, including caller-provided anchor order. Bookmark
checks assert the containing XML part and absence of stray bookmark markers
in other parts. Textbox checks assert identities, order and links; inert cases
must not create active frames in any document, header, footer, note or comment
part.

### SDK inventory additions

| Addition | New positive packages | Input source |
| --- | ---: | --- |
| Binary property contracts | 57 | Independently assembled binary DOC |
| Cell shading | 9 | Authored public table models |
| Bookmarks | 21 | Authored public models |
| Textbox references | 20 | Authored public models |
| **Total added** | **107** | **57 DOC-derived and 50 public-model** |

The binary group also retains twelve malformed DOC inputs without outputs.
They are rejection controls and are not included in the 57 successful
conversions. The complete public-model inventory now has nine groups and 419
outputs: metafile 24, compound 17, formatting 106, table formatting 53, cached
field structure 88, display-field evidence 46, section geometry 44, bookmarks
21 and textbox references 20. The combined 1,533 outputs include DOCX/DOCM;
they are not 1,533 binary source documents.

## Saved evidence and reproduction

The [evidence index](evidence/parser-audit-20261114-followup/README.md) links
the final receipt and verified 398-member compact archive. It retains complete
final command logs, selected original-failure and focused-repair logs, all SDK
reports and stage logs, both generations' metadata, 107 new positive packages,
69 binary inputs, dependency declarations and source hashes. Earlier output
packages are represented by their exact hashes in the full SDK receipt and
their reproducible source inventory rather than duplicated in the archive.

For a fresh run, check out the tested commit, run `dart pub get`, then run the
commands above. The exact arguments are retained in `final-receipt.json`.
The ordinary SDK path is `python3 tool/fidelity/schema.py --out build/schema-new`;
the recorded run adds `--cached-nuget` pointing to the three pinned NuGet
archives. Use a new output directory for each SDK invocation. The saved lock
file identifies this run's resolved Dart dependencies.

Hosted Actions status remains independent of these local receipts. The prior
pass's hosted run completed successfully; the new source-head push and PR runs
were queued when this report was finalized.

## Scope

These repairs address source interpretation, model/export consistency, native
package semantics, and bounded validation. They do not establish identical
Word pagination or native editor review behavior. No new Word/LibreOffice
rendering pass is claimed. The previous interrupted session's missing native
artifacts remain outside this pass's evidence.
