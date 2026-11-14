# Independent UDF and ZIP recovery controls

The application contains original Dart UDF/recovery code and its existing
permissive archive dependencies. The mastering and extraction executables below
are external verification tools. Their source and binaries are not shipped with
CrispCloud, and no native or Pub dependency was introduced for these tests.

## UDF: independently mastered input

`test/support/generate_udf_reference.py` runs an external **genisoimage 1.1.11**
and supplies four original payloads: a text file, an empty file, a Unicode-named
UTF-8 file, and a nested 8,193-byte binary file. It masters an ISO/Joliet/UDF 1.02
bridge using physical partition maps and ordinary short allocation descriptors.

The executable was extracted into scratch from the official Debian package:

- [Debian package and published checksum](https://packages.debian.org/trixie/amd64/genisoimage/download)
- Package `genisoimage_1.1.11-4_amd64.deb`, SHA-256
  `e6dc605d0ef3fc375d6cc96c16af32b48a1053e2f08db769d3483d3c7fdb6884`.
- Executable SHA-256
  `48dd2cf116561683a4a4a32c51570590fc79bcc6bcce6fc806a3c3ee4f3b8118`.

The generator normalizes UDF descriptor timestamps and the generated volume-set
identifier for reproducibility. It recalculates tag checksums and CRC-16 using
Python's standard `binascii.crc_hqx`; it does not call the Dart reader or fixture
assembler. File timestamps and ISO volume timestamps are fixed before mastering.

Three exact images are embedded, gzip/base64 encoded, in
`test/support/archive_udf_reference_data.dart`. The fixture manifest records
their hashes, the external executable hash, command arguments, original payload
hashes and the explicit derived extent layout.

| Image | Origin and qualification |
| --- | --- |
| `mastered-bridge` | Externally mastered ISO/Joliet/UDF 1.02 bridge, with the deterministic metadata normalization above. |
| `derived-udf-only` | The same independently mastered UDF filesystem; ISO recognition records are removed and the original BEA01/NSR02/TEA01 records move to sectors 16–18. This is an explicit derivative, not a separate mastering-tool output. |
| `derived-fragmented` | The UDF-only derivative with one file's original 8,193 bytes redistributed within its original five allocated sectors and described by three short extents in nonascending physical order. The file entry's CRC and allocation-descriptor length are updated. |

Each image is 894,976 bytes. All three are recognized as UDF 1.02 and extracted
without errors by external **7-Zip 26.06**. The resulting four regular files per
image match the independent payload manifest exactly: names, lengths and
SHA-256, including the empty and Unicode-named files. The oracle reports **three
successful images and twelve exact file matches**. The original fragmented
payload remains 8,193 bytes; no physical multi-gigabyte extraction is implied.

`check_archive_udf.py` reads the *committed* embedded image bytes, verifies their
fixed image hashes, extracts them with the supplied external executable, and
compares every extracted regular file against the independent manifest. A
nonzero extraction exit status fails the check. The executable SHA-256 is
`f94066e93f9a807547a3bff1021b3ec79d5ea4f57dfead018e9698182ad283b5`.

`verify_archive_udf_fixtures.py` is a separate Python integrity control that needs
no external executable. It verifies the same three image hashes and **93
descriptor CRCs/tag checksums/locations** across their known volume, integrity,
file-set, file-entry and directory descriptor inventories. It is intentionally a
validator for these fixed reference images, not another general UDF reader.

## ZIP: independent source streams and candidate readback

`test/support/generate_zip_recovery_reference.py` uses Python's standard
`zipfile` writer with original payloads and fixed ZIP metadata. The generator
does not share code with the recovery scanner, Dart ZIP encoder or Koni reader.
Generation was reproduced byte for byte with Python **3.12.14** and zlib
**1.3.2**. The embedded data and manifest record twelve cases:

- Complete ZIP and the same local records after removing the central directory.
- Deflate members with signed and unsigned 32-bit data descriptors.
- A stored member whose data-descriptor boundary is deliberately unsupported.
- A truncated final member after two verified members.
- A bad-CRC member after a verified prefix.
- Duplicate names, an unsafe name followed by a safe member, and explicit ZIP64.
- A data descriptor whose measured length does not match.
- A 26,003-byte incompressible deflate member with a signed descriptor, followed
  by a stored member. Its packed input crosses three 8 KiB decoder input
  boundaries, exercising continuation and exact framing after end-of-stream.

The portable Dart driver checks the expected recoverable entry inventory,
recovered payload hashes, caller-owned source lifetime, input preservation,
private snapshot isolation, selection immutability, bounded candidate output and
cancellation. Candidate bytes are immutable and already pass the application's
independent Koni readback. The driver can also emit its actual candidate ZIPs as
base64 JSON for an additional external implementation check.

`check_archive_zip_recovery.py` reads that JSON with Python `zipfile`, checks the
candidate inventory against the independent fixture manifest, verifies every
member CRC with `testzip()`, and compares each file's length and SHA-256. It does
not trust the Dart receipt for expected names or expected hashes. **Eight
candidate ZIPs and fourteen recovered file payloads pass**. Cases with no
recoverable entries are required to refuse candidate creation.

## Reproduction commands

Run in a checkout with the original production dependencies resolved. Direct
`dart` execution avoids invoking unrelated native build hooks. The JavaScript
commands compile and execute the actual reader/recovery implementations.

```sh
dart test/support/archive_udf_web_acceptance.dart
dart compile js -O2 test/support/archive_udf_web_acceptance.dart -o /tmp/udf.js
node -e 'globalThis.self = globalThis; require(process.argv[1]);' /tmp/udf.js

dart test/support/archive_zip_recovery_web_acceptance.dart
dart compile js -O2 test/support/archive_zip_recovery_web_acceptance.dart -o /tmp/zip.js
node -e 'globalThis.self = globalThis; require(process.argv[1]);' /tmp/zip.js

python3 test/support/verify_archive_udf_fixtures.py --report /tmp/udf-fixtures.json
dart test/support/archive_zip_recovery_web_acceptance.dart --emit-candidates > /tmp/zip-candidates.json
python3 test/support/check_archive_zip_recovery.py --candidates /tmp/zip-candidates.json --report /tmp/zip-oracle.json

# Optional independent extraction; the executable remains outside the app.
python3 test/support/check_archive_udf.py --sevenzip /path/to/7zz --report /tmp/udf-sevenzip.json

# Optional exact external-master regeneration into a disposable directory.
python3 test/support/generate_udf_reference.py --genisoimage /path/to/genisoimage --output-dir /tmp/udf-reference
python3 test/support/generate_udf_reference.py --genisoimage /path/to/genisoimage --output-dir /tmp/udf-reference --check
python3 test/support/generate_zip_recovery_reference.py --output-dir /tmp/zip-reference
python3 test/support/generate_zip_recovery_reference.py --output-dir /tmp/zip-reference --check
```

## Scope of the evidence

The portable UDF driver adds synthetic cases for the supported revision and
allocation forms, a precise physical offset of 6,144,000,040,960 bytes, and an
8 GiB sparse logical file with a bounded 17-byte zero prefix. Those large cases
use sparse positional sources; they are not full physical disk extractions.
The supplemental 60-test UDF VM/Node harness keeps the production reader and
fixture source unchanged and changes only the test package import from
`flutter_test` to `test` in an isolated copy. Its receipt records that adaptation.

The independent oracles establish agreement for these selected profiles and
fixtures. They do not qualify UDF writing, virtual/sparable/metadata partition
maps, deleted-file carving, filesystem repair, encrypted ZIP recovery, split ZIP
sets or ZIP64 recovery. Native widget gates, production release qualification
and exact source hashes are recorded separately in this evidence directory.
