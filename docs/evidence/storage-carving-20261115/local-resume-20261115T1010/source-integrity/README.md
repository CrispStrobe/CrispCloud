# Source integrity and synchronization qualification

This directory preserves new source checks for the combined main/ODF/storage
candidate. The `qualification/` and `checks/` directories are the original
attempt on `e0221c2034cf56cac6c9566c8ff7b65ed41518a2`; their contents are retained
unchanged.

## Original attempt

The source and package-resolution snapshot remained unchanged throughout. The
following checks passed:

- All 10,429 tracked files matched their committed Git blob and mode.
- All 2,223 managed Office files matched the manifest SHA-256 and exact
  canonical Git blob/mode: 491 Quds files at
  `793c64ac4fc2e896706aa65c13eaa70bd27f7267` and 1,732 parser files at
  `d422fa99a3a84830794f0e2dc332d59f923779f7`.
- Standalone parser inventory and source/dependency declarations agreed.
- Both guarded synchronization dry runs succeeded.
- Existing Python controls passed: 8 Quds sync, 19 standalone parser sync,
  and 21 inventory tests, totaling 48.

The aggregate gate failed because its last command attempted the scripted
Office oracle before generating its required current outputs. Its
`setUpClass` raised `FileNotFoundError` for
`build/fidelity-scripted/word/edited.docx`; zero oracle tests ran. This is a
missing prerequisite, not a failed source comparison. The oracle requires the
engine package working directory in addition to genuine current output files.

The original runner `run_source_controls.py` and its logs remain here.
`run_source_only_controls.py` keeps the seven source/inventory commands and adds the 34 existing host-evidence controls and
explicitly records the separate output-dependent gate as pending. Its source
scope does not claim that the deferred oracle passed.

## Output-dependent oracle prerequisite

Run the existing engine suite `test/scripted_workflows_test.dart` from
`packages/quds_office_engine`, using the pinned Dart toolchain and locked
package graph. This produces real modified documents plus three asynchronous
export/reopen cycles for each format:

- `build/fidelity-scripted/word/edited.docx` and `roundtrip-1.docx` through
  `roundtrip-3.docx`;
- `build/fidelity-scripted/sheet/edited.xlsx` and `roundtrip-1.xlsx` through
  `roundtrip-3.xlsx`;
- `build/fidelity-scripted/slide/edited.pptx` and `roundtrip-1.pptx` through
  `roundtrip-3.pptx`.

Then, in that same package directory, run and retain source-bound receipts for:

```bash
python3 tool/fidelity/scripted_oracle.py
python3 -m unittest discover -s tool/fidelity -p test_scripted_oracle.py -v
```

The current oracle defines 17 test methods, including six heading-inheritance
controls. If all 17 execute and pass, these five Python control cohorts total
99 tests (8 + 19 + 21 + 34 + 17). The corrected source-only runner includes
the 34 host-evidence inventory/layout controls, for 82 expected tests before
the output-dependent oracle. The earlier historical total of 61 is not used as
acceptance for this source; the original current attempt observed 48 passing
controls and an oracle setup error.

The generated-output oracle, full output inventory, rendering and external
schema acceptance remain distinct from source integrity. No archived outputs
are copied into the current build or relabeled as current results.
