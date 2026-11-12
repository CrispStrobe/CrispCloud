# Resumed host acceptance — 12 November 2026

This is a separate completed validation of immutable host implementation
`b7edb919def85ef78d6d34ba6eb7c74d61e0bd4d` and its 366 managed files from Quds
`7641d9cfa167987216134ebfc4772918cc945d97`. The preceding session independently
published `18565195` while this run was executing. Its final-host evidence and
runtime records are preserved unchanged.

## Results and exact receipts

- [Producer acceptance](producer-acceptance.json): 921 engine tests, 143 host
  tests, zero skips; 7 sync, 344 engine, 10 host inventory and 9 coverage controls.
- [Engine inventory](engine-inventory.json) and [host inventory](host-inventory.json):
  exactly 296 +62 captures, all hashes verified. Host captures include uploads
  and dialog/controller exports.
- [Host coverage](host-coverage.json): 2,216/3,549 instrumented lines; all ten
  scoped files instrumented. This is line execution, not branch coverage.
- [External summary](external/external-summary.json): 358/358 SDK files pass;
  14 native files render to 26 pages, with zero failures.
- [Native report](external/host-native/render-report.json): eleven actual upload
  captures and three paragraph-dialog exports. The latter pass exact three-save
  page/text/RGB comparison and independent tab XML/paragraph-geometry checks.

The full source snapshots, implementation pins and unchanged-tree checks are
recorded in producer-acceptance.json. Native and schema checks require every
recorded input path/hash and recheck original and frozen bytes afterward.
Runtime provenance identifies the rebuilt Open XML SDK3.3.0 validator and
official LibreOffice24.2.7.2 embedding runtime; this is not Microsoft Office
renderer certification. Unknown fonts and unsupported table/tab/style behavior
retain the source report's explicit boundaries.

## Reproduction and retained artifacts

The exact host runner is in runtime/run_host_acceptance.py. Use the repository's
pinned Flutter3.47.8 runtime, CI=true and a fresh output directory outside the
checkout. The ordinary command is:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

External collection/native helpers and build/provenance records are retained in
runtime/. They record the runtime used; reproducing elsewhere requires restoring
the documented binaries and selecting the corresponding local paths.

The raw host log and LCOV are stored losslessly as gzip files.
compressed-artifacts.json records both original and compressed hashes. The
external/committed-receipts.json inventory describes the saved external receipts;
external/artifact-hashes.json also describes reproducible PDF/PNG/text runtime
outputs, which are not all included in this documentation checkpoint.

No source implementation, tests, goldens or acceptance policy changed in this
resumed run. It preserves independently obtained evidence, with prior final
receipts kept as their own historical record.
