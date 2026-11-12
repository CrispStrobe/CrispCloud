# Fidelity corpus and independent oracles

`tool/fidelity/corpus.json` pins ten authored Office XML fixtures from the MIT
Quds fork at `ca9853b5b08784beac50df5680176cb4e5b3cb25`, plus nine package
controls, for 19 cases in total. Those controls cover the existing formatting
DOC, three independent linked-textbox sources, editable OfficeArt shapes,
EMF/WMF vectors and continued/restarted binary lists. Source paths, feature tags, SHA-256 hashes, and
license provenance travel with the corpus. The Quds expectations are retained
under `test/fixtures/fidelity/quds-expectations`; they describe original OOXML,
not a promise that a native DOC bridge can carry every newer OOXML feature.

The [recorded native results](fidelity-results.md) retain the full comparison
report for a tested package checkpoint; the [status matrix](fidelity-status.md)
separates that measured coverage from the remaining format capabilities.

```
python3 tool/fidelity/oracle.py
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --output build/fidelity-first-run
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

Finally our DOCX is saved back to DOC by Office and imported a second time.
Changes are reported separately from the first conversion. Renderer version,
font inventory hash, source hashes, package commit and dirty-worktree state
are included. The native DOCX render is measured too, so native conversion
loss cannot silently become the expected output.

`run.py` exits unsuccessfully for conversion/oracle failures. Ordinary measured
differences are findings, not an assertion of equality. `--require-exact`
additionally rejects parser-versus-native semantic differences, parser round-trip
differences and source-DOC-versus-parser exact-render differences. Bridge changes
and native DOC-to-DOCX rendering differences remain separate findings; this flag
does not certify an authored DOCX survived its intermediate native DOC bridge.
It never regenerates or blesses goldens. Reports and rasters stay in the
requested output directory for inspection. Exact results apply only to the
recorded fixture, Office build and fonts; they do not certify all documents.

## Reviewed source page goldens

`test/fixtures/fidelity/goldens` contains reviewed color pages and text/word-box
measurements for the pinned `formatting.doc` and linked-textbox binary fixtures.
These are independent source-DOC renders, not output from this converter. The
manifest pins the binary sources, render records and PNGs. No tool has an update
or bless mode. A new golden requires a source render, image review and an
explicit reviewed manifest change.

The opt-in native runner compares the source render to these goldens before
interpreting the converted-document measurements. `sourceGolden=matched` means
the reference renderer reproduced a reviewed source page. It does **not** mean
the conversion matched that page; `pagination.exactOnThisRenderer` is separate.

The environment includes the exact Office build, font inventory and font-file
content hashes, and both Poppler tool versions. A missing font fingerprint or
different environment is reported as `environment-mismatch`, never a passing
golden. `--require-goldens` requires a matching reviewed golden for every selected
case. For example:

```sh
python3 tool/fidelity/goldens.py
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --output build/reviewed-source-check --case formatting \
  --case linked-textboxes-native --require-goldens
```

Native rasters now use RGB PPM at the recorded resolution. Grayscale equality
could miss a color change with the same luminance and is no longer an exactness
criterion. PNGs make the reviewed source pages easy to inspect; PDF hashes are
retained as provenance, not as a stable equality check, because PDF metadata can
change without a visual change. Mutation tests verify that color-raster, source,
word-position, tool/font-environment and review-image changes cannot silently
pass the golden check.

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
