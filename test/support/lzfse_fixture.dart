import 'dart:convert';
import 'dart:typed_data';

import 'lzfse_reference_data.dart';

/// Deterministic synthetic payload and independently encoded LZFSE stream.
///
/// The original Apple decoder verifies the exact output, its end-of-stream
/// state and complete input consumption. See generate_lzfse_fixtures.py and
/// test/fixtures/archives/lzfse-reference-manifest.json for reproduction and
/// hashes. This helper uses only Dart SDK libraries, including on the web.
class LzfseFixture {
  LzfseFixture(this.name, this._plain, this._packed);

  final String name;
  final Uint8List Function() _plain;
  final Uint8List Function() _packed;

  Uint8List get plain => _plain();
  Uint8List get packed => _packed();
}

LzfseFixture _reference(String name, Uint8List Function() plain) =>
    LzfseFixture(name, plain, () => base64Decode(lzfseReferenceData[name]!));

Uint8List _noise(int length) {
  var state = 173;
  final result = Uint8List(length);
  for (var i = 0; i < length; i++) {
    // The largest product is below 2^53, so Dart VM and JS agree exactly.
    state = (state * 48271) % 2147483647;
    result[i] = state % 256;
  }
  return result;
}

Uint8List _v2Plain() => Uint8List.fromList(
  List<int>.generate(32768, (i) => (i * 17 + i ~/ 251) % 256),
);

final lzfseEmptyFixture = _reference('empty', () => Uint8List(0));
final lzfseRawFixture = _reference(
  'raw',
  () => Uint8List.fromList(List<int>.generate(7, (i) => i)),
);
final lzfseLzvnFixture = _reference(
  'lzvn',
  () => Uint8List.fromList(
    utf8.encode('CrispCloud archive LZVN reference. ' * 40).sublist(0, 1024),
  ),
);

/// Sector-aligned, genuinely entropy-compressed stream for UDIF integration.
final lzfseV2Fixture = _reference('v2', _v2Plain);
final lzfseV2ZeroFixture = _reference('v2_zero', () => Uint8List(8192));

/// Apple's original v2-to-v1 header expansion preserves the coded payload.
final lzfseV1Fixture = _reference('v1', _v2Plain);
final lzfseDistanceFixture = _reference(
  'distance',
  () => Uint8List.fromList([
    ..._noise(8192),
    ...List<int>.filled(100000, 90),
    ..._noise(8192),
  ]),
);

/// Two naturally emitted compressed blocks. Decoding the second in isolation
/// fails in Apple's decoder because it refers to the first block's history.
final lzfseMultiblockFixture = _reference(
  'multiblock',
  () => Uint8List.fromList([..._noise(50000), ..._noise(50000)]),
);

final lzfseMixedFixture = LzfseFixture(
  'mixed',
  () => Uint8List.fromList([
    ...lzfseRawFixture.plain,
    ...lzfseLzvnFixture.plain,
    ...lzfseV2Fixture.plain,
    ...lzfseV1Fixture.plain,
  ]),
  () => lzfseStream([
    for (final fixture in [
      lzfseRawFixture,
      lzfseLzvnFixture,
      lzfseV2Fixture,
      lzfseV1Fixture,
    ])
      fixture.packed.sublist(0, fixture.packed.length - 4),
  ]),
);
final lzfseCrossBlockLzvnFixture = _reference(
  'cross_block_lzvn',
  () => Uint8List.fromList(ascii.encode('ABCABCABCABCA')),
);

/// A 32-byte v2 header reuses the last FSE tables, even across a stored block.
final lzfseReusedTablesFixture = LzfseFixture(
  'v2_reused_tables',
  () => Uint8List.fromList([
    ...lzfseV2Fixture.plain,
    ...ascii.encode('bridge'),
    ...lzfseV2Fixture.plain,
  ]),
  () {
    final first = lzfseV2Fixture.packed;
    final second = lzfseV2WithoutTables();
    return lzfseStream([
      first.sublist(0, first.length - 4),
      lzfseStoredBlock(ascii.encode('bridge')),
      second.sublist(0, second.length - 4),
    ]);
  },
);

/// Tables supplied in v1 form also survive an intervening LZVN block.
final lzfseV1ReusedTablesFixture = LzfseFixture(
  'v1_lzvn_reused_tables',
  () => Uint8List.fromList([
    ...lzfseV1Fixture.plain,
    ...lzfseLzvnFixture.plain,
    ...lzfseV2Fixture.plain,
  ]),
  () {
    final first = lzfseV1Fixture.packed;
    final bridge = lzfseLzvnFixture.packed;
    final second = lzfseV2WithoutTables();
    return lzfseStream([
      first.sublist(0, first.length - 4),
      bridge.sublist(0, bridge.length - 4),
      second.sublist(0, second.length - 4),
    ]);
  },
);

Uint8List lzfseV2WithoutTables() {
  final packed = lzfseV2Fixture.packed;
  final headerBytes = ByteData.sublistView(packed).getUint32(24, Endian.little);
  final result = Uint8List.fromList([
    ...packed.sublist(0, 32),
    ...packed.sublist(headerBytes),
  ]);
  ByteData.sublistView(result).setUint32(24, 32, Endian.little);
  return result;
}

final lzfseReferenceFixtures = <LzfseFixture>[
  lzfseEmptyFixture,
  lzfseRawFixture,
  lzfseLzvnFixture,
  lzfseV1Fixture,
  lzfseV2Fixture,
  lzfseV2ZeroFixture,
  lzfseDistanceFixture,
  lzfseMultiblockFixture,
  lzfseMixedFixture,
  lzfseCrossBlockLzvnFixture,
  lzfseReusedTablesFixture,
  lzfseV1ReusedTablesFixture,
];

/// Test-only framing helpers, independent of the production decoder.
Uint8List lzfseStoredBlock(List<int> plain) {
  final block = Uint8List(8 + plain.length);
  block.setAll(0, ascii.encode('bvx-'));
  ByteData.sublistView(block).setUint32(4, plain.length, Endian.little);
  block.setAll(8, plain);
  return block;
}

Uint8List lzfseLzvnBlock(List<int> payload, {required int rawBytes}) {
  final block = Uint8List(12 + payload.length);
  block.setAll(0, ascii.encode('bvxn'));
  final data = ByteData.sublistView(block);
  data.setUint32(4, rawBytes, Endian.little);
  data.setUint32(8, payload.length, Endian.little);
  block.setAll(12, payload);
  return block;
}

Uint8List lzfseStream(Iterable<List<int>> blocks) {
  final result = BytesBuilder(copy: false);
  for (final block in blocks) {
    result.add(block);
  }
  result.add(ascii.encode('bvx\$'));
  return result.takeBytes();
}

const lzfseLzvnEnd = <int>[6, 0, 0, 0, 0, 0, 0, 0];
