# Fidelity corpus and independent oracles

`tool/fidelity/corpus.json` pins 24 source cases, including ten authored Office
XML fixtures from the MIT Quds fork at
`ca9853b5b08784beac50df5680176cb4e5b3cb25`, the package's existing native DOC,
independent authored controls and public Word/Apache POI binaries.
Source paths, feature tags, SHA-256 hashes, and
license provenance travel with the corpus. The Quds expectations are retained
under `test/fixtures/fidelity/quds-expectations`; they describe original OOXML,
not a promise that a native DOC bridge can carry every newer OOXML feature.

```
python3 -m pip install -r tool/fidelity/requirements-test.txt
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

The portable Python suite requires Python 3.11 or newer and the pinned Pillow
test dependency for independent colored-border masks. CI installs that declared
dependency in Python 3.12; a preinstalled local imaging library is not assumed.
Optional image-appearance native probes additionally use NumPy and PyMuPDF.

For each original DOCX the runner retains its structural snapshot and renders
the original package before creating a DOC using installed LibreOffice. It
renders that DOC before invoking the parser. `bridgePagination` compares these
two renders, attributing their page, text, bounding-box, and raster differences
to the native original-DOCX-to-binary-DOC path. `pagination` separately compares
that same DOC render with the parser DOCX render. A stable parser conversion
cannot hide a visual change that already occurred on the native bridge.

The structural `bridgeChanges` comparison uses authored OOXML and the native
DOC-to-DOCX interpretation. Its path includes both native binary conversion
and native DOCX export. Either can lose or transform comments, controls,
revisions, tables, or graphics; it is not direct proof that those structures
were absent from the binary DOC. Likewise, a structural difference between
native DOCX and parser DOCX does not establish parser loss: the native DOCX
exporter can discard data that the parser retains. `comparisonAttribution`
records the source and destination of each comparison explicitly. Independently
assembled binary fixtures and targeted oracles resolve those ambiguous cases.
Original binary DOC cases have no original OOXML render, so their
`bridgePagination` and `bridgeChanges` are explicitly null.

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

The version 3 report adds original-DOCX rendering and original-to-binary visual
attribution, and requires those comparisons for authored DOCX cases. It records
SHA-256 receipts for repository Dart sources,
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
including original-to-binary visual changes, native bridge structural changes,
and native DOCX rendering drift. Missing stages,
incomplete cycles, changed inputs and missing comparison results cannot pass.
It never regenerates or blesses goldens. Reports and rasters stay in the
requested output directory for inspection. Exact results apply only to the
recorded fixture, Office build and fonts; they do not certify all documents.
`test_run.py` exercises a mocked three-cycle native/parser pipeline, distinguishes
bridge loss from parser loss, and injects late conversion/render/build failures.
It does not substitute those mocks for a native rendering result.

## Optional compressed raster retention

For long or repeated corpora, opt into lossless gzip storage:

```sh
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --roundtrip-cycles 3 --raster-storage gzip \
  --output build/fidelity-three-cycles-compressed
```

The default remains `--raster-storage ppm`, including the existing uncompressed
page files. Gzip mode first requires the installed Poppler `pdfinfo` page count
to match the extracted geometry's page count, then renders one page at a time
with the same RGB format and DPI. It verifies a streaming decompression against
that page's original PPM hash and size, and writes its receipt before removing
the raw page. Successful rendering keeps one active uncompressed page; failed
page remnants remain available for diagnosis. All completed compressed pages,
PDFs, source documents, text and geometry remain retained. Total storage still
grows with the corpus, and a large page or poorly compressible image can require
substantial space. Compression adds CPU and per-page rasterizer startup time.

The main and case reports record `rasterStorage`. Each successful compressed
render keeps its existing `rasterSha256` list as **uncompressed PPM hashes**, so
the render comparisons and reviewed source goldens use the same bytes as before.
Additional `rasterArtifacts` entries record page number, relative `.ppm.gz`
path, compressed SHA-256 and byte count, and uncompressed SHA-256 and byte count.
Paths are relative to that render's directory. `rasterManifest` identifies and
hashes `raster-manifest.json` in the same directory. That manifest also records
the PDF hash and independent page count, `pdfinfo.txt` receipt, DPI/color space,
compression level, Python version and runtime zlib version. The main report
also pins the `pdfinfo` executable and version when gzip mode is selected.
Compressed hashes identify stored files; they are not substituted for the page
hashes used by the rendering oracle.

The raster manifest is checkpointed before and after each page. A failed later
page leaves earlier completed page receipts and compressed files available. A
compression, verification or receipt-write failure retains the current raw page
if rasterization produced it. A failed render is still a failed stage, even
when some page artifacts survive. Atomic report replacement preserves the prior
complete checkpoint if a later write fails; this is not a promise that a
filesystem with no free space can write a new failure report.

Standard gzip and tar tools can read the artifacts. Existing report/golden
comparisons need no changes; a review tool that previously globbed `*.ppm` must
read the manifest and decompress the selected `.ppm.gz` file instead. For
example, materialize one page for an image viewer without changing its archive:

```sh
gzip -dc CASE/render-binary/page-0001.ppm.gz > /path/to/review/page-0001.ppm
```

Check the archive against its `sha256` receipt and the decompressed page against
`uncompressedSha256`; those are different hashes. Gzip needs no Pillow or new
Python package. `test_run.py` checks exact byte recovery, ordered multi-page
storage, compatibility with source-golden comparisons and tar archives,
corrupted/interrupted compression, changed raw inputs, missing pages and failed
receipt publication. These controls verify storage behavior; native corpus
rendering remains a separate acceptance run.

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

## Recovered source goldens and RGB measurements

The reconciled corpus contains 24 pinned source cases. `goldens.py` verifies
two independent source-DOC page records and reviewable PNGs. It has no update
mode. The compact and extended linked-textbox documents have separate paths
and hashes; the extended document owns the recovered linked-box page golden.

Runner report version 4 uses RGB rasters, records hashes of the actual font
files, and checks both the native source and parser output against a recorded
source golden when one exists. It retains the original DOCX render, native
bridge, native DOCX export and all requested binary round trips separately.
A font, Office build, PDF tool, color-space or DPI mismatch is unverified,
even when another comparison happens to have equal page counts or text.

The stronger recovered package reader selects one understood
`mc:AlternateContent` branch by namespace URI, bounds XML depth/node count,
resolves style/numbering references, and records section-to-story assignments.
These checks complement the existing structural graph and revision text
projections. Their mutation tests remain independent of the Dart converter.

## Additional reader and conversion paths

The [conversion path matrix](conversion-path-matrix.md) compares the two DOC
importers on identical source and regenerated binary bytes, includes an
OOXML-only native resave, and retains independent Pandoc AST/Markdown and
Antiword text observations. It preserves reader failures and lossy projection
boundaries instead of treating matching Markdown as full document equality.
The [typed inline oracle controls](independent-semantic-oracles.md) cover glyphs,
field operands and boundaries, bookmark ranges and note/hyperlink bindings that
equal visible text or element counts previously missed.
