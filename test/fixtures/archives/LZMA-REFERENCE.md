# Original LZMA-alone reference fixtures

These files contain original deterministic test payloads compressed through
Python's independent `liblzma` binding. They use LZMA-alone framing with unknown
decoded size and a terminal marker. The tests additionally replace only the
size header to exercise the valid known-size-with-marker profile.

Regenerate them from the repository root:

```sh
python3 test/support/check_archive_lzma.py generate
```

| Fixture | Profile | SHA-256 |
| --- | --- | --- |
| `lzma-reference-default.lzma` | Default `lc=3, lp=0, pb=2`; 8 MiB dictionary | `e4ed2e9fa860e80616aec454d36a3cbd2500a705018a1c351017d80419c66c3d` |
| `lzma-reference-properties.lzma` | `lc=1, lp=2, pb=4`; 64 KiB dictionary | `0e7ab2971669f678dde610d45c405aaefb025f68dd697f59b41855cd1e98d2a2` |
| `lzma-reference-distance.lzma` | Repeated original pseudo-random 8 KiB regions; requires distances beyond 4 KiB | `7c63651994955303b404f83d6f4809736bf144ffb88ba9c6d14e116041ef2c24` |
| `lzma-reference-empty.lzma` | Empty payload with terminal marker | `da343da97420e033dcaf4bc7cb50f420bbe92f431b093aef89de45063c61fb17` |

`check_archive_lzma.py verify FRAME SOURCE` checks fresh writer output with
liblzma, requiring the exact payload, a completed stream and no ignored input.
The app's writer uses the already locked MIT `koni_codecs` encoder; it emits
known decoded size and no terminal marker, which is a valid LZMA-alone profile.
The reader handles both marker modes and validates the final range state and
exact compressed-input consumption. It rejects concatenation and trailing
bytes instead of hiding them from the rewrite policy.

The app uses the public, portable `RangeDecoder` primitives from MIT
`package:archive` through a format-specific packet driver. This is necessary
because its ordinary `LzmaDecoder` does not expose how much input it consumed.
No package cache modifications or native application dependencies are needed.

The reader supports `lc + lp <= 4`, dictionaries up to 64 MiB, and at most
64 MiB of compressed input and decoded output. Declared dictionary sizes below
4 KiB are interpreted as 4 KiB as required by the format. The writer's levels
select real dictionary limits from 4 KiB through 64 MiB, preserving content
while emitting canonical `lc=3, lp=0, pb=2` properties. LZMA-alone has no content
checksum; its range-coder validation is not a cryptographic integrity guarantee.

Primary references:

- [XZ project's LZMA-alone format document](https://github.com/tukaani-project/xz/blob/master/doc/lzma-file-format.txt)
- [Igor Pavlov's LZMA specification, distributed with the SDK](https://android.googlesource.com/platform/external/lzma/+/refs/heads/nougat-dev/DOC/lzma-specification.txt)
