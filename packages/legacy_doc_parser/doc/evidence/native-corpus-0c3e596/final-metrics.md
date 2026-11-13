# Independent comparison of final native source 0c3e596

All 24 cases and 72 repeat imports completed without execution/import errors.
Every original, regenerated binary and cycle input remained unchanged. The
independent archive verification checked 2,646 files, including 312 DOC/DOCX
files, 230 PDFs and 240 losslessly compressed RGB pages. The decoded pages
represent 343,330,104 PPM bytes. Exact source is
`0c3e59682952cce0e11301afec789e7ae2a1256a`.

The original reports remain authoritative. [final-comparison.json.xz](final-comparison.json.xz)
records each comparison against both historical baselines and
[final-independent-native-audit.json](final-independent-native-audit.json)
records the complete archive re-verification. Neither receipt is a new native
run.

## Aggregate measurements

| Metric | e90f38f | 7308125 | Final 0c3e596 |
| --- | ---: | ---: | ---: |
| Cases / completed repeats | 24 / 72 | 22 / 66 | 24 / 72 |
| Initial matching page counts | 24 / 24 | 22 / 22 | 24 / 24 |
| Initial matching page dimensions | 22 / 24 | 20 / 22 | 22 / 24 |
| Initial matching word sequences | 21 / 24 | 19 / 22 | 21 / 24 |
| Initial word geometry within 0.25 pt | 11 / 24 | 11 / 22 | 11 / 24 |
| Initial matching extracted layout text | 18 / 24 | 16 / 22 | 19 / 24 |
| Initial exact RGB, text and geometry | 6 / 24 | 6 / 22 | 6 / 24 |
| Repeats exact versus preceding import | 50 / 72 | 47 / 66 | 52 / 72 |
| Repeats exact versus first import | 40 / 72 | 37 / 66 | 42 / 72 |

The final source reproduces both reviewed source goldens, while one of the two
parser outputs matches its source golden. Strict initial structural equivalence
remains 0/24; those differences include representations and native export
behavior and are not automatically semantic-loss verdicts. All 72 repeats
preserve the comparison's page count and dimensions.

The six exact initial outputs remain `comment-threads`, `content-controls`,
`content-controls-legacy`, `word-altchunk`, `linked-textboxes`, and
`linked-textboxes-native`.

## Changes and remaining discrepancies

- **Table borders:** Initial maximum displacement remains 74.427 pt. All three
  repeats are now exact against both previous and first parser output. This
  restores the repeat stability already present in e90f38f and removes the
  13.45 pt/cycle regression in 7308125.
- **Note markers:** The initial word sequence still differs, so no initial
  maximum displacement can be calculated. All three repeats are now exact,
  removing the earlier 13.45 pt/cycle accumulation in both baselines.
- **Word 14 textboxes:** The initial word sequence and extracted layout text now
  match the source. Maximum corresponding-word displacement is 0.75 pt. Three
  cycles retain the sequence but move 0.05 pt per cycle, 0.15 pt cumulatively.
  Each regenerated binary DOC renders exactly like its parser conversion; this
  small repeat movement occurs across the native bridge. The earlier first-cycle
  RGB exact match is lost and is not suppressed in the comparison.
- **Word 16 page origin:** Initial displacement falls from 56.4 to 1.446 pt.
  Repeat metrics remain unchanged. The remaining initial discrepancy exceeds
  the 0.25-point tolerance and is not declared fixed.
- **Formatting:** Correct source font slots recover visible `東京` and retain
  the one visible source emoji. Native/old-parser text extraction duplicates the
  emoji token while omitting `東京`; final extraction has one of each. The
  resulting native sequence mismatch is not an emoji loss. See
  [font-attribution.md](font-attribution.md) and its actual rendered crops.
  The old 11.902-point maximum is now incomparable, not zero. All three repeats
  remain exact against first and previous parser output.
- **Shared header textboxes:** Both cases retain the e90f38f behavior: 0.35 pt
  initial displacement, then 0.35 / 0.70 / 1.05 pt cumulatively across repeats.
  These are pre-existing border/frame discrepancies. The cases were absent
  from the 22-case 7308125 corpus.
