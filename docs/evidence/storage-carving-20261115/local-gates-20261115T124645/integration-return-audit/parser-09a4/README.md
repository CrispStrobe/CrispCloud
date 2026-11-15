# Audited full parser qualification at 08296ed

The app's unchanged canonical parser pin is `08296edbee08da013a8ff718798972552ccd03f7`. Its existing qualification commit `09a4a531a4aa210a638a220de45c9d53d44c84e1` was explicitly referenced by observed app `3e9560c9b4bd617b5346bacd8b5039493f0f2dc1`. This read-only audit materialized that exact evidence; it did not run tests, change parser source or move the canonical checkout.

## Verified result

The complete raw machine stream contains **144 requested suites and 4,132 passing visible tests**, zero failures, errors or skips, with unique paired test IDs and one successful final event. Its 144 hidden loader tests are excluded from the count. Every per-suite total matches the retained summary. Strict analysis of 18 files reports no issues with fatal infos and warnings enabled.

Both gates ran on exact source `08296ed`, with stable before/after source, commit, resolved inputs and tool hashes. This audit independently checked all 32 archive members and 23 inner-index entries, the full suite inventory, all 937 tracked non-evidence files against Git, and both 949-entry input snapshots. The recorder intentionally excludes 895 historical evidence paths; its selector is retained in the audit report.

The restored standalone lock matches the current lock byte-for-byte. Package graph nodes match after normalization; serialized config/graph bytes differ between workspaces. The recorded Dart executable, VM, AOT runtime, Dart CLI snapshot and analyzer snapshot all match the installed pinned SDK bytes. This is standalone Dart unit and analysis qualification; host application dependency-graph acceptance remains separately recorded.

## Remote artifact linkage

`canonical-parser-full-qualification.json` provides the source pin, qualification commit, exact artifact URL/path, size and SHA-256, and verified counts. The raw archive is retained remotely at:

`CrispStrobe/legacy-doc-parser@09a4a531a4aa210a638a220de45c9d53d44c84e1:doc/evidence/incoming-reconcile-20261115/artifacts.tar.xz`

Archive size: **206,644 bytes**. SHA-256: **353e4386a5e0a9fec060e2f75ff113a08a392febd565c32c2edcec074981c95d**.

`independent-verification.json` is the detailed read-only audit; `audit_existing_receipt.py` is its reproducible checker. Original summary, manifest and archive bytes are included in this scratch bundle for review.

## Separate records and counting

Our earlier 18-test changed-suite and one-file strict records at `84264525417b924476af3a9c8cfa9bbe19b6437b` remain untouched. The earlier 4,131-test full run at `57442c79239fb4d483e274e0ebb04f34686beb6c` also remains untouched. Neither is added to the audited **4,132 / 144** full-run total. No GitHub Actions run was awaited or polled.
