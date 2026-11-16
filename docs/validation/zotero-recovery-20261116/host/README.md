# Completed focused host qualification

The complete fresh run passed at CrispCloud `07083d1983db87a9868c3e8ba0cda1efd283b445`, pinned to Quds `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`. It ran **41 host Flutter tests and 28 Python sync/verifier tests**, with all ten required commands passing. Strict analysis and formatting covered eight host and sixteen vendored targets. Source and tracked-index guards verified 2,509 managed files.

The 3,732 selected host source inputs and 5,837 dependency/runtime inputs were unchanged; tracked inputs matched the published source; the temporary analyzer configuration was restored. See [receipt.json](receipt.json) for exact commands, source trees, hashes, timings, targets and limits. This fresh run excludes every result from the earlier interrupted attempt.

[run-expanded-host.py](run-expanded-host.py) is the exact executed runner (its SHA-256 appears in the receipt). The accompanying artifact inventory maps losslessly compressed files to original names and SHA-256 values. Use `gzip -dk` on each `.gz` archive to restore original filenames before independently checking the receipt hashes.

The canonical run is recorded separately; no combined success is inferred from this host receipt. This is focused local qualification using the genuine locked graph, not a fresh full application build or live Zotero/Word/LibreOffice/keychain acceptance. No GitHub Actions or CI endpoints were queried.
