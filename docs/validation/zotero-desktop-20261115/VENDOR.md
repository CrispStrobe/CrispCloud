# Independent managed-source verification

The full streaming audit covered CrispCloud code commit
`3c4cd0e24ab36f4fd88363cbc8521455bda811c6`, pinned to Quds
`1cc4d251ebeb3e0cce205805e9183396da0c0df4`.
All 2,374 managed files matched the manifest SHA-256 values and exact Git
blob IDs, sizes and executable modes. No managed file was absent, duplicated,
a link or another special file. Of these, 517 matched the canonical Quds tree
and 1,857 matched standalone legacy-doc-parser `4895712158127b2fc930d796e17035c3ca0dac62`.

The verifier streamed the complete public commit archive without storing it or
extracting managed source. `vendor-stream-receipt.json` and
`stream-verification.log` record the observed results. `vendor-verification.tar.gz`
contains those files, the exact original manifest, metadata inventories, full
verified TSV hash inventory, and the original verifier. Extract that evidence
archive into a fresh directory and run `python verify-stream.py` to reproduce
the recorded checkpoint audit; the verifier reads its exact pinned public
archive. It does not use GitHub Actions.

The final source repin also carries the two updated package changelogs. The
separate [final integration receipt](final-integration.json) compares that small managed-file delta to
the already verified checkpoint and validates their new hashes and canonical
source identities. Implementation and test bytes retain the tested hashes.
