# Complete native corpus at c5ff75e7

All **24 initial cases and 72 repeat imports completed without execution or
import errors** on clean parser runtime
`c5ff75e76163d9abbdd44a9f2a7c5ad210929289`, tree
`25bd05c12fa2272a32ec2aaba2cc0117be5bed96`. Nine initial cases render exactly
on the recorded native renderer. Word14 retains an appearance difference in
all three repeat comparisons against regenerated binary DOC. The original
pages and measured losses are preserved; completion does not establish
universal fidelity or Microsoft Word behavior.

## Results compared with 74420eb2

The baseline is the complete [74420eb2 corpus](../native-corpus-74420eb2/README.md).
All 24 source inputs and initial binary DOC files have identical bytes between
runs. The corpus manifest, native renderer, installed font inventory and font
files, Dart compiler and three Poppler tool identities also match.

| Measurement | 74420eb2 | c5ff75e7 |
| --- | ---: | ---: |
| Initial page counts match | 24 / 24 | 24 / 24 |
| Initial page dimensions match | 22 / 24 | 22 / 24 |
| Initial per-page word sequences match | 21 / 24 | 21 / 24 |
| Initial word geometry within 0.25 pt | 14 / 24 | 14 / 24 |
| Initial extracted layout text matches | 19 / 24 | 19 / 24 |
| Initial exact RGB, text and word geometry | 9 / 24 | 9 / 24 |
| Repeat exact versus regenerated binary DOC | **39 / 72** | **36 / 72** |
| Repeat exact versus preceding parser import | 58 / 72 | 58 / 72 |
| Repeat exact versus first parser import | 48 / 72 | 48 / 72 |

**Only Word14 has changed render fingerprints.** The other 23 cases retain
every recorded fingerprint. Word14's initial maximum word displacement remains
0.75 pt. Initial page, text and geometry flags are unchanged, as are the repeat
page, text and geometry flags. All 72 repeat page counts and dimensions match.
Repeat geometry is within 0.25 pt in 51/72 comparisons to regenerated binary
DOC, 67/72 to the previous import, and 63/72 to the first import.

The 14 original DOCX-to-binary bridge comparisons remain separate: their page
counts and dimensions match, with 3/14 exact renders. Source golden outcomes
are unchanged. Strict structural differences include representation and bridge
changes; their counts alone cannot attribute semantic loss.

## Word14 pixel measurements

`word14-pixels.json` retains a deterministic comparison of **16 pairs** of
lossless 72-DPI RGB pages from both corpus archives. The source binary pixels
are identical. Each compressed page, decompressed PPM and render receipt is
hash-checked before measuring. The helper uses only Python's standard library.

Initially, changed pixels decrease from **35,146 to 30,704**. The total absolute
RGB channel difference decreases from **10,774,592 to 6,725,615**. This aggregate
improvement does not imply that every fill or pixel improves:

| Named object / shape ID | Initial changed pixels before → after | Absolute RGB channel difference before → after |
| --- | ---: | ---: |
| Solid / 1031 | 409 → 409 | 72,293 → 72,293 |
| One-color gradient / 1029 | 6,500 → 6,499 | 1,529,313 → 1,646,517 |
| Two-color gradient / 1027 | 6,524 → 6,524 | 1,804,478 → 1,716,061 |
| Pattern / 1030 | 5,444 → 3,320 | 2,407,579 → 1,167,703 |
| Picture / 1028 | 11,778 → 7,440 | 3,335,066 → 629,425 |
| Texture / 1026 | 4,491 → 6,512 | 1,625,863 → 1,493,616 |

All three former exact Word14 comparisons against their regenerated binary
DOCs now have pixel differences. These differences are confined to the pattern
and texture regions; the solid fill, both gradients and picture region remain
pixel-identical in each binary-to-parser comparison.

| Cycle | Pattern changed pixels / largest channel difference | Texture changed pixels / largest channel difference | Total changed pixels |
| --- | ---: | ---: | ---: |
| 1 | 18 / 56 | 6,092 / 207 | 6,110 |
| 2 | 10 / 55 | 6,092 / 207 | 6,102 |
| 3 | 3,831 / 255 | 5,908 / 207 | 9,739 |

The texture differences have half-open pixel bounds `[73,259,258,292]` in
cycles 1–2 and `[73,259,258,291]` in cycle 3. The pattern bounds are
`[347,139,534,172]` in cycles 1–2 and `[347,139,534,173]` in cycle 3. The six
analysis regions partition the separating whitespace around the named objects;
they are not asserted binary shape bounds. Counts and channel differences
come from exact byte subtraction, without a tolerance or visual similarity
score. Appearance/source attribution is separate from this measurement; the
pixel counts alone do not prove which importer, emitter or save bridge causes
a mismatch.

