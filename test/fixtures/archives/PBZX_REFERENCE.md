# PBZX reference fixtures

These two PBZX streams contain only the original libarchive-generated
[`reference-odc.cpio`](CPIO_ODC.md), with its three ordinary test entries.
They contain no Apple software or proprietary package payloads.

The fixture generator uses Python's native liblzma binding for XZ compression
and a small, explicit big-endian framing emitter. Its output is then decoded by
the **unchanged upstream PBZX parser** in
[BIOSUtilities](https://github.com/platomav/BIOSUtilities/tree/f799425af93264b62a2f3c3cc5bbabf8a2226114),
commit `f799425af93264b62a2f3c3cc5bbabf8a2226114`.
The complete resulting CPIO bytes must equal the independent original before a
fixture is written. This checks the framing with a separate implementation;
neither CrispCloud's PBZX reader nor its CPIO parser participates in generation.

## Reproduction

From the repository root:

```sh
git clone https://github.com/platomav/BIOSUtilities.git build/pbzx-reference
git -C build/pbzx-reference checkout f799425af93264b62a2f3c3cc5bbabf8a2226114
python3 test/support/generate_pbzx_reference.py build/pbzx-reference
python3 test/support/generate_pbzx_reference.py build/pbzx-reference --check-only
```

The generator checks the reference commit and refuses modified tracked files.
It imports `biosutilities/apple_efi_pbzx.py` directly, which needs only the Python
standard library for this operation. After its PBZX decoder writes a CPIO file
and validates the complete decoded length, the generator intercepts the optional
7-Zip handoff to capture that CPIO. The reference framing and decompression code
are not modified. No 7-Zip executable, firmware extraction, or external package
installation is needed.

## Cases and recorded hashes

| Fixture | Framing and compression | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `reference-odc.pbzx` | Block size 256; first 256 decoded bytes use an XZ stream with CRC64 (172 stored bytes); final 125 bytes are stored | 341 | `b67a566e5663f0ef8ab632e7c3af10f51e97c9938432950c764a959860c7796f` |
| `reference-odc-unchecked.pbzx` | Block size 16 MiB; one 381-byte decoded chunk using XZ without a data checksum (196 stored bytes) | 224 | `6f96c2ca3612d747f96dab14a1b273f2c8b5a0d1b4e43de90b013545392a05af` |

The mixed stream places the final file's CPIO header across the compressed/stored
boundary. Both streams decode to exactly **381 bytes**, SHA-256
`654f5817c061f00101f57a70e014c1762eb33d58a17923a3ccedfcd0907d4729`.
The recorded generator uses Python's `lzma` module with liblzma **5.8.1**, preset
6 (8 MiB dictionary). Other encoder versions may emit different but equivalent
XZ bytes; changing a checked-in fixture requires recording its hashes again.

The checksum-free case reflects a valid PBZX/XZ profile and makes no claim of
payload authenticity or package signature verification. For comparison, the
[go-macos-pkg format notes](https://github.com/deploymenttheory/go-macos-pkg/blob/main/docs/formats/payload.md)
document this profile from Apple's package output. Framing integers represent
block, decoded, and stored sizes; they are not continuation flags.

## License and boundary

BIOSUtilities is copyright Plato Mavropoulos, licensed under
[BSD-2-Clause-Patent](https://github.com/platomav/BIOSUtilities/blob/f799425af93264b62a2f3c3cc5bbabf8a2226114/LICENSE).
Its source remains in the separate optional reference checkout; no upstream
parser code is copied into or loaded by the app. The checker invokes its parser
only on these small trusted fixtures, not on arbitrary input.
The original generator and payloads are repository test material.

This establishes interoperability with an independent PBZX implementation and
native liblzma. It does not establish macOS installer acceptance or validate
publisher signatures.
