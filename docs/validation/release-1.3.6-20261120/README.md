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
