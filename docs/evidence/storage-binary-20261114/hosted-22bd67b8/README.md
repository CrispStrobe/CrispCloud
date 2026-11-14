# Hosted comparison qualification at 22bd67b8

GitHub Actions [run 43623536386](https://github.com/CrispStrobe/CrispCloud/actions/runs/43623536386),
[job 132534268438](https://github.com/CrispStrobe/CrispCloud/actions/runs/43623536386/job/132534268438),
checked out **22bd67b887c81a11ea22664defc3474a07eef50a**. Its native storage
cohort passed **1,373 tests** and its actual Chrome comparison cohort passed
**31 tests**, both with zero failures/skips and successful JSON completion.
These cohorts overlap earlier native comparison results and are not additive.

The browser result closes the previously recorded local browser-qualification
gap for this exact source. The earlier workspace startup denial remains an
accurate record of that local attempt. No result is inherited by a later source
revision without comparison or execution.

The **overall workflow failed** in the later external FAT reference-image step.
The official archive server did not accept an HTTPS or HTTP connection within
the configured 15-second connect timeout, and there was no cached archive.
The native tests, Chrome tests, portable VM/JavaScript checks and unchanged-
manifest verification had already succeeded. The failed gate is preserved; it
was not skipped or reclassified to manufacture a passing workflow.

The downloaded artifact (ID **14126413276**) matched GitHub's published archive
SHA-256:

`4a39622892b512d768cd425e4021c76b60fa3ea3f95706198b9e97e21d7c7fcd`

[summary.json](summary.json) records source, counts and failure classification.
[files.json](files.json) maps complete original log/event bytes to deterministic
gzip files with both original and stored hashes. [REVISION.txt](REVISION.txt)
and [manifest-before.txt](manifest-before.txt) are copied unchanged from the
artifact. Synthetic suite-loading events are excluded from the test counts.

This evidence is specific to the captured comparison/storage source above and
does not qualify the subsequent shared-bandwidth implementation.
