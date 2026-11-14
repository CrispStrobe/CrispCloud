# Independent partition inspector review

The service and its fixtures were reviewed against
[UEFI 2.11, chapter 5](https://uefi.org/specs/UEFI/2.11/05_GUID_Partition_Table_Format.html),
with emphasis on false clean reports, metadata placement, unsigned arithmetic,
source consistency, cancellation and resource limits. The independent
regressions are in `test/disk_partition_inspector_review_test.dart`; the service
author retained ownership of the implementation and its original test suite.

## Findings resolved

1. **Reserved GPT header bytes could produce a clean report.** Revision 1.0
   reserves the bytes after offset 92. Changing those bytes in a standard
   92-byte header does not affect its CRC. The service now reports the nonzero
   reserved region and exposes its actual metadata range for selection. The
   regression covers primary and backup headers with 512- and 4,096-byte sectors.
2. **Protective MBR validation omitted required reserved fields.** The service
   now checks its disk signature, reserved word, boot flag, starting CHS,
   additional records and the reserved tail of a 4 KiB sector. These produce
   protective-MBR findings. A separate legacy-MBR control confirms that the
   protective-only restrictions are not applied to ordinary legacy records.
3. **A successful signature probe could authenticate different full-header
   bytes.** Both selected full headers are now read before following arrays,
   and their signatures are rechecked. A probe/full-read disagreement throws an
   I/O consistency error, including when the altered header has a recalculated
   valid CRC. Both primary and backup cases are covered.
4. **An array could be read inside the peer header's partition area.** Own-header
   placement checks did not catch contradictory mirrors. The service now also
   checks a physically plausible peer's usable range before following either
   pointer. Both direction regressions preserve valid header CRCs and assert
   that the conflicting array remains unchecked and is never read.

No remaining blocking issue was found in the reviewed implementation. The
read-only API retains caller ownership of the source, represents unsigned LBAs
with `BigInt`, validates their ranges before converting them to read offsets,
and bounds table bytes, entry counts, findings and individual reads.

## Regression results

All **20 independent review tests passed on actual compiled JavaScript under
Node 24.22.1, using production Dart 3.13.7**. The checked source identities and
exact command are in [partition-review-receipt.json](partition-review-receipt.json),
and the test output is in [partition-review-node.log](partition-review-node.log).
Hashes were checked before and after the command.

For this JavaScript run, a temporary test copy changes only the import from
`package:flutter_test/flutter_test.dart` to `package:test/test.dart`. The test
logic and fixture bytes are unchanged, and the harness imports the actual live
application library through its existing symlink. The canonical Flutter test
remains unchanged in the repository. Native gate receipts are recorded
separately; their counts overlap this review suite.

The additional review controls check late short and oversized reads, cancellation
during final snapshot validation, two 1 MiB partition arrays at the global
metadata budget, and the last complete sector below JavaScript's exact-integer
ceiling (`2^53 - 512` bytes). The maximum-offset case passes with exact backup
header offsets and bounded sparse reads; no huge file or payload is allocated.

The review preserves the declared scope: primary MBR records and bounded GPT
metadata at 512 or 4,096 logical bytes per sector. It does not introduce EBR
chain traversal, filesystem parsing, repair actions or disk writes.
