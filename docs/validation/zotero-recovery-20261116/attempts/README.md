# Excluded setup, interrupted and failed attempts

These records preserve earlier execution and runner-mechanics evidence. **None of their counters contributes to the final fresh total of 1,173 tests.**

- `sparse-setup/`: two missing sparse-checkout manifests; zero tests ran.
- `interruption/`: completed 390 engine tests and incomplete editor progress at +121 before loss of the managed execution handle. The cause is unknown. Flutter added two package-config metadata fields, so its original harness byte-invariance gate remains false. The earlier remote engine-only checkpoint is preserved here and in Git history.
- `host-interruption/`: 41 completed host tests, passed vendor guards and an incomplete analyzer run; no completed qualification receipt.
- `missing-example-fixtures/`: a complete failed canonical retry with 920 passes in preceding cohorts, followed by a failed rendering cohort at partial +162 because three source example imports were absent from the wrapper. No production assertion failed. The whole attempt remains failed and excluded. Its exact three committed examples were linked and fingerprinted before a new complete run.
- `runner-mechanics/`: synthetic subprocess controls for timeouts, heartbeats, exit codes and terminal markers. These are runner checks, not application tests.

Successful final runs are separate under `../canonical/` and `../host/`. The final canonical run reused only its own caches from the isolated run that returned a clean failure; it did not reuse caches from the old unobservable processes. Source, locked graph, external inputs and font fixtures were unchanged during each accepted run.

Original attempt filenames and bytes are retained. Existing `.gz` archives restore losslessly with `gzip -dk`; original archive inventories remain unchanged.
