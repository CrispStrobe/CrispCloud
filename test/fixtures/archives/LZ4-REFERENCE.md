# Original LZ4 reference fixtures

These fixtures contain original deterministic test data compressed by the
independent `liblz4` 1.10.0 implementation. No application serializer, third-party
archive contents, or GPL implementation was used to produce them.

Regenerate them from the repository root:

```sh
python3 test/support/check_archive_lz4.py generate
```

| Fixture | Profile | SHA-256 |
| --- | --- | --- |
| `lz4-reference-linked.lz4` | Linked 64 KiB blocks, content size, block and content checksums; later blocks actually require earlier history | `56633b54e02e401184d73f688e74b780e3ec246735219d51905659ea5f592ea6` |
| `lz4-reference-independent.lz4` | Independent blocks, content size, both checksum types | `05ccace85cbece56043dfbe5800e57c1aae82d3094b880e487c845a5744bd0a7` |
| `lz4-reference-unchecked.lz4` | Independent blocks, no declared content size or optional checksums | `5f9dae6f363707611c13d4ea828c5967de5fa8befb6c2c9cb4a9237a6c39ef0f` |
| `lz4-reference-stored.lz4` | Incompressible data emitted as a stored block | `8a78d73c156264de0e05bd4e4d215be77edf58d47706fad1fb840709ceff9408` |
| `lz4-reference-empty.lz4` | Empty data frame | `1829a9507d05badea902f965a15399c2e319389efb3577ddd9a70063d1c68a5b` |

The test suite also passes fresh CrispCloud compressed and stored output to
`check_archive_lz4.py verify FRAME SOURCE`. The script requires exact content and
input consumption from the reference decompressor. Native libraries are optional
validation dependencies; the app's LZ4 reader and writer use portable Dart only.

Implementation references are the public [LZ4 frame format][frame],
[LZ4 block format][block], and [XXH32 algorithm specification][hash]. The encoder
uses an original bounded hash-table match finder and upgrades fresh/eligible
rewritten frames to include known content size plus block and content checksums.
It emits independent 256 KiB blocks, using stored blocks when compression would
not save space. A frame collection or skippable extension metadata is readable
but cannot be represented by this one-frame writer without losing its framing.
External dictionaries and legacy LZ4 framing are explicitly rejected.

[frame]: https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md
[block]: https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
[hash]: https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md
