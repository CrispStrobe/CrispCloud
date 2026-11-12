# Native corpus continuation at 7308125

## Completed measurement

All **22 source cases and 66 requested repeat imports completed without
execution or import errors**. All 22 initial page counts match (23 pages on
each side), and every repeat import retains its comparison's page count.
Six initial comparisons match RGB pixels, extracted layout text and word
geometry exactly. Both reviewed source goldens reproduce; the parser output
matches one of those two goldens. All strict structural comparisons still
report differences. Successful measurement is not an exact-fidelity pass.

`index.json` is the unchanged final atomic receipt, completed at
2026-11-12 20:32:16 UTC. Each case retains its complete losslessly compressed
report, verified input/output/PDF/text/geometry/raster archive and exact
manifest. [summary.json](summary.json) derives the aggregate and preserves
every initial and repeat rendering comparison, separately from the original
reports. The [portable/schema receipt](../continuation-7308125/README.md)
records the independent 725-Dart, 130-Python and 196-DOCX checks.

| Initial comparison with native binary DOC | Result |
| --- | ---: |
| Same page count | 22 / 22 |
| Same page dimensions | 20 / 22 |
| Same per-page word sequences | 19 / 22 |
| Word geometry within 0.25 pt | 11 / 22 |
| Same extracted layout text | 16 / 22 |
| Exact RGB, text and geometry together | 6 / 22 |
| Strict structural equivalence to native-exported DOCX | 0 / 22 |
| Reviewed source render goldens reproduced | 2 / 2 |
| Parser outputs matching those source goldens | 1 / 2 |

The six exact initial renders are `comment-threads`, `content-controls`,
`content-controls-legacy`, `word-altchunk`, `linked-textboxes` and
`linked-textboxes-native`. Their structural snapshots still differ. The
`formatting` source golden reproduces, but its parser output has 11.902 pt
maximum word displacement. The other source golden,
`linked-textboxes-native`, also matches the parser's first render.

## Per-case rendering and repeat stability

The first comparison uses the binary DOC as the rendering reference. For the
14 original DOCX inputs, the original-to-binary bridge is also retained and
measured separately: all 14 bridge page counts agree, while only three bridge
renders are exact. This prevents a native bridge loss from being silently
attributed to the parser.

The repeat columns count exact RGB/text/geometry matches across three cycles.
Each cycle exports the previous parser DOCX back to binary DOC, then imports
that DOC again. Stability is measured both against the preceding parser import
and against the first parser import. A null word-drift metric means that word
sequences differ, so corresponding-word displacement cannot be calculated.

| Case | Native/parser pages | Initial maximum word drift, pt | Initial render exact | Repeats exact vs preceding | Repeats exact vs first |
| --- | ---: | ---: | --- | ---: | ---: |
| formatting | 1/1 | 11.902 | no | 3/3 | 3/3 |
| word | 1/1 | 18.000 | no | 3/3 | 3/3 |
| word-compatibility | 2/2 | text differs | no | 0/3 | 0/3 |
| table-borders | 1/1 | 74.427 | no | 0/3 | 0/3 |
| story-media | 1/1 | 0.000 | no | 3/3 | 3/3 |
| comment-threads | 1/1 | 0.000 | yes | 3/3 | 3/3 |
| note-markers | 1/1 | text differs | no | 0/3 | 0/3 |
| bookmarks | 1/1 | 3.050 | no | 3/3 | 3/3 |
| content-controls | 1/1 | 0.000 | yes | 3/3 | 3/3 |
| content-controls-legacy | 1/1 | 0.000 | yes | 3/3 | 3/3 |
| word-altchunk | 1/1 | 0.000 | yes | 3/3 | 3/3 |
| linked-textboxes | 1/1 | 0.000 | yes | 2/3 | 0/3 |
| officeart-shapes | 1/1 | 0.000 | no | 1/3 | 0/3 |
| linked-textboxes-native | 1/1 | 0.000 | yes | 2/3 | 0/3 |
| emf-vectors | 1/1 | 0.050 | no | 3/3 | 3/3 |
| wmf-vectors | 1/1 | 0.000 | no | 3/3 | 3/3 |
| linked-textboxes-compact | 1/1 | 0.000 | no | 2/3 | 0/3 |
| list-continue | 1/1 | 24.909 | no | 3/3 | 3/3 |
| list-restart | 1/1 | 26.809 | no | 3/3 | 3/3 |
| word14-margin-origin | 1/1 | text differs | no | 1/3 | 1/3 |
| word16-page-origin | 1/1 | 56.400 | no | 1/3 | 0/3 |
| poi-simple-table2 | 1/1 | 0.300 | no | 2/3 | 0/3 |

Across all cycles, **47/66 renders are exact versus the preceding import and
37/66 versus the first import**. Twelve documents remain exact relative to
their first import for all three cycles. This is repeat stability, not
equivalence to the source. Every strict cycle comparison differs from the
native-exported DOCX, the preceding parser import and the first parser import.
Those snapshots include representation changes; a difference count alone
cannot establish semantic loss or assign it to the native bridge or parser.

