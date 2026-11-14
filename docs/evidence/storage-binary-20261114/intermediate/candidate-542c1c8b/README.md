# Failed saved candidate 542c1c8b

Both original gate receipts bind source revision
`542c1c8b97643e5ad2e7c44f35b5417ef95c7d6a`, tree
`d392e42e9f3678f4c265c3e5c9db56f510f32f58`, and **8,111 source paths**.
Both report `source_unchanged: true`, an unchanged package map, and exit code 1.
These are retained failures, not passing qualification for this or a later revision.

| Gate | Recorded outcome | Receipt |
| --- | --- | --- |
| Expanded native comparison/UI gate | 87 passed, 1 failed, 0 skipped. The reused-provider-buffer test expected `[1, 2, 3, 4]` and observed `[3, 4, 3, 4]`. | [Native receipt](final-native-receipt.json) |
| Strict scoped analysis | One `curly_braces_in_flow_control_structures` diagnostic. | [Analysis receipt](final-analysis-receipt.json) |

The receipts preserve their original bytes, filenames and hashes. The original
run-output names contained `final-`; that name does not imply these runs passed.
Later runs may reuse those output names, so this directory preserves this
candidate separately.

[files.json](files.json) maps every original receipt filename to its archived
file. Logs and native events have deterministic gzip compression; decompress
them to check their original SHA-256 values. The two source inventories were
byte-identical and are stored once as [source.json.gz](source.json.gz).
Its compressed SHA-256 remains
`f1d11b12ef4f42116cb674d39360a6e5f0c313da43fae6e8ec9b4e8aea6c4900`;
its uncompressed SHA-256 remains
`04e9240101a3ce85538f78865cf5d7201846d0417ac570bfbcbf16b68214cb6c`.