- **Lists:** Both native A4/parser Letter differences remain. Their absent
  source page-size properties and source-defined Letter default have separate
  documented attribution. No page-size change is hidden by equal page counts.

No unexpected rendering regression was identified. The Word 14 repeat pixel
change and the altered formatting word-sequence comparison remain explicit,
with the source/native attribution above. This is not an exact-fidelity or
complete semantic-preservation certification.

## Final per-case metrics

A “sequence differs” value is not comparable; it never means zero drift.
Repeat exactness means RGB, extracted text and word geometry together.

| Case | Initial maximum drift, pt | Initial exact | Repeats exact vs previous | Repeats exact vs first | Third cycle drift vs first, pt |
| --- | ---: | --- | ---: | ---: | ---: |
| bookmarks | 3.050 | no | 3/3 | 3/3 | 0.000 |
| comment-threads | 0.000 | yes | 3/3 | 3/3 | 0.000 |
| content-controls | 0.000 | yes | 3/3 | 3/3 | 0.000 |
| content-controls-legacy | 0.000 | yes | 3/3 | 3/3 | 0.000 |
| emf-vectors | 0.050 | no | 3/3 | 3/3 | 0.000 |
| formatting | sequence differs | no | 3/3 | 3/3 | 0.000 |
| header-textbox-alias | 0.350 | no | 0/3 | 0/3 | 1.050 |
| header-textbox-first-enabled | 0.350 | no | 0/3 | 0/3 | 1.050 |
| linked-textboxes | 0.000 | yes | 2/3 | 0/3 | 0.000 |
| linked-textboxes-compact | 0.000 | no | 2/3 | 0/3 | 0.000 |
| linked-textboxes-native | 0.000 | yes | 2/3 | 0/3 | 0.000 |
| list-continue | 24.909 | no | 3/3 | 3/3 | 0.000 |
| list-restart | 26.809 | no | 3/3 | 3/3 | 0.000 |
| note-markers | sequence differs | no | 3/3 | 3/3 | 0.000 |
| officeart-shapes | 0.000 | no | 1/3 | 0/3 | 0.000 |
| poi-simple-table2 | 0.300 | no | 2/3 | 0/3 | 0.300 |
| story-media | 0.000 | no | 3/3 | 3/3 | 0.000 |
| table-borders | 74.427 | no | 3/3 | 3/3 | 0.000 |
| wmf-vectors | 0.000 | no | 3/3 | 3/3 | 0.000 |
| word | 18.000 | no | 3/3 | 3/3 | 0.000 |
| word-altchunk | 0.000 | yes | 3/3 | 3/3 | 0.000 |
| word-compatibility | sequence differs | no | 0/3 | 0/3 | sequence differs |
| word14-margin-origin | 0.750 | no | 0/3 | 0/3 | 0.150 |
| word16-page-origin | 1.446 | no | 1/3 | 0/3 | 0.000 |

## Environment and references

All 24 original source hashes match e90f38f; all 22 common source hashes match
7308125. The final corpus manifest matches e90f38f. All 22 common native binary
and native-export render fingerprints exactly match their retained 7308125
references. Native bridge and native-export comparison metrics are unchanged
against both baselines. Thus the changed parser measurements are not explained
by a newly changed initial native reference.

Recorded renderer, compiler, Poppler text extractor/rasterizer and installed
font identities match both historical baselines. The 7308125 `pdfinfo` identity
also matches; the older e90f38f receipt does not separately record it. Final
source/build identities agree across all 24 clean independently receipted runs.
Changed source fingerprints are listed rather than treated as environment drift.

The audit was reproduced from the workspace root with:

```sh
python3 validation/compare_native_corpus.py \
  --before legacy-doc-parser/doc/evidence/e90f38f \
  --after validation/native-0c3e596 \
  --output validation/final-native-vs-e90f38f.json
python3 validation/compare_native_corpus.py \
  --before legacy-doc-parser/doc/evidence/native-corpus-7308125 \
  --after validation/native-0c3e596 \
  --output validation/final-native-vs-7308125.json
```

For each completed case, the independent audit also ran
`verify_native_artifacts.py --directory SEALED_CASE_DIRECTORY` from
`doc/evidence/native-corpus-7308125/`. It checked every archive member and every
decoded RGB page, then reconciled the results with the final atomic index.
