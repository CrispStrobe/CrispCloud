# Original Lzip reference fixtures

These files contain deterministic original payloads compressed by libarchive's
Lzip writer. The generator independently decodes the raw LZMA stream through
liblzma, checks its required end marker and exact consumption, and verifies
the Lzip CRC32, decoded-size and member-size trailer with Python `zlib` and
`struct`. No GPL implementation or third-party archive payload was copied.

Regenerate them from the repository root:

```sh
python3 test/support/generate_lzip_reference.py
```

| Fixture | Payload | SHA-256 |
| --- | --- | --- |
| `lzip-reference-default.lz` | Original repeated text | `de0fd86db8e4eaaefb3fde2b3d65590832afe052e876bbffe907f9ac601331fe` |
| `lzip-reference-distance.lz` | Repeated original pseudo-random 8 KiB regions | `196ccb29248b700f767fd2b8432af261487c9aa5712a07ba942d1dcee9314bdb` |
| `lzip-reference-tiny.lz` | One byte, `x` | `97cd4f3ea4bde55b1a9f869204d4966e37d6ca96c59d00b05f95b47a9e2d1d46` |
| `lzip-reference-empty.lz` | Empty single member | `3b73bb6ddf1f0dc41d0cf5f2eb4231abbd1ef3613878fe7101ebcd4d22624c27` |

The reader supports Lzip v1, exact consecutive nonempty members, fractional
dictionary codes within 4 KiB–64 MiB, and the existing 64 MiB compressed/decoded
limits. A standalone empty member is valid. Empty members in collections are
refused in accordance with the published format. Version 0, out-of-range
dictionaries, missing end markers, mismatched checksums/sizes and trailing
opaque bytes are explicitly rejected. There is no Lzip writer in this change.

The implementation uses the strict portable LZMA packet driver already in
CrispCloud, synthesizing only its fixed properties and unknown-size header so
that an end marker remains mandatory despite the known footer size. The native
libraries are optional fixture-generation tools and are not app dependencies.

Primary format reference: [Lzip file format](https://www.nongnu.org/lzip/manual/lzip_manual.html#File-format).
