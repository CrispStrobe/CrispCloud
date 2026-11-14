# LZFSE reference fixtures

These fixtures use deterministic synthetic payloads and the original Apple
LZFSE implementation at
[`e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`](https://github.com/lzfse/lzfse/tree/e634ca58b4821d9f3d560cdc6df5dec02ffc93fd).
That implementation is BSD-3-Clause. The fixture generator builds the reference
in a separate temporary test environment. No native codec or executable is
added to CrispCloud's runtime dependencies.

The payload generator and framing helpers are independent of the Dart decoder.
Every complete fixture is checked by Apple's original decoder for the exact
output bytes, its terminal end-of-stream state, and complete input consumption.
The native output buffer has spare space, preventing a full buffer from hiding
an unfinished decode. The C bridge calls the original stateful decoder for this
reason; the public buffer API treats a full output buffer as a successful-sized
return even when the complete stream has not been consumed.

## Files

| File | Purpose |
| --- | --- |
| `test/support/generate_lzfse_fixtures.py` | Pinned reference build, deterministic encoding, original-decoder verification, manifest/data regeneration |
| `test/support/lzfse_reference_helper.c` | Test-only bridge to Apple's original decoder and v2 header expansion |
| `test/support/lzfse_reference_data.dart` | Generated base64 streams for browser-safe tests |
| `test/support/lzfse_fixture.dart` | Expected payloads, derived mixed streams, independent test framing |
| `test/fixtures/archives/lzfse-reference-manifest.json` | Encoded/decoded SHA-256 values, byte counts and block layout |
| `test/support/lzfse_malformed_fixture.dart` | Shared malformed and bounded-profile exclusions |
| `test/archive_lzfse_codec_test.dart` | Native Flutter unit suite |
| `test/support/lzfse_web_acceptance.dart` | SDK-only VM and actual compiled-JavaScript acceptance runner |
| `test/support/check_lzfse_dmg.py` | Independent UDIF writer, Apple reference and external 7-Zip cross-check |

The Dart fixture and acceptance helpers import only Dart SDK libraries and the
actual decoder source. The browser checks read no local fixture files and invoke
no native codec.

## Twelve permanent positive fixtures

| Name | Output bytes | Encoded bytes | Coverage |
| --- | ---: | ---: | --- |
| `empty` | 0 | 12 | Empty stored block and complete outer end marker |
| `raw` | 7 | 19 | Genuine Apple stored fallback |
| `lzvn` | 1,024 | 73 | Genuine LZVN compression and inner/outer end markers |
| `v2` | 32,768 | 1,009 | Genuine entropy-compressed v2, sector-aligned for DMG tests |
| `v2_zero` | 8,192 | 151 | Zero-entropy and long overlapping matches |
| `distance` | 116,384 | 8,569 | Repeated 8,192-byte history separated by 100,000 bytes |
| `multiblock` | 100,000 | 50,733 | Two naturally emitted compressed blocks with shared history |
| `v1` | 32,768 | 1,559 | Original Apple v2-to-v1 header expansion, original coded payload |
| `mixed` | 66,567 | 2,648 | Stored, LZVN, v2 and v1 blocks under one outer end marker |
| `v2_reused_tables` | 65,542 | 1,838 | V2 frequency-table reuse across an intervening stored block |
| `v1_lzvn_reused_tables` | 66,560 | 2,443 | V1-supplied tables reused by v2 across an intervening LZVN block |
| `cross_block_lzvn` | 13 | 37 | A small-distance match reads earlier stored history and overlaps itself |

The generator also proves that the second natural compressed block cannot be
decoded alone: Apple's decoder rejects it without the first block's history.
That negative control distinguishes real cross-block history from concatenating
separately encoded blocks.

V1 data is not labeled as native v1 encoder output. Apple's own header-expansion
function expands a genuine v2 header, and the original entropy payload is kept
byte-for-byte. Apple's original decoder then verifies the resulting v1 stream.
Mixed streams retain the constituent block bytes and replace their individual
outer end markers with one final marker. The table-reuse fixtures retain coded
payloads while omitting the second v2 frequency table, as supported by the
original format reader.

## Failure and profile coverage

The permanent shared corpus contains **76 negative cases**. These cover absent
or trailing end markers, exact output mismatches, unsigned header overflow on
JavaScript, frequency normalization, malformed compressed tables, state/count
bounds, missing table history, LZVN opcode/operand truncation, invalid history,
previous-distance reset at block boundaries, and the documented canonical
padding policy. The suite separately rejects all **2,660 incomplete prefixes**
of the raw, LZVN, v1 and v2 streams.

Cases prefixed `profile rejects` exercise CrispCloud's documented bounded
decoder profile. They are not claims that every permissive native decoder must
reject those byte patterns. The profile requires complete end-marker and bit
consumption, canonical final FSE states, normalized tables and zero encoder
padding. Those restrictions are documented on `decodeArchiveLzfse`.

Additional acceptance assertions cover nonzero typed-data offsets, input
preservation, the 4,096-block boundary, 16 MiB input/output ceilings, and a caller
lowering its output limit. Tests compare every expected byte on both VM and
actual compiled JavaScript.

## Regeneration

Use an unmodified checkout of the pinned Apple repository and a POSIX C compiler:

```sh
git clone https://github.com/lzfse/lzfse.git /path/to/lzfse-reference
git -C /path/to/lzfse-reference checkout e634ca58b4821d9f3d560cdc6df5dec02ffc93fd
python3 test/support/generate_lzfse_fixtures.py \
  --source /path/to/lzfse-reference --check
```

The generator checks both the checkout revision and changes to `src/` or
`LICENSE`. `--write` regenerates the committed Dart data and JSON manifest;
`--check` compares regenerated content exactly. `--work-dir /path/to/work`
retains native reference output and `.bin`/`.lzfse` vectors for inspection.

See [lzfse-validation.md](lzfse-validation.md) for exact tested tool versions,
source identities, command receipts and the external 7-Zip limitations observed
while checking the UDIF wrappers.
