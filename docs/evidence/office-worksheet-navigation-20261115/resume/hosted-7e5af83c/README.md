# Recovered hosted acceptance at `7e5af83c`

The exact-source push run [43685477823](https://github.com/CrispStrobe/CrispCloud/actions/runs/43685477823)
completed successfully after the interrupted continuation. All three jobs
checked out `7e5af83c4e6d26247ccf91d2b03c47a816f46231` (tree
`39389be7f70b786382a133c91d85ecc933c6f0e3`). This checkpoint preserves the
actual hosted receipts rather than reconstructing the unavailable local
SDK/render execution from the preceding conversation.

## Saved evidence

- `github/` contains authenticated workflow/job/artifact metadata, the full
  decoded job logs, their hashes, and the separate observation of other PR
  checks. Log encoding and observation limits are recorded there.
- `archives.json` records GitHub's artifact digests and the independently
  recomputed digests. `archives/` retains all four original successful-run ZIPs
  and the original host ZIP from failed-inventory run `43681914471`.
  Large ZIPs are split into consecutive 512 KiB parts solely for transport;
  concatenation reproduces the exact GitHub archive bytes.
- `reports/` exposes the SDK, inventory, renderer, browser, and UI receipts
  directly. These are byte-for-byte copies from the retained archives.

Reassemble and verify the ZIPs outside the checkout:

```sh
python3 docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/reassemble.py /tmp/quds-navigation-artifacts
```

## Accepted package and behavior results

The retained logs report 1,265 engine tests, 283 host tests (including 12
navigation cases), 32 inventory controls, and 182/182 required host files.
The SDK report contains 540 packages and zero failures. Its separate self-test
accepts eight valid packages and rejects four invalid-XML and twelve
type-mismatch controls. The renderer passes 80 controls and renders 149 files;
the saved report confirms 36 repeated-save and three reference comparisons,
with no failures. Chromium checks actual download bytes and URL cleanup.

The six navigation workbooks are explicitly schema-scoped. Their inclusion
does not extend the renderer claim to those six files. The original failed
host run remains identified separately and is not relabeled as a passing run.

## UI inspection and remaining work

Both full-view PNGs have the expected framing (1600 × 1000 English rename
dialog; 390 × 1000 Arabic worksheet). The rename error and retained draft are
visible. However, the widget-test font setup leaves Arabic labels, Material
icons, and custom-painted grid labels as placeholder glyphs. These captures
establish framing only; readable Arabic/icon visual acceptance remains open.
A preview-only font setup is the next implementation checkpoint.

Other workflows on this older branch have independent failures recorded in
`github/summary.json`. This Office result is not an all-repository CI result,
a qualification of newer main, or a physical-device claim.

## Independent verification of the retained bytes

`integrity/` records a separate local check of all five archive digests,
1,843 extracted files, all 540 SDK input hashes, and the complete 182-file host
inventory. An independent Python OPC/XML reader checks the six navigation
workbooks, including draft values, quoted formulas, defined names, and
rename/undo/redo. All 201 rendered PNG page fingerprints were recomputed;
the 36 save-cycle and three independent-reference comparisons also pass.
Browser source, lockfile, compiled code, and downloaded-payload hashes agree.
This verifies the hosted execution evidence; it is not a second SDK or renderer
execution. The browser's generated package configuration is not in the artifact,
so its digest is retained without claiming an independent recomputation.

To reproduce that check from this committed directory, use a new destination
and a checkout containing qualified source `7e5af83c` (current runtime inputs
checked by the verifier must match it):

```sh
python3 docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/reassemble.py --extract /tmp/quds-navigation-replay
python3 docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/integrity/verify_hosted_artifacts.py --artifacts /tmp/quds-navigation-replay --app . --output /tmp/quds-navigation-verification
```

Python 3.12+ and Pillow are required. The retained receipt identifies the
exact versions used. The verifier's original source and receipts are preserved
unchanged, including their explicit geometry-only limit for the older UI PNGs.
