# Combined archive integration evidence

This directory retains exact-source results for the continuation described in
[the reconciliation guide](../../recovery/archive-integration-20261113.md).
The original 12 branch heads and 89 PR heads are recorded separately from
later implementation and evidence checkpoints.

## Initial combined gate

`baseline-receipt.json` records candidate
`5d0814fdf8dfa2257e3000d1d3e3792864a4901e` and tree
`a607513135a1aa5515dee19caa773a73fe41b556`. All dependency, source, help, strict
analysis, portable JavaScript and independent ISO/DMG gates passed. The 165-file
Flutter run finished with **3,107 passing tests, one failing test and 13 explicit
large-archive opt-in skips**. This initial run is retained as a failure rather
than being relabeled after a later correction.

The failure was `changed sources require explicit exclusion and fit narrow
windows` in `transfer_history_dialog_test.dart`. A fixed scroll distance moved
the checkbox under the dialog title, so its tap missed and the completion action
never appeared. The same failure reproduced in isolation, without a layout
overflow. Follow-up verification must retain the narrow viewport, an actual
checkbox tap, the explicit-exclusion requirement and both source/destination
content assertions.

`baseline-test-files.txt` and `baseline-analysis-inputs.txt` preserve the complete
selected file sets. `baseline-logs.tar.gz` contains the original command logs and
machine-readable test events; `baseline-logs.json` records all hashes. Generated
JavaScript and reproducible fixture binaries are omitted from the log archive.

The local native profile used verified Clang, SQLite and pinned libsmb2, plus
real installed 7-Zip 23.01/RAR 7.23. Independent disk-image checks used 7-Zip
26.06. The optional native ebook hook was disabled only during the local Flutter
test command; both manifests were restored byte-for-byte and the tested worktree
was clean afterward. The receipt includes the precise tools, commands, source
pins, skip identities and all results.

## Source attribution

Subsequent implementation checkpoint `e2d48cae` fixes encrypted split-7z member
reads after password acceptance. Candidate `67cd81fe` also pins canonical ebook
reconciliation `a18b93c1`; its runtime, package, test and CI bytes equal the
baseline's ebook pin `ac9925c4`, with only two upstream documentation files
different. The shared dependency was merged through
[Crisperbooks PR #1](https://github.com/CrispStrobe/crisperbooks/pull/1) at
`505d3d7bfb922e5f0d77b7230cd38b0e266d0606`, whose tree equals `a18b93c1`.

The exact parser qualification remains in the separate
[parser receipt](../parser-lineage-integration-20261113/README.md). Historical
and focused test counts overlap and must not be summed as a single run.
