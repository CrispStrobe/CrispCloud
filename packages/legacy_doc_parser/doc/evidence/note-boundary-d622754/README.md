# Note-table boundaries: three native cycles

This receipt measures `d622754b46ab4fd4e38ceed0c0fe4aa64dc23f2d`, based on
`713973f`, with the bounded final-note-table writer correction. The integrated
commit `aeb65b97d11859c771a49f5452a7db8dd375b9ae` has the same complete `lib/`
tree (`8ff2c257f9c1b0326147342ddcca482f2e6fe284`) and `pubspec.yaml` blob
(`6c9061f2deb12612990c3ac904f3fc6bd24776fd`). Its isolated validation checkout
also has the same resolved dependency lock, retained here as
`measured-pubspec.lock`. Use the pushed commit
`4f384e1d1de1bd22cb7d1865d3d653a5144601c5` for reproduction; its complete Git
tree equals `aeb65b9` (`18fa3a379043c336787462d1d2f1f02cecd08ec8`). The measured
source hashes are in the full report.
The measurement tools were untracked additions at measurement time; their
exact hashes are recorded, and their source is included in this evidence commit.

## Result

All sixteen independently authored controls completed their initial import and
three further DOCX → native DOC → parser DOCX cycles: **64 imports** in total.
Every parser output preserves its source note's parsed block sequence, text,
empty paragraphs and marker. There is no note-range trimming.

The original `table-borders.docx` is copied byte-for-byte for `footnote-table`.
That case remains `[paragraph, table]` at all four imports. Its parser DOCX
renders match the independently authored original exactly in page dimensions,
text, word rectangles and every RGB channel at 144 DPI. The `1Note` marker's
top stays at **682.0999755859375 points** at every import. The earlier
[6b2b611 receipt](../6b2b611/README.md) retained `[p,tbl,p]`, then successively
more paragraphs, with marker positions 668.65, 655.20, 641.75 and 628.30 points.

LibreOffice's playback of the final-table binary DOC still differs from the
authored original and parser output: its marker is at 695.5499877929688 points.
This native table interpretation remains a separate red comparison. Exact
original-to-parser output does not make native DOC playback exact.

| Control, for both note kinds | Authored block count | Parser counts: initial, cycle 1, cycle 2, cycle 3 | Native bridge changes to note blocks |
| --- | ---: | --- | --- |
| Plain | 1 | 1, 1, 1, 1 | None |
| Empty | 1 | 1, 1, 1, 1 | None |
| One trailing blank | 2 | 2, 2, 2, 2 | None |
| Two trailing blanks | 3 | 3, 3, 3, 3 | None |
| Final table | 2 | 2, 2, 2, 2 | None |
| Table followed by one blank | 3 | 4, 5, 6, 7 | One additional interior paragraph per bridge |
| Table followed by two blanks | 4 | 5, 6, 7, 8 | One additional interior paragraph per bridge |
| Table followed by text | 3 | 4, 5, 6, 7 | One additional paragraph before following text per bridge |

Ten controls retain their authored note structure through all cycles. Five
footnote controls also match their original authored pages exactly at every
import. Twelve controls are visually stable relative to their first parser
import, but two of those still accumulate structurally visible empty endnote
paragraphs. The structural checks therefore remain necessary even when pixels
do not change. All eight endnote controls have an original-to-binary bridge
layout difference before parser conversion; for example, the plain endnote
marker moves from 143.20 to 156.65 points on that bridge, and parser output
matches the resulting binary render exactly.

For table-plus-text controls, the raw binary range contains a CR between the
closed table's two `0x07` marks and `TAIL`, before the paragraph's final CR.
The global story-ending CR remains outside the range. The extra interior CR
is thus not a note guard that can safely be subtracted. Native DOCX projection
represents the note table in a frame-anchor paragraph. Restoring those floating
table semantics requires separate evidence and implementation; this correction
preserves the actual source paragraphs and does not pretend to resolve it.

## Independent schema result

The Open XML SDK 3.3.0 validator inspected **all 96 DOCX files**, with exact
path coverage and SHA-256 verification:

| Route | Files | Schema errors |
| --- | ---: | ---: |
| Independently authored OOXML controls | 16 | 0 |
| Parser DOCX, initial and all three cycles | 64 | 0 |
| LibreOffice DOCX projections of the binary inputs | 16 | 48 |

