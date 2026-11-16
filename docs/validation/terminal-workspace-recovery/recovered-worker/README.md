# Original worker result and interruption

The original worker completed the isolated 36-file run on frozen source
`3cd501798794dcb74de5dca912b498a4c0a7e39b` with **462 passed, one platform skip
and zero failures**. Its command output also reported no changes across 5,664
watched source, native, dependency, fixture and adapter inputs, including modes.
The run started at 09:55:50.792776 UTC on 16 November 2026 and took 155.155 seconds.

The worker became unavailable after the result was returned and before its full
log, final source inventories and final PNGs could be copied into a remote
checkpoint. The replacement execution surface lacked the original workspace.
All implementation source, incoming integration and the earlier preserved
development evidence were already safe in eight remote checkpoints through
`0c43c476ff33638306425c1427cf1d04a170a912`.

[interrupted-worker-result.json](interrupted-worker-result.json) records the
exact facts returned by the completed command, including the reported full-log
SHA-256. It is reconstructed from the task transcript, **not the original receipt
or log bytes**. The final five PNGs from that run were neither inspected nor
archived before the interruption. A later complete rerun must have its own
durable log, inventories and inspected captures; its counts must not be added
to these historical counts.

[workflow-registration.json](workflow-registration.json) similarly transcribes
the successful local YAML registration/path check performed before the outage.
[static-targets.json](static-targets.json) records the independently reproduced
164-file analysis/format target set. The final analyzer, formatter check and full
optimized application web build had **not run** when that worker was lost.

The source remained unchanged during recovery:
[frozen-source-identity.json](frozen-source-identity.json) proves that checkpoint
`0c43c476` differs from frozen source `3cd50179` only below `docs/`.
[remote-cutoff.json](remote-cutoff.json) records the fresh remote advertisement;
all other branch and PR tips are unchanged from the already verified integration.

Toolchain restoration and later validation are documented separately in the
[parent acceptance record](../README.md). No GitHub Actions were queried,
awaited or rerun.