The largest comparable initial displacement is 74.427 pt in `table-borders`.
`table-borders` and `note-markers` accumulate 13.45 pt per repeat, reaching
40.35 pt from the first parser import after three cycles. `list-continue` and
`list-restart` retain page count but change from A4
(595.303937 × 841.889764 pt) to Letter (612 × 792 pt). Textbox and
OfficeArt cases can retain word positions while pixels change. These are
specific remaining problems, not failures hidden by equal page counts.

The new header/footer table-boundary recovery is tested by
[four separate retained native controls](../header-table-boundary-20261112/README.md)
and the schema gate. Those controls are not counted among these 22 corpus
documents. The rejected textbox-depth reset is absent from this source.

## Source and execution identity

All measurements use clean parser commit
`730812534e8dc045d6d97f600218228f05c51b97`. Each source runs through a separate
normal `tool/fidelity/run.py --case ID --roundtrip-cycles 3 --raster-storage gzip`
invocation. This is a serial collection of independently receipted runs, with
compiler/source/renderer/font consistency checked across them. Every invocation
retains its own compiled-executable identity; it is not represented as one
uninterrupted invocation.

All 22 runs record identical compiler, source-input, native renderer, Poppler
and font fingerprints; all independently compiled executable hashes also
agree. Each run records 126 runtime/configuration/harness source hashes and
confirms unchanged inputs during compilation. Every original source, native
binary input and repeat input remains byte-identical through its measurement.

The renderer was LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, with Poppler 26.05.0 at 72 DPI.
The compiler was Dart 3.13.7 stable on Linux x64. Full paths, executable hashes,
font inventories and per-stage commands remain in the reports. Microsoft Word
was not executed. No golden was updated.

## Retained artifacts and verification

The wrapper seals and independently verifies each completed case before removing
only that case's generated raw directory. Original inputs, native DOC bridges,
converted DOCX, PDFs, text, bounding boxes, compressed RGB pages and stage records
are retained in the per-case archives. Generated Office profiles and the
compiled executable are excluded; the executable hash and full build/source
receipt remain in each report. Every compressed raster is bound to its exact
page, raw PPM hash, compressed hash and render/storage receipts.

The 22 archives retain **2,438 files**, including **286 DOC/DOCX files,
212 PDFs and 222 compressed RGB pages**. They occupy 3,547,388 bytes;
the retained artifact files total 187,580,816 bytes before the outer archive
compression. The gzip pages losslessly represent 317,155,818 raw PPM bytes.
The complete native reports total 152,835,771 uncompressed bytes and 552,640 XZ
bytes. These totals contain deliberate duplicate evidence; they are not a
unique-content size claim.

`execution-logs.tar.gz` retains all 66 per-case measurement/sealing/verification
logs, the full orchestration log and the five wrapper lifecycle-test results.
Its manifest binds all 68 original log byte streams. [independent-native-audit.json](independent-native-audit.json) records a later
re-verification of all 2,438 members and 222 decoded pages; it is not another
native run.

Run `python3 verify_native_artifacts.py --directory sealed/01-formatting` from
this directory to verify a case; add `--extract NEW_DIRECTORY` to extract only
after verification. The standalone scripts are copied unchanged from this
execution, and the three execution-helper hashes are pinned by the index.
The wrapper requires an
exact clean source checkpoint and refuses incomplete-output overwrites.

Verify all case archives and reproduce the derived summary from this directory:

```sh
for case in sealed/*; do
  python3 verify_native_artifacts.py --directory "$case" || exit 1
done
python3 summarize_native_corpus.py --directory . > /path/to/new-summary.json
cmp summary.json /path/to/new-summary.json
```

The independent verifier checks report and archive hashes, exact safe member
paths and bytes, each decoded RGB page, and the page's binding to the measured
render and storage manifests. The summarizer reads the original reports,
checks their index/archive identities and source/environment consistency, then
derives the metrics above. It does not edit measured reports or update goldens.

To repeat native measurement, retain these scripts outside a clean checkout of
the recorded source and provide explicit tool paths and a new output directory:

```sh
python3 /path/to/evidence/run_bounded_corpus.py \
  --parser /path/to/clean-parser-checkout \
  --expected-commit 730812534e8dc045d6d97f600218228f05c51b97 \
  --office /path/to/soffice --dart /path/to/dart \
  --output /path/to/new-native-run
```

The sealer and verifier must remain beside the wrapper. The wrapper checks
free disk space, records each independent invocation, seals and verifies a
case before cleanup, and supports explicit `--resume` of verified completed
cases. It preserves a failed or incomplete raw directory and refuses to
overwrite it automatically. Reproducing exact pixels also requires the
recorded native renderer, Poppler versions and fonts.

Equal page counts, exact rendering and structural equivalence are reported
separately. No difference is silently converted into a pass.