`word14-source-triage.tar.xz` preserves the independent read-only source review
as five unchanged files, including its inspection script, 14-package report,
manifest, primary specification/source excerpts and qualified conclusions.
The archive is 16,324 bytes, SHA-256
`f9c350ecfa28c514f60b115b2bfa737ebcdc0808f010787abbf1d934765a017a`.
The native verifier binds all 14 inspected DOCX packages, their original binary
source, embedded images, retained OfficeArt content and BLIP payloads to the
original sealed archives. It also binds the source review's external pixel
references to this exact pixel helper and result.

The source review found identical textbox geometry/style between versions,
exact source image selection and payload bytes, and no discarded explicit
tile-origin, size or alternate-fill-rectangle operand in the affected repeat
textures. The first native DOC bridge replaces the original monochrome DIB
pattern with a colored PNG/type-2 texture, so no repeated output contains the
initial BMP wrapper. The pinned native binary importer and VML importer use
separate tiled-brush and bitmap-fill paths. These findings support a remaining
tiled-fill interoperability discrepancy; they do not attribute every pixel to
one native function or justify a guessed parser offset, recoloring, or removal
of the retained fills to recover the older exactness count.

The runtime retains supported gradient, monochrome-pattern, texture and
picture fills. The separate source controls in
[textbox fill evidence](../textbox-fill-controls-20261113/README.md) and the final
continuation handoff qualify supported operands and consumer behavior. The
retained alternate DrawingML `metroBlob` is outside the implemented fill
subset. These native results make no claim of complete alternate DrawingML
rendering or universal tiled-fill parity.

Specifically, the original texture metroBlob describes top-left tile alignment,
whereas the later native DOCX bridge describes center alignment. The original
preset-pattern metroBlob is likewise distinct from the bridge's colored PNG
texture. Those original blobs remain retained but unsupported; later bridge
output is not a full oracle for their Word-authored semantics.

## Environment and retained bytes

This run used LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, Dart 3.13.7, `pdftoppm` and
`pdfinfo` 26.05.0, and `pdftotext` 25.03.0. Microsoft Word was not executed.
All source and cycle inputs remained unchanged. All **150 native build/harness
inputs** are retained in `native-source.tar.xz` and bound to the same inputs in
the [portable/schema acceptance](../continuation-c5ff75e7/README.md). The full
launch record independently binds all 1,260 input hashes before and after the
run, exact arguments, launcher/driver identities, environment and console.

The single completed run retains **2,577 artifact files**, including
**312 DOC/DOCX files, 230 PDFs and 240 compressed RGB pages**. Its artifact
archive is **2,737,996 bytes**, SHA-256
`a7f916b919a5cce562ece30425472f5f7e8efa25d6a31076228dcb5961b1b626`.
Member bytes total 190,467,340. The compressed pages losslessly represent
343,330,104 raw PPM bytes. The original 155,925,883-byte report compresses to
262,380 bytes, SHA-256
`5eb526678cd573004713fa285e2d66d736ce36499c882d9d927455ecba96f8eb`.
Original report and artifact bytes are unchanged. Temporary native profiles
and the reproducible executable are omitted; its exact hash and compile
command remain in the measured report.

The native source archive is 279,468 bytes, SHA-256
`0056b25960e06b862cba324e478993a7364b05b50ae14d6f30ab09f175008d4c`.
Its member hashes aggregate to
`dc1374371123b037fd9717980048c00a832d5a55f4e2b2d61aed8e55ec760d28`.

## Verification

From the repository root:

```sh
python3 doc/evidence/native-corpus-c5ff75e7/review_native_evidence.py --repository . --self-test
```

The review verifies exact bundle inventories, original artifact/raster seals,
captured native source bytes, portable/native source and Dart identity, the
full launch receipt and every case/cycle document chain. It independently
recomputes **278 render comparisons**, reproduces the complete comparison
against the 74420eb2 seals, and binds every summary row to that derivation.
It also recomputes all **16 Word14 pixel comparisons** directly from the sealed
RGB artifacts, including each object region and reported difference bound.
Sixteen targeted corruptions reject source, command, status, sidecar, chain,
metric, launch, pixel-summary and source-package/image contradictions.

The separate hosted CI observation is checked through its exact run/job API
receipts, returned decoded logs, required steps and result markers, with seven
additional corruption controls. Hosted Dart 3.14.0 and local Dart 3.13.7 remain
explicitly separate; hosted logs do not stand in for these native artifacts.

The inherited comparison helper uses assertions, so both review and comparison
entry points explicitly refuse `-O`, `-OO` and `PYTHONOPTIMIZE`. The artifact,
pixel and hosted verifiers use explicit exceptions. Helpers do not rerun Office
or update a golden. `comparison-vs-74420eb2.json.xz` retains the full lossless
comparison; `summary.json` contains its measured aggregates and case rows.
Original workspace paths remain in captured records. Verification normalizes
only current review-input locations; original tool paths, source identities,
hashes and counts remain bound. `bundle-files.json` inventories every file in
this folder except itself and Python bytecode caches.
