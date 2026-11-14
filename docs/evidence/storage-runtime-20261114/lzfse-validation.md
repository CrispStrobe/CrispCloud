# LZFSE validation, 2026-11-14

The final standalone acceptance run qualifies the source files recorded in
[lzfse-source-sha256.json](lzfse-source-sha256.json). Their hashes were checked
before and after the commands. This receipt identifies file contents, rather
than assigning uncommitted work to a branch HEAD.

The tested decoder SHA-256 is:

```text
487cd93fc4582bf1e2fde8b32e44984ab42e396163ca4354f5652ab434c2082b
```

## Completed checks

| Check | Observed result | Receipt |
| --- | --- | --- |
| Original Apple fixture regeneration and strict decoding | 12 exact positive vectors; required multiblock-history negative control passed | [lzfse-fixture-reference.log](lzfse-fixture-reference.log) |
| Dart VM, production Dart 3.13.7 | 12 reference vectors, 489,825 output bytes, 76 negative/profile cases, 2,660 truncated prefixes; offset/preservation and budgets passed | [lzfse-vm.log](lzfse-vm.log) |
| Actual JavaScript compile, production Dart 3.13.7, `-O2` | Compilation passed | [lzfse-js-build.log](lzfse-js-build.log) |
| Compiled JavaScript, Node 24.22.1 | Same 12 positive, 76 negative and 2,660 truncation checks passed | [lzfse-js-run.log](lzfse-js-run.log) |
| Source, BSD notice and import verifier | Seven pinned source/license files and Dart boundary verified | [lzfse-source-verification.log](lzfse-source-verification.log) |
| Verifier tampering controls | Unchanged copy passed; four separate mutations were rejected for their expected reasons | [lzfse-verifier-controls.json](lzfse-verifier-controls.json) |
| External 7-Zip 26.06 UDIF extraction | Six exact successful extractions; six tool errors retained explicitly | [lzfse-sevenzip-report.json](lzfse-sevenzip-report.json) |

These counts describe overlapping validation paths and must not be added to
the native Flutter gate totals. The JavaScript check covers the actual decoder
and its SDK-only fixtures; it does not constitute a complete Flutter web or
WebAssembly application build.

## Reference and tool identity

The Apple reference is BSD-3-Clause revision
`e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`. The test-only C bridge compiles its
original sources with GCC 14.2.0. Python 3.12.14 orchestrates reference decoding,
manifest comparison and independent UDIF creation. Full version strings and
tool hashes are recorded in [lzfse-toolchain.json](lzfse-toolchain.json).

The external 7-Zip executable came from the publisher's
[26.06 release](https://github.com/ip7z/7zip/releases/tag/26.06), linked by the
[official download page](https://7-zip.org/download.html). The downloaded Linux
x64 archive was verified against its published SHA-256 before execution:

```text
7z2606-linux-x64.tar.xz
2b539cf067b2ad48e1baa5093dbaa8818b73542d1222a0ffde9dc5f2922ea62e

7zz executable
f94066e93f9a807547a3bff1021b3ec79d5ea4f57dfead018e9698182ad283b5
```

7-Zip remains an optional external validation tool. Its executable and source
were kept outside the repository and are not app dependencies or bundled code.

## Independent DMG results and oracle limits

Every tested image wraps its LZFSE stream in an independently written UDIF
partition using method `0x80000007`. Before invoking 7-Zip, Apple's original
decoder verifies the complete padded stream. The checker re-reads the UDIF XML
block map, confirms the sector length, and checks that the stored CRC32 equals
`zlib.crc32` of the entire sector-aligned partition, including zero padding.

| UDIF case | 7-Zip result |
| --- | --- |
| Genuine LZVN | Passed, exact 1,024 bytes |
| Genuine v2 | Passed, exact 32,768 bytes |
| Zero-entropy v2 | Passed, exact 8,192 bytes |
| Long-distance payload, sector-aligned before native encoding | Passed, exact 116,736 bytes |
| Natural multiblock payload, sector-aligned before native encoding | Passed, exact 100,352 bytes |
| Mixed v2 / LZVN / v2 | Passed, exact 66,560 bytes |
| V1 | Exit 2, `Unsupported Method` |
| Mixed stored / LZVN / v2 / v1 | Exit 2, `Data Error` |
| Natural multiblock followed by a stored sector-padding block | Exit 2, `Data Error`; output bytes match, still counted as a failure |
| V2 table reuse across stored data | Exit 2, `Data Error` |
| V1 table reuse across LZVN | Exit 2, `Unsupported Method` |
| Stored-only 512-byte control | Exit 2, `Data Error`; output bytes match, still counted as a failure |

The pinned
[7-Zip 26.06 LZFSE decoder source](https://github.com/ip7z/7zip/blob/26.06/CPP/7zip/Compress/LzfseDecoder.cpp)
explains the narrower oracle coverage. Its v1 branch returns `E_NOTIMPL`. Its
v2 header reader rejects a 32-byte header, so it cannot accept a v2 block that
omits previously supplied frequency tables. Its `DecodeUncompressed` loop does
not decrease the remaining `unpackSize` after copying bytes, which causes reads
to continue into subsequent framing and end with a data error. The stored-only
control and the two same-size multiblock images isolate that last behavior from
CRC calculations or sector alignment. The inspected source SHA-256 is recorded
with the toolchain receipt.

All twelve permanent LZFSE fixtures and all twelve UDIF oracle cases pass the
original Apple decoder. The six nonzero 7-Zip results remain failures in the
JSON evidence. No failed extraction is converted into a pass because its output
buffer happens to match the expected bytes.

`check_lzfse_dmg.py` returns a nonzero status for those results by default.
`--allow-oracle-limitations` permits only the six named cases, their observed
exit code 2 and the expected error classification; it leaves each error in the
report. An error in any of the six successful controls still fails the command.

## Commands

The receipts include the exact executable paths and commands used. From the
repository root, the portable equivalents are:

```sh
python3 tool/verify_lzfse_sources.py
python3 test/support/generate_lzfse_fixtures.py \
  --source /path/to/lzfse-reference --check

/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  test/support/lzfse_web_acceptance.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js -O2 \
  test/support/lzfse_web_acceptance.dart -o /path/to/work/lzfse.js
node /path/to/work/lzfse.js

python3 test/support/check_lzfse_dmg.py \
  --source /path/to/lzfse-reference \
  --sevenzip /path/to/7zz \
  --sevenzip-archive /path/to/7z2606-linux-x64.tar.xz \
  --work-dir /path/to/work/dmg-oracle \
  --allow-oracle-limitations
```

The verifier negative controls use fresh temporary copies of the snapshot and
derivative. They run `python3 tool/verify_lzfse_sources.py --repo-root <copy>`
after: appending a change to the pinned decoder source; updating that changed
source's length, SHA-256 and Git blob identity only in the manifest; adding an
unapproved `dart:io` import; and removing the derivative's initial BSD notice.
Each control requires exit code 1 and its expected diagnostic. The untouched
copy requires exit code 0. The production source tree is unchanged by these
controls.

The [fixture guide](lzfse-fixtures.md) describes the deterministic payloads,
v1-header derivation, table-reuse cases and malformed-input coverage.
