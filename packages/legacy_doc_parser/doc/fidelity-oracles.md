# Fidelity corpus and independent oracles

`tool/fidelity/corpus.json` pins ten authored Office XML fixtures from the MIT
Quds fork at `ca9853b5b08784beac50df5680176cb4e5b3cb25`, plus the package's
existing native DOC fixture. Source paths, feature tags, SHA-256 hashes, and
license provenance travel with the corpus. The Quds expectations are retained
under `test/fixtures/fidelity/quds-expectations`; they describe original OOXML,
not a promise that a native DOC bridge can carry every newer OOXML feature.

```
python3 tool/fidelity/oracle.py
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --output build/fidelity-first-run
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --roundtrip-cycles 3 --output build/fidelity-three-cycles
```

No Office application is installed or downloaded. Normal unit tests do not
require native Office. The opt-in runner uses an isolated profile and creates
a new output directory. Source fixtures are hashed again after every run.
Package XML and relationships are inspected without fetching external targets.

For each original DOCX the runner first creates a DOC using installed
LibreOffice, then records the differences between the authored OOXML and a
native DOC-to-DOCX conversion. Those **bridge changes** matter: comments,
controls, modern revisions, and unsupported graphics may be lost before our
parser sees any bytes. They cannot prove or disprove our DOC parser's support.
Independently assembled binary unit fixtures cover those ambiguous cases.

The generated DOC is then converted by this package. The runner compares all
reachable stories, table/cell counts, comment threads, revision structures,
image hashes, links and sections against the native DOCX. Relocated parts are
resolved by relationships, not hard-coded filenames. Exact source DOC and
converted DOCX are also independently rendered to PDF. Page dimensions, page
count, page-by-page words, bounding-box drift, layout text, and raster hashes
are recorded. A same-page-count result alone never passes exact pagination.

Finally our DOCX is saved back to DOC by Office and imported again. The default
is one cycle; `--roundtrip-cycles 3` measures three successive binary imports.
Each cycle starts with the preceding parser output, records its native DOC and
native DOCX interpretation, and measures the new parser output. Native bridge
loss and parser differences stay separate. Semantic and rendering comparisons
refer to both the immediately preceding import and the first parser import.
A revision lost on the first cycle therefore remains a measured loss when the
second and third cycles produce the same damaged state. `--no-roundtrip` or
`--roundtrip-cycles 0` disables these extra measurements explicitly.

Every semantic snapshot and successful render is saved immediately with its
source-document hash. Atomic report checkpoints identify each running,
completed or failed stage. A failed third import leaves the preceding two
cycles and the native third-cycle snapshot available; a failed render retains
the earlier semantic and rendering evidence. Build failures also leave a report
with the compiler/environment information already collected.

The version 2 report records SHA-256 receipts for repository Dart sources,
fidelity tools, corpus manifest, dependency lock and package configuration,
as well as the actual compiled parser executable. It records compiler, Office,
PDF extraction and raster tool versions and executable hashes, Python/platform
details, font inventory, package commit and dirty-worktree state. Build inputs
are hashed before and after compilation; a concurrent change fails the run
instead of assigning ambiguous source provenance to the executable. These
receipts identify the measured repository and tool binaries; they do not claim
that every transitive runtime library or external dependency source was hashed.

`run.py` exits unsuccessfully for conversion/oracle failures. Ordinary measured
differences are findings, not an assertion of equality. `--require-exact`
additionally rejects every semantic, round-trip, or exact-render difference,
including native bridge changes and native DOCX rendering drift. Missing stages,
incomplete cycles, changed inputs and missing comparison results cannot pass.
It never regenerates or blesses goldens. Reports and rasters stay in the
requested output directory for inspection. Exact results apply only to the
recorded fixture, Office build and fonts; they do not certify all documents.
`test_run.py` exercises a mocked three-cycle native/parser pipeline, distinguishes
bridge loss from parser loss, and injects late conversion/render/build failures.
It does not substitute those mocks for a native rendering result.

## Structure beyond element counts

`structure.py` independently reads the emitted OOXML. Its snapshots include
direct table/row/cell properties, table grids and merge controls, referenced
table-style inheritance and conditional regions, every used numbering level
and override, and the numbering-instance graph. Renumbering identifiers does
not hide the collapse of two restart instances into one. Unequal section-column
widths, compatibility settings and explicit disabled values are inspected too.
Historical `sectPr` children belong to revision evidence and do not increase the
number of current sections.

Comment parent links join the final paragraph of each comment, including
relocated parts, case-insensitive hexadecimal paragraph IDs, replies preceding
their parents, and the resolved flag. VML textbox chains are validated for
dangling links, conflicting successors, multiple predecessors and cycles.
Box dimensions, margins, text flow, paint and DrawingML sequence metadata are
measured separately from their count. Ink elements are recorded as source
properties, not interpreted as rendered strokes.

Revision facts include the changed span, its location, author/date and previous
property state. Independent accepted/rejected **text projections** cover inline
insertions/deletions, move text, paragraph-mark merging and row visibility.
They are measurement views only: the runner does not accept or reject any change
in the source, and these projections are not a complete implementation of Word's
table topology, numbering history or editing rules.

The richer snapshot is deliberately strict about structural changes. A
semantically equivalent native rewrite may still be reported; such a finding
requires inspection and is never automatically accepted as a new expectation.
This prevents visually identical, flattened tables or review data from passing
as preserved editable structure. `test_structure.py` uses independently authored
OOXML and count-preserving mutations, rather than converter-generated goldens.

Primary references:

- [Conditional table-style properties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tablestyleproperties)
- [Numbering level overrides](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.leveloverride)
  and [restart semantics](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.levelrestart)
- [CommentEx paragraph join](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2013.word.commentex)
- [VML next-textbox reference](https://learn.microsoft.com/en-us/windows/win32/vml/msdn-online-vml-mso-next-textbox-attribute)
- [WordprocessingML revision structure](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-accept-all-revisions-in-a-word-processing-document)
