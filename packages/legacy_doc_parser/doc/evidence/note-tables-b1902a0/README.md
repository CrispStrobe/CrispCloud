# Note table repeat stability

These two independent native runs used clean parser commit
`b1902a0ba0ec2539c7f413769cb18347f98f7556`. Each ran the existing case for three
DOC → parser DOCX repetitions. The bounded orchestrator sealed and verified
each full report and artifact archive before reclaiming its generated raw
run directory. `index.json` records the separate invocations and source
receipts; these are not represented as one corpus invocation.

| Case | Previous maximum drift per cycle | New drift per cycle | Exact repeat vs first import | Initial binary → parser |
| --- | --- | --- | --- | --- |
| table-borders | 13.45 pt | 0 pt | 3/3 | 74.427 pt maximum word drift; wrapping differs |
| note-markers | 13.45 pt | 0 pt | 3/3 | Word sequence and layout still differ |

All six repeated imports match their first import in RGB pixels, extracted
layout text, word geometry and page dimensions on the recorded renderer.
This fixes accumulating displacement; it does not claim exact initial
fidelity. Source/binary inputs remain unchanged for both initial cases and
all six repetitions. `summary.json` retains the precise comparison fields,
old/new report hashes, archive hashes and environment checks. The earlier
22-case reports and goldens have not been altered.

The focused portable gate passed 75 tests. Both new source-native regression
outputs passed the independent Open XML SDK validator with zero errors;
`schema.json` identifies the exact output hashes. Raw rasters are retained
losslessly as `.ppm.gz` inside the sealed archives, with compressed and raw
hashes/sizes plus per-render raster manifests.

Use the unchanged verifier at
`../native-corpus-7308125/verify_native_artifacts.py` with the sealed report,
artifact archive and manifest to recheck archive content, PDF/raster hashes
and gzip sidecars. Source fixture provenance is repeated in
`source-fixtures.json`; the checked-in regression binaries are byte-for-byte
copies of the old retained native bridge artifacts.
