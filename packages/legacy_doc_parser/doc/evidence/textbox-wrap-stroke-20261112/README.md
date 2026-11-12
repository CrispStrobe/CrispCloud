# Textbox wrap clearances and withdrawn stroke default

These receipts retain the Word 14 wrap-clearance fix and the native
counterexample that caused automatic textbox stroke defaults to be withdrawn.
The source DOC, the native export and the parser output are measured separately.
The source bytes and earlier unsuccessful candidate have not been replaced.

## Decision and measured scope

Preserving six explicit 3.6-point top/bottom wrapping clearances restores the
source's word sequence and extracted layout text. The initial output still has
up to 0.75 points of corresponding-word displacement and differs in RGB pixels.
Three wrap-only repeat imports preserve the word sequence, with 0.05 points of
additional displacement per cycle, 0.15 points cumulatively from the first
parser output. Those repeat comparisons are within the existing 0.25-point
word-position tolerance; they are not RGB-exact.

Materializing the absent source stroke width as 0.75 points improves the initial
maximum displacement to 0.40 points, but the first two repeated imports each
add 0.35 points and the third changes reading order. This is a native regression,
despite passing focused model tests. The writer therefore leaves an absent
textbox width unforced. Explicit widths and the specification-backed operand
validation remain. See [the stroke retraction](../../textbox-stroke-defaults.md)
for the remaining source/target frame-border contract and primary references.

| Receipt | Clean parser commit | Initial source word sequence / layout text | Initial maximum word drift | Repeated-import result |
| --- | --- | --- | --- | --- |
| [Baseline](baseline/native-artifacts.manifest.json) | `d11fa0e297f8058c8048c71537f2392457baa624` | Both differ | Not comparable because word sequence differs | Not requested |
| [Wrap only, initial](wrap-only/native-artifacts.manifest.json) | `ab575729720f0b6f7f2316e8613e7780be950356` | Both match | 0.75 pt | Not requested |
| [Wrap only, three cycles](wrap-repeat/native-artifacts.manifest.json) | `ab575729720f0b6f7f2316e8613e7780be950356` | Both match | 0.75 pt | Word sequence and layout text match through all three; cumulative 0.05 / 0.10 / 0.15 pt |
| [Withdrawn stroke default, three cycles](stroke-default/native-artifacts.manifest.json) | `832b51ace136c3a15fa8ac668dd401cfca2924a7` | Both match | 0.40 pt | Cumulative 0.35 / 0.70 pt, then changed word sequence in cycle three |

All four executions render one page at the same page dimensions. None of their
initial parser comparisons is exact in RGB or within the 0.25-point word-position
tolerance. The native DOCX export also changes the source word sequence in all
four runs; it is retained as a separate observation, not used as the sole layout
oracle. A missing drift value means corresponding words cannot be compared,
not that drift is zero.

For the wrap-only repeats, each regenerated binary DOC renders exactly like
the parser's conversion of that same DOC on this renderer. The small cumulative
changes occur across the native DOCX-to-DOC bridge. For the withdrawn candidate,
each of the first two regenerated binary DOCs also differs from its subsequent
parser conversion by 0.35 points. The failed stroke result cannot therefore be
attributed entirely to the native bridge.

## Exact source and runtime

The input is the existing `test/fixtures/word_native/word14-margin-origin.doc`
fixture, SHA-256
`cab742e55b62e7a638ada283e877144a574e0412032ac5d797c1eb8cfedcfb9a`.
Every report records a clean parser worktree, unchanged source bytes and
unchanged regenerated binary inputs. Every run uses LibreOfficeDev
`26.8.0.0.alpha0`, build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.
The complete reports retain compilation identity, parser source fingerprints,
font inventory, Poppler identity and raster settings.

