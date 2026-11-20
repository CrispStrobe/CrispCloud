# Release gate repairs — 20 November 2026

Target: CrispCloud **1.3.6+46**. CrispOffice source: **52c7f27fc7b6998e209e3ac8c815d6cf1ca6f867**, with 3,036 guarded source files including the exact upstream Word spacing BAS test input. The independent legacy parser remains at 4895712158127b2fc930d796e17035c3ca0dac62. AOT/RML is not added.

## Findings and corrections

The original v1.3.5 release run 44735226548 stopped at analysis: spaCy's test dependencies were unresolved and the Studio-only Zotero launcher imported example tests outside the host mirror. Both analyzer inputs are now handled in their package context.

Run 44793748736 passed analysis and completed 14,649 tests successfully, with 58 failures and 112 skips. Its failures exposed missing Office translations, a premature modal-route lookup when KeePass attachment bytes load synchronously, stale UI captions and font-family expectations, incomplete WebDAV fakes, and widget tests that did not correctly drive real font I/O. The focused checks retain rendering, integrity, read-only, credential, and export assertions.

The authenticated GitHub by-tag endpoint returned 404 for the existing v1.3.5 draft while the releases list returned it. The publisher now searches all authenticated list pages after a tag-lookup 404, retains matching drafts and assets, and fails on listing errors or duplicate matches.

## Local verification before publication

- 315 host tests passed across the 18 affected test files, including metafile raster pixels, native streaming archives, localized Office surfaces, exports, WebDAV, and KeePass attachment loading.
- 119 latest Word VBA spacing and integration checks passed, including the actual committed BAS file and CLI execution.
- Application analysis exited successfully with zero errors; existing warnings and informational diagnostics remain nonfatal under the established policy.
- 15 release-publication tests and four macOS startup safeguard tests passed.
- Guarded Office inventory, crypto release evidence, export source policy, and whitespace checks passed.
- The earlier JavaScript Web release build passed in 667 seconds and passed the distribution-component guard. This is supporting evidence for the Web CI optimization, not a build receipt for the final 1.3.6 source.

The full Linux gate, all-platform binaries, notarization, and new TestFlight processing are tracked separately. This checkpoint does not claim those later jobs have completed. The v1.3.5 tag is preserved; it is not moved to the repaired application source.

## Compiled identity audit after the parallel delivery

Apple processing status alone did not establish iOS source qualification. The IPA recorded in `testflight-46.json` contains bundle metadata `1.3.6 (46)`, but its compiled Dart runtime embeds `1.3.5+45` and `bb0d8ef6`. The original package checksum was verified before this finding was recorded. The macOS package independently embeds the correct `1.3.6+46` runtime at `498b7357`; its bundle and compiled identities agree.

The delivery receipt now distinguishes the originally declared release checkout from the identities actually found in the compiled frameworks. The iOS source qualification is explicitly false; `VALID` remains Apple's processing state, not evidence that the new runtime was compiled.

Apple artifact preflight now reads the compiled App framework inside the submitted IPA/ZIP/PKG, bounds its size, and requires the full version/build and source identity to match the frozen checkout. Both Store workflows now embed `marketing+build` in APP_VERSION. The check rejects the actual stale IPA and accepts the newly compiled tagged Mac runtime. This is a consistency guard, not a cryptographic source attestation.

The guard's 43 tests pass, including mislabeled plists, stale compiled source, absent frameworks, bounded reads, and identity tokens split across stream reads. New Office main `c954d00d` was reconciled by the parallel intake; 356 independent engine paragraph-control/layout checks passed after the exact upstream BAS input was added to the guarded mirror. Controller and host qualification for that newer source is recorded separately from the earlier 315-test run.

## Follow-up qualification of Office c954d00d

The follow-up uses CrispCloud checkout `193d2c26` (version `1.3.7+47`) with CrispOffice `c954d00d2fc85604ae394674bca91ea8a1dede0e`, 3,044 guarded files, and the unchanged independent legacy parser. It qualifies source changes; it does not qualify another session's uploaded binary.

- Host: all 315 tests passed across the same 18 affected host files against the newer Office source.
- Engine: 356 tests passed across Word paragraph controls, VBA integration, paragraph style identity, and incremental layout differential checks.
- Editor: 184 tests passed; eight image-only checks were skipped. Coverage includes cross-paragraph marker deletion, incremental layout equivalence, bookmark history, Zotero navigation, and embedded editor behavior.
- Analysis: zero errors, 251 warnings, and 1,333 informational diagnostics. The default local command returns nonzero for these diagnostics; the release workflow's existing `--no-fatal-warnings --no-fatal-infos` policy treats them as nonfatal.
- Apple artifact preflight: 43 tests passed. Guarded Office inventory and crypto release input checks passed.

The earlier frozen 1.3.6 source also built successfully on macOS (universal arm64/x86_64) and Ubuntu x64. Both actual applications passed a 20-second startup smoke check; the Linux application ran under Xvfb on the Ubuntu VPS in a screen session. The VPS also passed the 315 host and 119 engine checks. These build results do not claim a binary built from the later c954d00d source.

At the final CI observation, [all-platform run 44802843089](https://github.com/CrispStrobe/CrispCloud/actions/runs/44802843089) remained queued and had produced no release binaries. The release remains a draft. Store/TestFlight uploads are explicitly left to the parallel release session at the user's request.
