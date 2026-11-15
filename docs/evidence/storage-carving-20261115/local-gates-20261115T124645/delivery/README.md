# Qualified delivery to PR #111

The qualified result was returned to `integration/storage-carving-20261115` by a lease-protected fast-forward from `3e9560c9` to **`10891b06a6da9f2502960cdbfe34b30eed271665`**. The previous head, observed main and original handoff remain ancestors. The qualified backup branch `integration/storage-carving-local-20261115124645` remains saved at the same acceptance checkpoint. Application source is unchanged from **`4c2b6ddd`**.

PR #111 was updated and read back with the exact replacement body, correct head/base, open state and draft status. `pr111-before.json` preserves the earlier body and metadata. `pr111-body.md` contains the exact new body; its SHA-256 is `92e84964e18b06f19af4b94c3046f90127234f491113f7eeefbfa03d43485f84`.

`integration-return.json` and `github-readback.json` record the completed branch/PR actions at the acceptance checkpoint. This evidence-only delivery checkpoint saves their receipts. The final remote head is verified after publication; its own commit hash cannot be embedded in its contents.

All 13 accepted local gates and the independent final audit passed; [the acceptance summary](../README.md) and [machine-readable index](../final-acceptance.json) retain exact scope and exclusions. No GitHub Actions status was polled, awaited or restarted. Main was not merged and nothing was deployed.

The final summary received a separate count, scope and relative-link review, recorded in `summary-review.json`. Raw failed and predecessor receipts remain preserved and excluded from current acceptance.
