# Completed canonical qualification

The complete fresh run passed **1,104 tests across 70 disjoint files with zero skips** at Quds `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`: 576 Zotero tests and 528 integration tests. All twelve commands passed, including strict analysis and formatting of 37 targets.

The [receipt](receipt.json) binds exact commands, results and original raw-log hashes to the source tree and the executed [runner](run-qualification.py). All 1,568 selected canonical inputs, 3,857 external dependency/runtime inputs, locked harness inputs and four separately observed system-font paths remained unchanged. The analyzer configuration was restored.

[invocation.json](invocation.json) is the exact complete-run invocation. [artifact-inventory.json](artifact-inventory.json) maps every losslessly compressed artifact to its original name and SHA-256. Run `gzip -dk` on each `.gz` file to restore original bytes before independently checking the receipt.

The [independent PDF receipt](poppler/receipt.json) records successful raster and extraction checks on the fresh synthetic Unicode-alias fixtures. The two 320 by 112 rasters are pixel-identical, and both the directly encoded and Word-exported PDFs extract the authored code points. The [source and producer binding](poppler-binding.json) ties those inputs to the completed producer receipt. The [original verifier](verify_pdf_rendering.py) and [path-selection wrapper](run-current-pdf-verification.py) are retained unchanged. The wrapper only selects the isolated checkout after verifying source/producer identity. These checks add no Dart/Flutter test cases and make no broad emoji, CJK, shaping-parity or platform-conformance claim.

All earlier setup, interrupted and failed attempts are preserved separately and excluded from this fresh total. This is focused local qualification, not a new full application build or live Zotero/Word/LibreOffice/keychain acceptance.