Each native projection has the same three unrelated exporter errors in its
main document: unsigned `docGrid/@charSpace="4294963199"`, table
`jc/@val="start"`, and `rStyle` child ordering. These native files and every
validator error remain retained. The original probe exited nonzero because
its SDK gate includes all routes. In version 1 of the probe, the aggregate
field named `writerContractPassed` also includes this global SDK gate and is
therefore false. Each of its 64 individual `writerPreservesSourceBlocks` checks
is true. `summary.json` reports that distinction explicitly; the raw report
has not been edited to turn the aggregate result green.

The production increment's focused tests passed 61 Dart tests. Six Python
oracle tests distinguish missing notes/markers, empty notes, lost or added
blank paragraphs, native frame alternatives and interior-CR placement.
The existing portable producer separately supplies sixteen literal binary
footnote/endnote controls to the central SDK gate.

## Retained evidence

- `native-report.json.xz`: complete original report bytes, including raw note
  CP/PLC ranges, code units, parsed and emitted blocks, word rectangles, RGB
  hashes and comparisons, all cycles, code hashes and the red SDK outcome.
- `schema-report.json.xz`: complete independent validator report, including
  the 48 native-export errors and hashes for all 96 inspected packages.
- `native-files.tar.xz`: all **304 exact artifacts**: 64 binary DOC inputs,
  96 DOCX files and 144 rendered PDFs. The 4,827,939 raw bytes compress to
  167,956 bytes. No Office document or PDF content is rewritten.
- `manifest.json`: every relative artifact path, size and hash, report hashes,
  and the deterministic archive settings.
- `summary.json`: explicit route attribution and per-control outcome.
- `environment.json`: supplemental installed-font and tool-file identities,
  recorded after the completed run; exact embedded PDF bytes are also retained.
- `note-focused-tests.log.xz` and `note-probe-tests.log.xz`: focused test logs.

Native measurements use LibreOfficeDev 26.8.0.0.alpha0
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, PyMuPDF 1.26.6 and the recorded
installed fonts. Microsoft Word was not executed. Equal results on this
renderer do not certify all Word editing, layout or round-trip behavior.

## Verify and inspect

The dependency-free verifier checks exact report bytes, all 304 artifact
hashes, complete schema coverage, the retained red native results, safe regular
file paths, fixed metadata and a byte-exact archive rebuild. Extraction requires
a new directory and occurs only after those checks pass:

```sh
python3 doc/evidence/note-boundary-d622754/verify.py
python3 doc/evidence/note-boundary-d622754/verify.py --extract build/note-boundary-evidence
```

A successful verification means these observations were retained faithfully;
it does not mean all native comparisons passed. The archive uses sorted USTAR
regular-file entries, mode `0644`, zero timestamps and owner/group IDs, empty
owner/group names, and XZ CRC64 with preset 9. Relative paths identify the
authored source, initial import (`import-00`) and three cycles (`import-01`
through `import-03`). Each import includes the exact binary input, converted
DOCX and binary/converted PDF. The initial import additionally retains native
DOCX playback. Absolute validator paths can be remapped using
`manifest.json`'s `sourceOutputDirectory`.

## Reproduce the measurement

Use the recorded production tree and dependency lock in an isolated checkout,
with `tool/fidelity/note_boundary_inspect.dart` and
`tool/fidelity/note_boundary_probe.py` from this evidence commit. The probe
authors its controls directly from the retained `table-borders.docx`, compiles
the normal parser adapter, uses isolated native profiles, retains every input
and output, and measures the original OOXML, native bridge and parser output
separately. It removes only its own completed native profile caches.

With an already built independent SDK validator and installed native tools:

```sh
python3 tool/fidelity/note_boundary_probe.py \
  --output build/note-boundary-reproduction \
  --office /path/to/soffice \
  --dart /path/to/dart \
  --dotnet /path/to/dotnet \
  --validator /path/to/OfficeValidation.dll
```

The default is sixteen controls, three cycles and 144 DPI. The retained native
SDK errors make this whole-corpus invocation return nonzero on the recorded
renderer. Inspect the route-specific schema results and the individual writer,
bridge and render comparisons; do not suppress the native errors or replace
the authored expected blank counts with generated output.
