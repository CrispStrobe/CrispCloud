# Interrupted native checkpoint fe4d668

The exact tested source tree `a16bf1c9d3ddab00009c58dfcf8eaf706f1178d4` is pushed as
`713973fb27330d190281cbe66193f6b22ec722f8` and was measured from clean local commit `fe4d6687a06567ec3cec2fcebb0b4cfdb4810a1a`.
The portable gate passed 647 Dart tests, 109 Python tests, JavaScript acceptance,
clean analysis/formatting, and a zero-warning package dry run. The independent
Open XML SDK gate accepted all 144 required outputs with exact coverage, hashes,
determinism and positive/negative controls. Full receipts are retained here.

## Native run did not complete

The native process exited 1 because the overlay filesystem ran out of bytes
while a separate full engine gate held a large temporary compilation cache.
The unchanged last atomic report contains 20 of 22 cases,
18 completed three-cycle cases, and
55 completed cycle imports. Its raw status remains
`running`; the process log and this index record the interruption explicitly.
The list-restart and Word14 cases record errors, and Word16/POI were not started.
No completed-corpus, exact-pagination or semantic-equivalence claim follows.

The report, stdout/stderr and all 228 emitted DOC/DOCX files are retained
losslessly. Every document hash occurs in the unchanged sealed report.
The deterministic archive contains only regular files with fixed metadata.
`native-files.manifest.json` lists every path, size and SHA-256. Verify or extract:

```sh
python3 doc/evidence/fe4d668-interrupted/verify-native-files.py
python3 doc/evidence/fe4d668-interrupted/verify-native-files.py --extract build/native-fe4d668-interrupted
```

Later runs must remain separate; this failed environmental run is not rewritten
as a pass. The previous [complete native checkpoint](../6b2b611/README.md) remains
unchanged. No original input or reviewed golden was edited.
