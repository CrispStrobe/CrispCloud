# ADC, LZFSE and XZ/LZMA disk-image reading

CrispCloud's positional UDIF reader accepts ADC (`0x80000004`, UDCO),
LZFSE (`0x80000007`, ULFO) and XZ/LZMA (`0x80000008`, ULMO). They feed the
same raw-partition and supported HFS+/HFSX/ISO filesystem views as raw, zero-fill,
zlib and bzip2 blocks. The shared viewer routing makes these readable through
F3, archive panes, extraction and archive testing.

ADC has three token forms: literals, short backward matches and long backward
matches. The decoder checks the complete token stream and exact block-map
output length before allocating its output. It handles overlapping matches and
rejects truncated tokens, references before the output history, excess output
and extra encoded data. ADC itself has no checksum or end marker; a present UDIF
partition CRC is checked when the complete raw partition is extracted.

ULFO blocks use a bounded Dart adaptation of Apple's BSD-3-Clause decoder,
pinned at `e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`. It reads raw, LZVN, LZFSE
v1 and LZFSE v2 blocks, including mixed streams and matches across blocks. It
requires exact declared output, a complete `bvx$` end marker and complete input
consumption. A full output buffer alone is not treated as successful decoding.
The decoder checks frequency totals, states, match history, bit consumption and
encoder padding. Each stream is limited to 4,096 blocks, with at most 40,000
literals and 10,000 nonempty L/M tuples per FSE block. This bounded profile
rejects streams beyond those limits. LZFSE itself has no payload checksum.
See [source provenance and distribution license](../packages/apple_lzfse/UPSTREAM.md).

ULMO blocks use XZ framing. The existing locked XZ decoder verifies framing and
present integrity checks, with a 16 MiB dictionary ceiling. LZMA-alone data is
not substituted for XZ. Both packed and expanded compressed chunks retain the
reader's 16 MiB limit, and the output length must exactly match the block map.
Metadata/member/input limits and source ownership are unchanged. One decoded
chunk is cached across partition views; a whole disk is never required merely
to open its supported filesystem.

These additional profiles are read-only. The canonical HFSX DMG writer still
requires its separately inspected raw/zero/zlib layout. Encrypted images,
segmented images, APFS file browsing and binary-resource-fork-only maps remain
unsupported. Filesystem previews do not authenticate publisher signatures or
verify every unvisited chunk; full partition extraction checks its present CRC.

## Format references

- [libmodi's disk-image format description](https://github.com/libyal/libmodi/blob/0c7af7a5fc08c833a4acb958416a971ef352afea/documentation/Mac%20OS%20disk%20image%20types.asciidoc)
  identifies UDCO/ULFO/ULMO and the block method values.
- [ADC format and fixture description](https://github.com/go-compressions/adc/tree/3dbe188981fa046d9b58696ba6e034c6b68b57a6)
  describes the three byte-level token layouts and the independently produced
  hdiutil sample. The decoder is an independent Dart implementation of that
  byte format; no Go or native decoder source is included.
- [Apple's pinned LZFSE source](https://github.com/lzfse/lzfse/tree/e634ca58b4821d9f3d560cdc6df5dec02ffc93fd)
  defines the LZFSE/LZVN stream and provides the independent encoder and decoder
  used by the fixture generator. The selected C source snapshots are review
  material; no native codec is linked into CrispCloud.

## Verification sources

`test/archive_adc_codec_test.dart` covers the independent stream, token/offset
boundaries, overlapping copies, strict input/output completion and resource
limits. `test/archive_dmg_reader_test.dart` exercises both methods through the
UDIF reader, supported filesystem views, buffered and streamed raw extraction,
partition checksums, source closure, dictionary refusal and writer exclusion.

`test/archive_lzfse_codec_test.dart` covers Apple-encoded LZFSE/LZVN streams,
v1 headers derived through Apple's own header reader, mixed and cross-block
history, malformed metadata and bounded completion. Browser-safe fixtures keep
the codec usable in actual compiled-JavaScript acceptance. The generator
`test/support/generate_lzfse_fixtures.py` requires the exact pinned source and
checks the reference decoder's terminal state and consumed input. Fixture
identities are retained in `test/fixtures/archives/lzfse-reference-manifest.json`.

The independently generated streams and retained license are described in
`test/fixtures/archives/dmg-codecs/README.md`. Run
`python test/support/check_dmg_codecs.py --sevenzip /path/to/7zz` to verify those
streams inside independently assembled UDIF containers with an external reader
supporting both methods (verified with 7-Zip 26.06; 23.01 refuses ULMO).
The combined integration receipt records executed results and their revision;
the presence of this guide alone is not a test result.
