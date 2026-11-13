# Complete native corpus at 0c3e596

All **24 initial source cases and 72 requested repeat imports completed with
zero execution/import errors** on clean runtime
`0c3e59682952cce0e11301afec789e7ae2a1256a`, tree
`e763288ee642c26854572e1cae212c36bf683918`. Every initial and repeat page count
matches its comparison. Six initial renders are exact; completing measurement
does not establish universal fidelity.

## Results

| Initial binary-DOC versus parser-DOCX comparison | Result |
| --- | ---: |
| Equal page counts | 24 / 24 |
| Equal page dimensions | 22 / 24 |
| Equal per-page word sequences | 21 / 24 |
| Word geometry within 0.25 pt | 11 / 24 |
| Equal extracted layout text | 19 / 24 |
| Exact RGB, text and word geometry together | 6 / 24 |
| Strict structural equivalence to native-exported DOCX | 0 / 24 |
| Reviewed source-render goldens reproduced | 2 / 2 |
| Parser outputs matching those source goldens | 1 / 2 |

Across all 72 cycles, 52 renders are exact versus the preceding parser import
and 42 versus the first import. All repeat page counts and dimensions match.
Every strict structural comparison still reports differences. Representation
differences require inspection before they can be classified as semantic loss.

The fourteen original DOCX inputs also retain and measure their original to
binary DOC bridge: all fourteen page counts and dimensions match, while only
three bridge renders are exact. Each repeated binary-to-parser comparison is
retained separately from changes introduced by the native bridge.

## Changes established by this checkpoint

`table-borders` and `note-markers` now reproduce their first parser import
exactly through all three cycles, removing the historical 13.45-point movement
per cycle. Their initial differences remain: `table-borders` has 74.427-point
maximum displacement, while `note-markers` has differing word sequences.
Repeat stability must not be confused with source-render equivalence.

The Word16 source's initial maximum word displacement falls from the historical
56.4 points to 1.446 points. The final floating-table origin no longer moves
on repeated imports. The remaining 1.446-point displacement is confined to the
middle word `für`; the first and third words match. Word geometry stays fixed
through all cycles, while some raster differences remain.

The Word14 six-textbox source now retains its word sequence and extracted
layout text after restoring the explicit 3.6-point wrapping clearances. Its
initial maximum displacement is 0.75 points. Each repeat moves 0.05 points
relative to the preceding import, reaching 0.15 points cumulatively. Each
regenerated binary DOC and its parser output render exactly alike, which
attributes that small repeated change to the native bridge. The rejected
automatic 0.75-point stroke default is absent from this runtime.

Both header textbox fixtures import successfully through all three cycles.
Their pre-existing 0.35-point-per-cycle positioning difference remains; this
checkpoint does not claim that their frame geometry is exact.

The two list cases still render with different page dimensions: their source
bytes omit page-size properties, the binary specification defaults to Letter,
and LibreOffice selects A4. The converter preserves the source-defined default.
Equalizing those renderer defaults is not a source-data correction.

The formatting case's changed word sequence is the script-font correction.
The final visible text contains `東京` and one emoji, matching its literal DOCX
text. The binary reference omits the visible Japanese text and its text
extraction duplicates the emoji token. The final emoji remains present. A null
maximum-word-drift value denotes incomparable sequences, not zero drift or
proof of lost source text.

## Runtime and evidence identity

The corpus ran as 24 separate sequential invocations of the ordinary fidelity
runner, each with three cycles and lossless gzip raster storage. Each run
records the exact clean source, independent compiler/build identity and all
stage commands. All runs share one source/compiler/renderer/font fingerprint;
all 138 runtime/configuration/harness input hashes and original/cycle inputs
remain unchanged. The separately compiled executables have one identical hash.

The renderer is LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, with Poppler 26.05.0 at 72 DPI and
Dart 3.13.7. Microsoft Word was not executed. The
[portable/schema receipt](../continuation-0c3e596/README.md) separately records
918 Dart tests, 162 Python controls, JavaScript acceptance, 228 required DOCX
packages and 21 extra table packages.

The unchanged atomic `index.json` and 24 complete report/archive/manifest sets
retain **2,646 files**, including **312 DOC/DOCX files, 230 PDFs and 240 compressed
RGB pages**. Artifact archives total 3,621,004 bytes; complete report archives
total 603,784 bytes. The raw report byte streams total 157,765,703 bytes, and the
compressed pages losslessly represent 343,330,104 raw RGB PPM bytes. Counts
include deliberate duplicate evidence across separately receipted stages.

`execution-logs.tar.gz` retains all 72 per-case measurement/sealing/verification
logs and the orchestration console log, with exact hashes in its manifest.
Temporary Office profiles and compiled executables are omitted from case
archives; their relevant identities remain in the original reports.

The derived `summary.json` preserves every initial and repeat comparison and
can be regenerated from the unchanged reports. Historical comparisons use both
the 24-case e90f38f baseline and 22-case 7308125 baseline; the latter excludes
the two header controls. Earlier failed candidates and receipts retain their
original identities.

The [independent per-case comparison](final-metrics.md) lists every case and
changed metric against both baselines. Its complete comparison JSON files are
retained losslessly as XZ, with compressed and raw byte hashes in
`final-review-files.manifest.json`. That manifest also binds the separate
24-case archive re-verification and [font attribution](font-attribution.md),
including literal source operands, DOCX XML observations, unchanged measured
PDFs and actual diagnostic PNG crops. These later inspections do not represent
another native corpus execution.

## Verification and reproduction

The helper scripts are unchanged from the measured bounded runner. Verify a
case without extracting it:

```sh
python3 verify_native_artifacts.py --directory sealed/01-formatting
```

Repeat for each directory under `sealed/`. The verifier checks exact safe
archive paths and member bytes, compressed and raw raster hashes, and their
binding to render/storage receipts. To regenerate the aggregate:

```sh
python3 summarize_native_corpus.py --directory . > /path/to/new-summary.json
cmp summary.json /path/to/new-summary.json
```

To rerun measurements, keep the wrapper, sealer and verifier beside one another
outside a clean checkout of the recorded runtime, and provide explicit tools
and a new output directory:

```sh
python3 /path/to/evidence/run_bounded_corpus.py \
  --parser /path/to/clean-parser \
  --expected-commit 0c3e59682952cce0e11301afec789e7ae2a1256a \
  --office /path/to/soffice --dart /path/to/dart \
  --output /path/to/new-native-run --roundtrip-cycles 3
```

The normal measurement command succeeds when measurement completes, including
reported differences. The underlying `tool/fidelity/run.py --require-exact`
requires exact comparisons. Neither mode updates reviewed source goldens
automatically.