The explicit wrap operands are OfficeArt `0x0385` and `0x0387`, each
`45720` EMU = 3.6 pt, in all six source textboxes. Their paired `1Table` record
offsets start at 5595, 7602, 12007, 13991, 15976 and 26158; each bottom record
follows six bytes after its top record. Left/right distances are absent.
[Implementation and source specification references](../../officeart-wrap-distances.md)
describe how explicit distances remain distinct from missing properties,
textbox inner insets and wrap mode.

The diagnostic [Dart helper](inspect_textbox_geometry.dart) and retained
[JSON lines](textbox-geometry-inspection.jsonl) expose source shape coordinates,
line widths, insets and origin properties for Word 14, the independent shared
header controls, and the candidate's first native regeneration. The helper is
a parser inspection tool, not an independent layout oracle. Its formatted
source is semantically identical to the helper used for the retained output.
The shared-header records retain their explicit 9525-EMU border and source
rectangle, including the previously observed 0.35-point placement difference.
No blanket origin adjustment or rejected table-depth reset is part of this
change.

## Retained files and verification

The four subdirectories contain 278 individual archived files and 24 compressed
RGB page rasters in total. Each contains the original run report compressed as
`native-report.json.xz`, a `native-artifacts.tar.xz` archive, and a manifest of
the archive and its individual members. Archives include the exact DOC inputs,
DOCX outputs, exported PDFs, word bounds, extracted text, raster manifests,
conversion logs and regenerated DOC files where applicable. No image was
resampled to obtain a smaller artifact. The verifier checks compressed and
decompressed raster hashes as well as archive members.

[summary.json](summary.json) exposes the measurements without replacing the
full reports. Its log section records hashes of both compressed and raw log
bytes. The native runner's short console logs only report completion; the
full native reports and artifacts carry the actual measurements.

Run each manifest verification from the repository root:

```sh
python3 doc/evidence/native-corpus-7308125/verify_native_artifacts.py \
  --directory doc/evidence/textbox-wrap-stroke-20261112/baseline
python3 doc/evidence/native-corpus-7308125/verify_native_artifacts.py \
  --directory doc/evidence/textbox-wrap-stroke-20261112/wrap-only
python3 doc/evidence/native-corpus-7308125/verify_native_artifacts.py \
  --directory doc/evidence/textbox-wrap-stroke-20261112/wrap-repeat
python3 doc/evidence/native-corpus-7308125/verify_native_artifacts.py \
  --directory doc/evidence/textbox-wrap-stroke-20261112/stroke-default
```

To reproduce a run, create an isolated checkout at the commit in the table and
use the recorded renderer, fonts and Dart toolchain. Run from that checkout,
selecting a new output directory. The two initial-only receipts used zero
cycles; both repeat receipts used three:

```sh
python3 tool/fidelity/run.py \
  --office /path/to/recorded/soffice \
  --dart /path/to/recorded/dart \
  --output build/textbox-reproduction \
  --case word14-margin-origin \
  --roundtrip-cycles 3 \
  --raster-storage gzip
```

## Focused validation attribution

`wrap-focused.log.gz` records 99 passing focused tests on local checkpoint
`acda8957c3182ed832f682181cf5f7a7f724cd9f`, whose tree equals remote `ab575729`.
`stroke-focused.log.gz` records 74 passing tests on local checkpoint
`8403771f2bbf624d73408776791a69c5bd4373cc`; the remote candidate `832b51a`
differs only in unrelated page-size test formatting. Their matching analysis
logs report no issues. These test results establish bounded parser/model
behavior, not native fidelity or repeat stability.

The retraction's 74 passing focused tests and clean analysis logs are recorded
separately on the `832b51a` base plus the retraction patch. They check that missing widths remain
absent, explicit zero/hairline/normal widths remain distinct, malformed source
widths remain unsupported, caller-built invalid widths reject conversion, and
wrap-clearance controls still pass. They do not claim a new clean native run
of the retraction commit; the wrap-only receipt preserves the output behavior
being restored, and final combined-source validation is performed separately.
