# Complete native corpus at 74420eb2

All **24 initial cases and 72 repeat imports completed without execution or
import errors** on clean parser runtime
`74420eb2e0ec14401a0db5bcbb30ab6d202a2340`, tree
`ac78b144d90bca0f44993d94ae0fd1c8115ce072`. Nine initial cases render exactly on
the recorded native renderer, up from eight in the previous complete corpus.
Completion retains the remaining differences; it does not establish universal
fidelity or Microsoft Word behavior.

## Results compared with 48bf3a

The baseline is the complete [48bf3a corpus](../native-corpus-48bf3a/README.md).
All 24 source inputs and initial binary DOC files have identical bytes between
runs. The corpus manifest, native renderer, installed font inventory and font
files, Dart compiler and three Poppler tool identities also match.

| Measurement | 48bf3a | 74420eb2 |
| --- | ---: | ---: |
| Initial page counts match | 24 / 24 | 24 / 24 |
| Initial page dimensions match | 22 / 24 | 22 / 24 |
| Initial per-page word sequences match | 21 / 24 | 21 / 24 |
| Initial word geometry within 0.25 pt | 14 / 24 | 14 / 24 |
| Initial extracted layout text matches | 19 / 24 | 19 / 24 |
| Initial exact RGB, text and word geometry | 8 / 24 | **9 / 24** |
| Repeat exact versus regenerated binary DOC | 39 / 72 | 39 / 72 |
| Repeat exact versus preceding parser import | 58 / 72 | 58 / 72 |
| Repeat exact versus first parser import | 48 / 72 | 48 / 72 |

Only two cases have changed render fingerprints:

- **Linked-textboxes-compact:** the initial raster now matches the native
  binary render exactly; words, page size and geometry were already exact.
  Its regenerated binary and parser renders change through all three cycles,
  while the existing repeat pass/fail metrics remain unchanged. The separate
  [textbox paint controls](../textbox-next-20261113/README.md) retain source
  paint attribution and the supported paint boundaries.
- **EMF-vectors:** maximum word displacement falls from approximately
  0.05 pt to zero initially and in each comparison to a regenerated binary
  DOC. Raster differences remain. The [PICMID controls](../picture-scaling-20261113/README.md)
  retain the independent sizing and image-payload evidence; this result does
  not claim that every metafile operation has a supported preview.

The other **22 cases retain every recorded render fingerprint**. There are no
new initial or repeated-save metric losses. Word14's 0.75 pt initial movement,
Word16's cycle-one width-balancing bridge difference, notes, tables, formatting
and source-defined page defaults retain the baseline observations. All 72
repeat page counts and dimensions match. Repeat geometry is within 0.25 pt in
51/72 comparisons to regenerated binary DOC, 67/72 to the previous import, and
63/72 to the first import. Strict structural differences include representation
and native bridge changes and are not a semantic-loss verdict.

The 14 original DOCX-to-binary bridge comparisons still have matching page
counts and dimensions, with 3/14 exact renders. These are kept separate from
the initial binary-DOC-to-parser-DOCX measurements above. The accepted source
goldens and their recorded outcomes remain unchanged.

## Environment and retained bytes

This run used LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, Dart 3.13.7, `pdftoppm` and
`pdfinfo` 26.05.0, and `pdftotext` 25.03.0. The rasters are 72-DPI RGB.
Microsoft Word was not executed. All source and cycle inputs remained
unchanged. All **143 native build/harness inputs** are retained in
`native-source.tar.xz` and bound to the same inputs in the
[portable/schema acceptance](../continuation-74420eb2/README.md).

The single completed run retains **2,577 artifact files**, including
**312 DOC/DOCX files, 230 PDFs and 240 compressed RGB pages**. Its artifact
archive is **2,508,524 bytes**, SHA-256
`1ef1924ca705c287386aaecb33767ca46986e94ffa8f9db096004611c83e228e`.
Member bytes total 189,966,989, and the compressed pages losslessly represent
343,330,104 raw PPM bytes. The original 155,849,116-byte report compresses to
261,896 bytes, SHA-256
`cce2448cdbc53c6e1fdacafc1788ca35f740d627e2b64b361f601def45c1d8bd`.
Original report and artifact bytes are unchanged.

The previous corpus used 24 separate invocations. This single invocation
stores shared compile/font files once, so its total member count is lower;
the document, PDF and raster counts are identical. Temporary native profiles
and the reproducible executable are omitted. The executable hash and exact
compile command remain in the measured report.

## Verification

From the repository root:

```sh
python3 doc/evidence/native-corpus-74420eb2/review_native_evidence.py --repository . --self-test
```

The review verifies exact bundle inventories, original artifact/raster seals,
all captured native source bytes, portable/native source and Dart identity,
and the complete case and cycle document chains. It independently recomputes
**278 render comparisons** from the retained render sidecars, reproduces the
complete comparison against the 48bf3a seals, and binds every summary row to
that derivation. Nine targeted semantic corruption controls reject source,
command, status, sidecar, document-chain and metric contradictions. The
original verifier result and the final review result are retained as JSON.

The inherited comparison helper uses assertions; both review and comparison
entry points explicitly refuse `-O`, `-OO` and `PYTHONOPTIMIZE`. The artifact
verifier itself uses explicit exceptions. The copied sealer has the same
normal-Python requirement. Helpers do not rerun Office or update any golden.

`comparison-vs-48bf3a.json.xz` retains the full lossless comparison and
`summary.json` retains its compact measured results. Original workspace paths
remain in the captured records. Verification tolerates only the review
helper's current input-location spelling; recorded tool paths and artifact
identities remain bound. `bundle-files.json` inventories all files in this
folder except itself and Python bytecode caches, including helper sources.
