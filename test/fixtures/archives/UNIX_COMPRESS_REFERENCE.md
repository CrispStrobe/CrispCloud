# UNIX compress (.Z) reference fixtures

These fixtures use original deterministic payloads. No VaultExplorer source,
assets or fixtures were used. The application decoder is an original bounded
Dart implementation; none of the external programs below is an application
dependency.

## Format references

- [OpenBSD compress(1)](https://man.openbsd.org/compress.1): LZW coding, 9–16-bit
  dictionary limits, adaptive dictionary reset and `.taz` naming.
- [libarchive compress reader](https://github.com/libarchive/libarchive/blob/d0bf2da07ebaa3964090ee936edea538d1602449/libarchive/archive_read_support_filter_compress.c):
  header flags, LSB code packing and historical group alignment. The reference
  file carries BSD licenses. It was consulted for format behavior; its source
  is not copied into the Dart implementation.
- [ncompress](https://github.com/vapier/ncompress/tree/03592d7a4702bb83558b6f1520c2a6a5381374c8):
  a separately compiled reference executable, version 5.1. Its `LICENSE.txt`
  and `UNLICENSE` declare a public-domain dedication. Only its documentation,
  build files and executable were needed; its implementation is not bundled.

The decoder validates the `1f 9d` signature, reserved header bits, 9–16-bit
dictionary range, forward references, bounded dictionary chains and partial
code/alignment bytes. Block streams reserve code 256 for dictionary reset;
nonblock streams use it as an ordinary dictionary entry. Both width changes
and resets finish the current eight-code group before the new width begins.
Dictionary and output storage are bounded independently of compressed claims.

## Fixture generation and independent checks

`generate_unix_compress_reference.py` uses the system **libarchive 3.7.4** C API
to write raw payloads through its compress filter. It also produces original
literal-code fixtures for the older nonblock profile and deliberate reset
alignment. **ncompress 5.1** decodes every fixture and its exact output is
compared with the original payload. **GNU gzip 1.13** independently decodes all
except the fixed nine-bit case described below.

Run the generator with a separately built reference executable:

```sh
python3 test/fixtures/archives/generate_unix_compress_reference.py \
  --ncompress /path/to/ncompress/compress
```

The generator writes `compress-reference-manifest.json` with packed and decoded
lengths and SHA-256 digests. Dart tests check both identities and the exact
decoded payload hashes.

| Fixture | Encoding | Decoded bytes | Boundary covered |
| --- | --- | ---: | --- |
| `compress-reference-empty.Z` | Original header-only stream | 0 | Empty payload |
| `compress-reference-text.Z` | libarchive | 43,200 | Dictionary references and width growth through 11 bits |
| `compress-reference-width-clear.Z` | libarchive | 426,000 | Growth through 16 bits and one dictionary reset |
| `compress-reference-nine-bit.Z` | ncompress `-b9` | 1,280 | Fixed nine-bit dictionary saturation |
| `compress-reference-nonblock.Z` | Original literal-code builder, checked by both tools | 4,608 | Nonblock dictionary and width-change padding through 13 bits |
| `compress-reference-clear.Z` | Original literal-code builder, checked by both tools | 4,608 | Dictionary reset at payload byte 1,301, including group padding |

The long libarchive payload is `CrispCloud compressed dictionary growth.\n`
repeated 6,000 times followed by 180,000 bytes from a 32-bit LCG seeded with
`0x12345678`, using multiplier `1664525`, increment `1013904223`, and the high
byte after each step. The smaller text fixture repeats
`CrispCloud UNIX compress reference.\n` 1,200 times. The other nonempty payloads
repeat the byte values 0 through 255.

Two observed reference-tool limitations are recorded rather than incorporated
into the implementation:

- libarchive 3.7.4's raw/compress writer emits a NUL byte for an empty raw input.
  The valid three-byte empty fixture is therefore constructed directly and
  independently checked with both reference decoders.
- GNU gzip 1.13 misdecodes the fixed nine-bit stream once its dictionary fills.
  ncompress 5.1's own `-b9` output and decoder agree on the fixture; the Dart
  decoder agrees with that exact payload. The ncompress change log records its
  nine-bit processing fix. Higher code-width and nonblock fixtures are checked
  with both reference decoders.

## Limits of integrity claims

UNIX compress has no stored uncompressed length and no payload checksum. A
truncated stream that is also a valid shorter sequence, or a bit change that
produces other valid dictionary codes, cannot be identified by decoding alone.
The reader therefore makes no checksum, completeness or publisher-authenticity
claim. A containing TAR can still validate its own member headers, and an
external expected file digest can establish a stronger content comparison.

Tests additionally cover every supported dictionary width in both modes,
dictionary saturation, the valid self-referential LZW case, repeated resets,
reserved flags, invalid and post-reset codes, partial code/group bytes, retained
padding bits, explicit output limits and the bounded compressed-input limit.
