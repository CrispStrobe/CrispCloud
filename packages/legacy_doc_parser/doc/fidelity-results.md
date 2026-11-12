# Measured fidelity: 12 November 2026

The frozen package checkpoint **`b03747396878518d0d623599baf9b376df776e3d`**
completed all **19 native cases**, including a second import after saving its
DOCX back to DOC. No case had an execution failure, every source remained
unchanged, and the parser source and corpus fingerprints remained unchanged.
This checkpoint passed **405 Dart tests**, **41 independent Python oracle
tests**, the DOC JavaScript acceptance and **40 media assertions** under Node,
static analysis, tracked-source formatting and a package dry run with no
warnings. The package was not published.

## What the native run establishes

All 19 cases retained their page count. **Seven cases matched the complete
source-DOC render**: page dimensions, page text, word boxes, layout text and RGB
raster output at 72 DPI. All three linked-textbox cases are in that group.
Both previously reviewed source-DOC goldens reproduced exactly on the recorded
environment. The other twelve cases have measured visual differences.

Every case still has differences in the strict OOXML structure comparison and
in the second-import comparison. Those findings include explicit/default
property rewrites and alternate representations, as well as real losses; the
comparison does not automatically dismiss a difference as harmless. Exact
pixels do not certify editable structures, revision semantics or a lossless
round trip. The comments, controls and altChunk cases also undergo a native
DOCX-to-DOC bridge that can lose features before this parser reads them. Their
exact rendered pages therefore do not establish support for every feature of
the original OOXML fixture.

| Case | Source → converted pages | Exact render | Maximum word drift (pt) | Semantic difference groups | Round-trip difference groups |
| --- | --- | --- | ---: | ---: | ---: |
| `formatting` | 1 → 1 | no | 11.902 | 9 | 5 |
| `word` | 1 → 1 | no | 18.902 | 10 | 5 |
| `word-compatibility` | 2 → 2 | no | not comparable | 8 | 5 |
| `table-borders` | 1 → 1 | no | 74.427 | 9 | 4 |
| `story-media` | 1 → 1 | no | 0.000 | 6 | 3 |
| `comment-threads` | 1 → 1 | yes | 0.000 | 6 | 3 |
| `note-markers` | 1 → 1 | no | not comparable | 14 | 5 |
| `bookmarks` | 1 → 1 | no | 3.050 | 8 | 5 |
| `content-controls` | 1 → 1 | yes | 0.000 | 8 | 5 |
| `content-controls-legacy` | 1 → 1 | yes | 0.000 | 8 | 5 |
| `word-altchunk` | 1 → 1 | yes | 0.000 | 7 | 4 |
| `linked-textboxes` | 1 → 1 | yes | 0.000 | 10 | 4 |
| `officeart-shapes` | 1 → 1 | no | 0.000 | 8 | 3 |
| `linked-textboxes-native` | 1 → 1 | yes | 0.000 | 10 | 4 |
| `emf-vectors` | 1 → 1 | no | 0.050 | 5 | 3 |
| `wmf-vectors` | 1 → 1 | no | 0.000 | 5 | 3 |
| `linked-textboxes-compact` | 1 → 1 | yes | 0.000 | 10 | 4 |
| `list-continue` | 1 → 1 | no | 24.909 | 6 | 6 |
| `list-restart` | 1 → 1 | no | 26.809 | 6 | 6 |

“Not comparable” means the page word sequence differed, so a paired maximum
word displacement would be misleading. A zero displacement can coexist with a
raster difference in shapes or images. Difference-group counts are inspection
locations, not counts of lost user features.

## Findings tied to fixes

- The three linked-textbox controls now reproduce exact RGB pages on this
  renderer. The independently measured kerning correction removed the earlier
  1.74-point word-width drift; it did not change the source text or invent line
  breaks. See [kerning evidence](kerning-fidelity.md).
- The OfficeArt and EMF/WMF cases, and both list second imports, formerly failed
  because native DOC output omitted CHPX coverage for its final paragraph mark.
  The [narrow boundary recovery](terminal-mark-formatting.md) handles only the
  independently verified pattern. The missing mark remains unknown, with
  formatting/revision limitations; interior gaps still fail.
- Continued and restarted lists keep their independently expected marker
  sequences: `1,2,3,4,5` and `1,2,7,8,3,9`. Their remaining page-size and word-box
  differences are visible in the table. The source controls omit explicit page
  geometry; native defaults and the converted document's defaults differ.
- The formatting control still drifts by 11.902 points; the broader Quds word
  control drifts by 18.902 points. Table/note and compatibility cases also have
  unresolved visual or content differences. These remain findings, not new
  expected output silently blessed by the harness.

See [the eight-area status matrix](fidelity-status.md) for the implemented
subsets and remaining acceptance work, including full review/protection policy,
arbitrary OfficeArt/GDI, dynamic table styles and general pagination.

## Complete retained evidence

The [readable summary](measurements/2026-11-12/summary.json) contains every case,
its hashes, warnings, conversion limitations, page comparison, source-golden
result and changed-property groups. The [compressed full native report](measurements/2026-11-12/native-report.json.gz)
retains **all** original structural differences, values and measurements; it is
not a filtered success report. The summary pins both compressed and decoded
report hashes. [Parser source hashes](measurements/2026-11-12/parser-source.json)
bind the runtime source, local dependency lock and conversion entry point to
the compiled executable fingerprint recorded in the report.

To inspect the complete report with the Python standard library:

```sh
python3 - <<'PY_REPORT'
import gzip, json
from pathlib import Path
path = Path('doc/measurements/2026-11-12/native-report.json.gz')
report = json.loads(gzip.decompress(path.read_bytes()))
print(json.dumps(report, indent=2))
PY_REPORT
```

The native runner retains generated DOC/DOCX/PDF files, color rasters and word
boxes in its chosen output directory. Those transient native products are not
new golden fixtures. The committed source inputs and the two reviewed golden
page records remain independently pinned.

## Environment and reproduction

- LibreOfficeDev `26.8.0.0.alpha0`, revision
  `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, already installed in this environment.
- `pdftoppm 26.05.0`, `pdftotext 25.03.0`; RGB renders at 72 DPI.
- Dart `3.13.7` on Linux x64.
- Full font inventory and font-file content fingerprints are recorded in the
  summary. Different fonts, native builds or rendering tools require fresh
  measurements; an environment mismatch cannot pass a reviewed golden.
- No Microsoft Word run or Open XML SDK validator run was available. These
  measurements do not establish exact Word behavior on Windows or macOS.

On the recorded source checkpoint, with existing Dart, Node, LibreOffice and
Poppler installations:

```sh
dart pub get
dart analyze
dart test
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
python3 tool/fidelity/oracle.py
python3 tool/fidelity/goldens.py
python3 tool/verify_web.py
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --output build/new-native-measurement
```

Use a new output directory. The runner neither installs Office nor executes
macros or updates document links. A normal zero exit status means the run
completed with unchanged inputs; it does not assert fidelity equality.
`--require-exact` is a separate strict gate and this corpus does not pass it.
`--require-goldens` additionally requires a reviewed matching source golden for
every selected case; it is appropriate only when selecting cases with such
records. Neither option updates or blesses expected output.
