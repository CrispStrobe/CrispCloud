# Complete native corpus at 48bf3a

All **24 initial cases and 72 repeat imports completed with zero execution or
import errors** on clean runtime
`48bf3a84e822b960e369f0134d597e025c775a41`, tree
`a952a0b5930baf97728120e6f34062586df89d11`. Both explicit-border header textbox
cases now render exactly, initially and through all three cycles. Word16's
initial word geometry is exact. Remaining differences are retained below;
completion does not establish universal fidelity.

## Results and comparison

The comparison is against the complete [0c3e596 corpus](../native-corpus-0c3e596/README.md).
All 24 source inputs and initial native binary DOC files have identical bytes
between runs. Renderer, installed font inventory and files, corpus manifest,
and the compiler, Office and three Poppler tool identities also match.

| Measurement | 0c3e596 | 48bf3a |
| --- | ---: | ---: |
| Initial page counts match | 24 / 24 | 24 / 24 |
| Initial page dimensions match | 22 / 24 | 22 / 24 |
| Initial per-page word sequences match | 21 / 24 | 21 / 24 |
| Initial word geometry within 0.25 pt | 11 / 24 | **14 / 24** |
| Initial extracted layout text matches | 19 / 24 | 19 / 24 |
| Initial exact RGB, text and word geometry | 6 / 24 | **8 / 24** |
| Repeat exact versus regenerated binary DOC | 33 / 72 | **39 / 72** |
| Repeat exact versus preceding parser import | 52 / 72 | **58 / 72** |
| Repeat exact versus first parser import | 42 / 72 | **48 / 72** |

All 72 repeat page counts and dimensions match. Repeat geometry is within
0.25 pt in 51/72 comparisons to regenerated binary DOC, 67/72 to the previous
import, and 63/72 to the first import. All strict structural comparisons still
report differences; those counts include representation and bridge changes
and are not a semantic-loss verdict. Both reviewed source-render goldens
reproduce; one of the two parser outputs matches its source golden.

The 14 original DOCX-to-binary bridges retain matching page counts and
dimensions, with 3/14 exact renders. These bridge comparisons are separate
from the initial binary-DOC-to-parser-DOCX comparisons above.

### Established changes and remaining differences

- **Header textbox alias and first-enabled controls:** initial maximum word
  displacement falls from 0.35 pt to zero. Every repeat comparison is now
  exact, removing the previous 0.35 pt per-cycle movement and 1.05 pt cumulative
  displacement. Raw source coordinates and explicit frame evidence remain
  distinct in the parser model.
- **Word16:** initial displacement falls from 1.446 pt to zero, with matching
  page size, words and extracted layout text. Raster differences remain.
  The first native DOC export changes the source width-balancing flag; the
  1.446 pt difference returns in cycle one and remains unchanged in cycles two
  and three. The comparison therefore explicitly records a cycle-one
  previous-import tolerance loss and three first-import tolerance losses.
  Every later binary/parser render fingerprint is identical to the prior
  corpus: the improved initial reference exposes the existing bridge behavior.
  See the [source flag and native implementation evidence](../compatibility-width-balance-20261113/README.md).
- **Word compatibility:** aggregate pass/fail metrics remain unchanged, but
  section-one `w:bidi` and `w:rtlGutter` now preserve the source direction.
  The first `UNSELECTED` body word moves from x=234.65 pt to x=600.65 pt,
  matching the unchanged native binary's x=600.65 pt. All word sequences are
  unchanged between corpora, and the first-page header boxes are unchanged.
  Existing note and line-number differences remain. The compact review retains
  the exact XML and render-member hashes and sampled word boxes.
- **Word14:** initial displacement remains 0.75 pt. The bridge adds 0.05 pt
  per cycle, reaching 0.15 pt cumulatively; each regenerated binary and parser
  output remains exact. No implicit stroke-width correction is claimed for
  the six effect-heavy textboxes.
