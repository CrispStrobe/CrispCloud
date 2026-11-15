# Worksheet navigation acceptance recovery — 15 November 2026

Continuation branch: `codex/office-recovery-20261115`.
Recovered host head: `1a86e790080c174c27a283b7ac49913ca1fa91f0`.
Host main at recovery: `8a24763fb4b2c720ff6b617cebbea8971191bdca`.

## Verified recovery boundary

The attached conversation reports later local acceptance and an inventory
repair, but those files and receipts are absent from the remote branch.
This continuation will retain new evidence and distinguish recovered hosted
results from newly executed checks.

Canonical Quds navigation is complete at
`f31cf308013ceb4527e3f4de677785894bb1bfc0`, with the accepted implementation
at `e6da5be3a7e085dc200e35d6300161658179463c` already consumed by this app.
Canonical PR #18 was merged; its CI runs 43682115989 and 43682115974 succeeded.
The newer canonical main has separate Word golden failures; this app's pinned
navigation source and the NAV-01–04 acceptance scope are unchanged.

Host run [43681914471](https://github.com/CrispStrobe/CrispCloud/actions/runs/43681914471)
passed the Chromium recovery-copy check and all 283 host tests, including the
12 navigation workflow cases. Its inventory then rejected 57 paths because
recursive root discovery counted historical committed evidence. The external
schema/render job was consequently skipped. Those later gates have not passed
for this host source in the recovered remote record.

The run's host artifact 14149236176 has recorded ZIP SHA-256
`3fe8fbf3bca0d941fc67270a9cdb7988e927db6b4b5ddf0237e98aa459354477`.
The download will be checked against that digest before using its outputs.

## Completion gates

1. Retain the exact hosted metadata, logs, artifact bytes and digest receipt.
2. Reproduce and repair inventory layout selection. Checkout validation must
   inspect current output roots; downloaded bundles must still reject duplicate
   or unexpected host roots. Keep all 182 required files and their validation
   scopes, including 149 render/reference files and 33 schema-only files.
3. Correct the optional UI capture helper and inspect the real rename dialog
   and narrow Arabic worksheet chrome. UI captures remain separate from XLSX
   package acceptance.
4. Run the regression controls, validate the exact saved packages independently,
   and let the complete hosted workflow finish on the implementation checkpoint.
5. Save the new acceptance receipts and update the continuation records, with
   explicit source identities and remaining limits.

Every implementation and validation checkpoint will be saved to the remote
continuation branch before moving to the next phase.
