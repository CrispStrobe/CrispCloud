# PICMID scale quantization: source and native evidence

The measured runtime is parser
`78c88b357ad66934abf9b467e3903748b7742e3c`, tree
`0faeb7fbb750a2a2533302e9ffccfb839341a665`. Both the final seven-control run
and the single initial `emf-vectors` corpus run record a clean checkout at
that exact commit. This evidence checkpoint changes no runtime source.

## Measured result

| Check | Before | Final |
| --- | --- | --- |
| Independent native PICMID frame expectations | 7/7 match | 7/7 match |
| Parser PICMID frame expectations | 3/7 match | 7/7 match |
| Retained `emf-vectors` maximum word drift | 0.05 pt in the `48bf3a` corpus | 0.0 pt |
| Retained `emf-vectors` page/text/layout text | Match | Match |
| Retained `emf-vectors` page RGB | Different | Different |

The [source contract](../../picture-scaling.md) explains the raw PICMID
goals/scales, integer arithmetic, primary references and the separate
native-only crop adjustment. The test does not claim exact image pixels or
complete GDI operation coverage. Both retained EMF and WMF vector streams
already had complete previews; their native image payloads remain unchanged.

The final controls use LibreOfficeDev `26.8.0.0.alpha0`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. They patch only eight goal/scale
bytes in the hash-pinned native PNG source. All seven output frame extents
match independently authored integer-twip constants; parser PDF image sizes
differ from those constants by less than 0.00002 pt. The native importer's
separate 0.1 pt image-size reduction remains visible and is not treated as
source cropping. The baseline and final raw reports remain unmodified.

Local scoped checks passed: 83 picture/media/metafile Dart tests, focused
Dart analysis, and the existing JavaScript media acceptance's 51 checks.
The archived compile/run logs retain the JavaScript result. The initial corpus
run has no repeated save cycles. Full integrated acceptance belongs to the
later combined runtime, not this focused checkpoint.

## Retained files and verification

`control-artifacts.tar.xz` stores 181 records totaling 855,263 bytes before
compression. It includes the exact authored binary inputs, parser/native DOCX,
PDFs, raw models/reports and execution logs for baseline and final controls.
It also retains the first diagnostic run under `pre-scope/`: that run
incorrectly applied a binary-versus-parser image-bound equality gate even to
the integral control. The separate baseline probe then checked PICMID frame
dimensions and independently authored parser image dimensions; native crop
and image-bound differences remained measured rather than silently removed.
The first diagnostic results have not been rewritten or relabeled as passing.

`emf-corpus/` is a separately sealed 45-file, 473,882-byte initial corpus run,
with its complete native report and losslessly compressed page rasters. It
uses the existing corpus sealing format and verifier. The control manifest
and native manifest enumerate every retained file's size and SHA-256.

```sh
python3 doc/evidence/picture-scaling-20261113/verify.py
python3 doc/evidence/native-corpus-48bf3a/verify_native_artifacts.py \
  --directory doc/evidence/picture-scaling-20261113/emf-corpus
```

The control verifier checks exact archive membership and byte hashes, binds
the displayed reports to their archived copies, validates all seven final
expectations, and checks the four recorded baseline disagreements. It uses
explicit errors and remains active under optimized Python. Raw reports,
source artifacts and archive bytes are evidence; successful verification
does not extend the documented rendering scope.