- **Notes, tables and defaults:** the stable table-note cases remain exact
  relative to their first parser import. `table-borders` retains its initial
  74.427 pt displacement against the native flattened representation; the
  [authored table oracle](../table-note-oracle-20261113/README.md) and
  [literal note-marker/numbering audit](../note-source-attribution-20261113/README.md)
  retain separate attribution. Two list inputs still exercise source-defined
  Letter defaults versus native A4 selection. Formatting retains source
  Japanese text and one emoji despite native extraction differences.

Only the two header cases and Word16 change initial metrics. Twenty cases
retain every recorded render fingerprint. The fourth case with changed render
fingerprints is the source-aligned Word-compatibility direction correction.
There are no new initial metric losses. The measured repeat tolerance losses
are the Word16 bridge behavior stated above; this does not qualify all remaining
differences as acceptable or prove fidelity in Microsoft Word.

## Identity and retained evidence

The corpus consists of 24 sequential independent runner invocations, each
compiling and measuring three repeat imports. All runs retain the same clean
source/compiler/renderer/font fingerprint, all 138 captured runtime,
configuration and harness inputs remain unchanged, and the independently
compiled executables have one identical hash. Original and cycle input bytes
remain unchanged throughout measurement.

The renderer is LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, with Poppler `pdftoppm` and
`pdfinfo` 26.05.0, `pdftotext` 25.03.0, 72-DPI RGB rasters and Dart 3.13.7.
Microsoft Word was not executed.

The unchanged original `index.json` and 24 report/archive/manifest sets retain
**2,646 artifact files**, including **312 DOC/DOCX files, 230 PDFs and 240
compressed RGB pages**. Artifact archives total **3,572,156 bytes**; compressed
reports total **598,108 bytes**. Their original report streams total
156,200,647 bytes. Artifact member bytes total 192,732,113, and compressed
rasters losslessly represent 343,330,104 raw PPM bytes. Counts include deliberate
duplicate evidence across separately receipted stages.

`independent-artifact-verification.json` records successful re-verification of
all 24 seals, every artifact member and all 240 decompressed raster pages.
`execution-logs.tar.gz` retains all 72 measurement/sealing/verification logs
and the wrapper console log, with exact member hashes in its manifest.
Temporary native profiles and rebuildable executables are omitted from the
case archives; their relevant provenance remains in the original reports.

`summary.json` preserves every initial and repeat result. The complete
comparison is retained losslessly as `comparison-vs-0c3e596.json.xz`;
`comparison-review.json` provides a compact per-case review and the additional
archived section-direction observations. `final-review-files.manifest.json`
binds every file in this folder except itself, including compressed and raw
comparison hashes. Packaging and review did not alter the measured runtime,
original index, reports, seals or error observations.

## Verification and reproduction

The six bounded-runner, sealing, verification, summary, comparison and wrapper
test helpers are byte-identical copies from the previous evidence folder.
The compact review script is a later read-only inspection, not a measurement
harness change. Run the inherited verification and derivation helpers with
normal Python, without `-O`, `-OO` or `PYTHONOPTIMIZE`: their integrity checks
use assertions. The new compact review script explicitly refuses optimized
Python. From this folder:

```sh
python3 verify_native_artifacts.py --directory sealed/01-formatting
python3 summarize_native_corpus.py --directory . > /path/to/new-summary.json
cmp summary.json /path/to/new-summary.json
python3 review_comparison.py
```

Repeat the first command for every directory under `sealed/`. The verifier
checks safe archive paths, exact member bytes and hashes, compressed and raw
rasters, and their binding to original render/storage receipts. Reproduce the
full comparison with unchanged helpers and the retained baseline:

```sh
python3 compare_native_corpus.py --before ../native-corpus-0c3e596 \
  --after . --output /path/to/new-comparison.json
```

The comparison embeds input paths; absolute-path spellings may differ when
reproduced elsewhere, while metric and content hashes remain comparable.
To rerun native measurement, use the copied `run_bounded_corpus.py` outside a
clean checkout of the recorded commit, explicit `--office` and `--dart` paths,
`--expected-commit 48bf3a84e822b960e369f0134d597e025c775a41`, a new `--output`
directory and `--roundtrip-cycles 3`. Measurement completion permits reported
differences; the underlying `tool/fidelity/run.py --require-exact` applies the
strict renderer gate. Reviewed goldens are never updated automatically.
