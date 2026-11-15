# Parser reconciliation and qualification

## Incoming source checkpoint

The initial union is saved at `9864ac623a95b82c305ea2923f4ac783bbd200fe`. It combines main `d422fa99`, real-format classification `9f61e030`, Word 98 Mac `3dc1a857`, comments/bookmarks recovery `89555522`, and Word 6/95 text import `120a3cc9` (which includes damaged-compound recovery `a82595a8`). All original branch ancestry is retained.

## Reproducing regression baseline

The 16-case regression-only checkpoint `c1559d9d2efa8651c0f9a7759473720e3155f9b5` leaves production identical to the union. Its recorded run has **3 passing and 13 failing cases**, no skips; all 13 error events correspond to the expected assertion failures. Source, commit identity, package-resolution inputs and recorder/tool hashes stayed unchanged. This is failing development evidence, not acceptance.

The failures reproduce: omitted Word98 recovery recognition; recovery bypass of the 64 MiB input bound; ignored contradictory `cbMac` extents; unbounded candidate/decoding work; incorrect Word6 Unicode decoding and acceptance of isolated surrogates; guessed Windows1252 decoding for unsupported charset/locale declarations; and removal of a valid endnote bookmark at the omitted comment story's end boundary. Valid small piece-table recovery and encrypted/obfuscated refusal provide passing controls.

`baseline/` retains raw machine events, stderr, exact command, strict counts, hashes and before/after snapshots. `dependency-setup/` retains exact standalone package-lock/config/graph bytes; its declaration was unchanged and the development lock was newly created. The recorder is the host source-bound recorder with only its machine-helper location changed to a sibling file.

Word6 encoding review cross-checks the independent LibreOffice reader: [ww8scan.cxx](https://docs.libreoffice.org/sw/html/ww8scan_8cxx_source.html) handles the old `fExtChar` Unicode flag and declared FIB charset/locale; [filter utility encoding lookup](https://docs.libreoffice.org/filter/html/util_8cxx_source.html) distinguishes locale-dependent code pages. Unsupported encodings must be refused explicitly rather than guessed.

All 143 ordinary `test/**/*_test.dart` suites are candidates for the final parser unit gate. These files contain no explicit skips, private absolute corpus paths, environment-variable dependence, or external process calls. External/private corpus tools are outside this inventory.

No GitHub Actions run was awaited or restarted.

## Evidence path relocation

The two compressed package graph/configuration snapshots originally saved
under `dependency-setup/after/.dart_tool/` at `00fe6b31` are now ordinary
`after/dart_tool-*.json.gz` evidence files. This keeps the exact standalone
mirror compatible with its generated-directory exclusion without weakening
that guard. `evidence-path-mapping.json` records original/current paths and
identical hashes. Raw snapshots and `receipt.json` are unchanged; the original
output artifact index is retained as `original-output-artifacts.json`, and the
current enclosing indexes use the relocated paths.
