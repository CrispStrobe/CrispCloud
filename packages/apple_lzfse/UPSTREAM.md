# Apple LZFSE decoder provenance

CrispCloud's bounded Dart decoder is adapted from
[Apple's LZFSE implementation](https://github.com/lzfse/lzfse) at commit
[`e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`](https://github.com/lzfse/lzfse/tree/e634ca58b4821d9f3d560cdc6df5dec02ffc93fd).
The applicable license is **BSD-3-Clause**, reproduced verbatim in [LICENSE](LICENSE).
The original copyright is retained in that file and in the Dart derivative.

## Exact source boundary

[UPSTREAM.json](UPSTREAM.json) records the original path, Git blob identity,
SHA-256 and byte length of each unmodified snapshot. The selected source files
all carry Apple's BSD license. The snapshot contains no separately licensed
third-party dependency, executable, binary library, or downloaded test corpus.

| Snapshot | Used for |
| --- | --- |
| `lzfse_decode_base.c` | Stream framing, v1/v2 headers and decode sequence |
| `lzfse_fse.c` and `lzfse_fse.h` | FSE table construction and bit-stream semantics |
| `lzfse_internal.h` | Format structures, bounded counts and L/M/D value tables |
| `lzvn_decode_base.c` | LZVN opcode layouts and history semantics |
| `lzfse_encode_base.c` | Reference for encoder padding and initial FSE states |

These files are retained under `upstream/` for review. They are not compiled,
linked, loaded with FFI, or included in the app's asset list. Only `LICENSE` is
bundled as an asset and registered in the app's license screen. No Pub dependency
is added. Independent fixture generation builds the pinned upstream project in
a separate test environment; the generated data is described with the fixtures.

## Dart adaptation

The maintained derivative is
[`lib/services/archive_lzfse_codec.dart`](../../lib/services/archive_lzfse_codec.dart).
It supports raw blocks, LZVN, LZFSE v1 and LZFSE v2 with a mandatory outer end
marker and exact input/output completion. Each call accepts at most 16 MiB of
input and 16 MiB of declared output, with at most 4,096 blocks. FSE tables and
literal/match counts are bounded; matches must refer to already decoded bytes.
Byte-based arithmetic avoids relying on 64-bit bitwise operations on the web.

The port adds checks beyond the reference's convenience buffer API: complete
end-marker consumption, exact block output, normalized frequency totals, final
FSE states and encoder padding. This intentionally bounded profile rejects
streams that do not meet its documented limits. It does not provide an encoder.
LZFSE has no embedded payload checksum; the UDIF reader separately checks a
present partition CRC during complete partition extraction.

The full BSD notice remains in the derivative. A change notice identifies this
as a Dart adaptation and describes its limits. The license grants source and
binary redistribution with attribution and disclaimer preservation; it grants
no endorsement by Apple or its contributors.

## Maintenance

`python3 tool/verify_lzfse_sources.py` verifies this exact snapshot against a
separate, fixed allowlist in the verifier and checks the derivative's attribution
and import boundary. Updating the JSON manifest alone cannot approve changed
upstream source. An upstream update requires review of the pinned diff, license
and dependency boundary, then updates to both records and the runtime tests.

Run the decoder tests on Dart VM and actual compiled JavaScript, and the DMG
integration tests through supported filesystem and raw partition workflows.
Validation receipts identify the source revision and the commands actually run;
this provenance record alone is not a passing test result.
