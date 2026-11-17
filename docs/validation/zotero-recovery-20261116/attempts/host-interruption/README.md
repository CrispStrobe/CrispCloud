# Interrupted host qualification — preserved evidence

This archive preserves the first recovery host attempt against CrispCloud `07083d1983db87a9868c3e8ba0cda1efd283b445`, pinning Quds `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`. It is **not a completed or accepted qualification**.

Both Office source/tracked guards passed, then all **41 actual host cases** passed. The following strict analyzer wrote only its start header. The managed execution handle `86536` later returned `Unknown process id 86536`; no final receipt or after-run inventories were written. The original run did not finish its analysis, formatting, Python, final vendor, or cleanup gates. Its 41 partial cases are excluded from the final accepted test total.

The interruption observation at `2026-11-16T20:31:08.704071+00:00` verifies that all **3,732 watched source files** and **5,837 dependency files** still matched the original before-run snapshots. The temporary analyzer configuration remained semantically identical to the archived graph. Its bytes differ from the archive because the original runner serialized archive keys in sorted order. No configuration restoration is claimed for this interrupted attempt.

A new command exposes only its own sandbox process namespace. The disappeared execution handle and stale log therefore do not establish the global absence of an orphan process, and the reason for the interruption is not asserted. The original directory and analyzer configuration were left intact. The replacement qualification uses a separate worktree and harness, and is executed and polled by the parent agent with atomic progress journals, 15-second heartbeats and fail-closed 600-second command deadlines.

[archive-inventory.json](archive-inventory.json) records the exact source and archived hashes of every copied file. Large JSON inputs are stored as lossless `.json.gz` files; decompression recovers the original bytes and hashes. Every source file was checked again after copying. The original runner and its preparation record are also included. This snapshot was archived at `2026-11-16T20:38:09.882285+00:00`; original raw logs remain separate and unchanged.

No GitHub Actions jobs, workflow/status queries, CI waits or reruns were used.
