# Binary comparison continuation — recoverable progress

## Preserved starting state

- Baseline: `15a389f57e3a8fe9837f786407ce787fe198386f` on `main`.
- Continuation branch: `integration/storage-binary-20261114`.
- The retained NTFS branch `d504409acc779b670de482247f3231a7247dcd92`
  is an ancestor of this baseline. The repository had no open pull requests
  when this continuation started.
- The source roadmap is `docs/storage-capabilities-20261114.md` at that
  baseline. Its dependency exclusions and separate read/write profiles remain
  the implementation constraints.

## This increment

Stage 6's same-offset binary scan, sparse difference index, changed-range
navigation and small Hex windows already exist in the baseline. This
continuation completes their source-capture and resource-bound contracts,
rather than introducing a second comparison interface.

The intended profile captures two read-only inputs, enforces the existing
8 GiB native / 32 MiB browser per-input snapshot ceilings, checks the capture
against a second bounded SHA-256 read, and navigates only owned captured bytes.
Available source metadata and account identity remain additional checks, not
content hashes. Two matching reads are evidence of the observed bytes, not a
claim of atomic snapshots on a provider without that facility.

Work also covers cancellable metadata waits, finite byte/chunk/time budgets,
empty-chunk yielding, failed-open cleanup, and dialog session ownership across
reload, swap, cancellation and disposal. No patch application, recovery write,
physical-device access, new runtime dependency or deployment is introduced.

## Work ownership and checkpoint policy

- Root owns the read-only captured-source implementation, integration review,
  evidence, all commits and all remote reference changes.
- Core comparison scanning/session integration and regression coverage.
- Viewer lifecycle integration and widget regressions.
- Exact toolchain/dependency preparation and validation support.

Concrete increments are saved with ordinary descendant commits to the remote
branch. Existing source, branches and historical qualification receipts are
preserved. Test claims will identify the revision and actual execution; this
initial checkpoint records the plan only and claims no new passing checks.

## Resume guidance

1. Fetch this continuation and `main`, and inspect their current heads.
2. Read this record and the eventual binary comparison profile.
3. Preserve failed/intermediate attempts separately from final receipts.
4. Continue pushing concrete increments; do not rewrite checkpoint history.
