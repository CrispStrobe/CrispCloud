import 'dart:typed_data';

import 'lzfse_fixture.dart';

/// Malformed streams and documented bounded-profile exclusions shared by the
/// unit suite and the compiled JavaScript acceptance runner.
class LzfseMalformedFixture {
  LzfseMalformedFixture(this.name, this.packed, this.expectedBytes);

  final String name;
  final Uint8List packed;
  final int expectedBytes;
}

List<LzfseMalformedFixture> lzfseMalformedFixtures() {
  final cases = <LzfseMalformedFixture>[];
  void add(String name, List<int> packed, int bytes) {
    cases.add(LzfseMalformedFixture(name, Uint8List.fromList(packed), bytes));
  }

  void v1(String name, void Function(Uint8List, ByteData) change) {
    final packed = lzfseV1Fixture.packed;
    change(packed, ByteData.sublistView(packed));
    add(name, packed, 32768);
  }

  void v2(String name, void Function(Uint8List, ByteData) change) {
    final packed = lzfseV2Fixture.packed;
    change(packed, ByteData.sublistView(packed));
    add(name, packed, 32768);
  }

  void lzvn(String name, List<int> payload, int rawBytes) {
    add(
      name,
      lzfseStream([lzfseLzvnBlock(payload, rawBytes: rawBytes)]),
      rawBytes,
    );
  }

  add('empty input has no stream end', [], 0);
  add('unknown block magic', [0, 0, 0, 0], 0);
  add(
    'v2 omitted tables before any prior FSE block',
    lzfseV2WithoutTables(),
    32768,
  );
  add('end marker before declared output', lzfseStream([]), 1);
  add('trailing byte after stream end', [...lzfseEmptyFixture.packed, 0], 0);
  add('repeated stream end', [
    ...lzfseEmptyFixture.packed,
    ...lzfseStream([]),
  ], 0);
  add('concatenated complete streams', [
    ...lzfseRawFixture.packed,
    ...lzfseRawFixture.packed,
  ], 14);
  for (final fixture in [
    lzfseRawFixture,
    lzfseLzvnFixture,
    lzfseV1Fixture,
    lzfseV2Fixture,
  ]) {
    final packed = fixture.packed;
    add(
      '${fixture.name} missing outer end',
      packed.sublist(0, packed.length - 4),
      fixture.plain.length,
    );
    add(
      '${fixture.name} short declared output',
      packed,
      fixture.plain.length - 1,
    );
    add(
      '${fixture.name} long declared output',
      packed,
      fixture.plain.length + 1,
    );
  }

  final oversizedRaw = lzfseRawFixture.packed;
  ByteData.sublistView(oversizedRaw).setUint32(4, 0xffffffff, Endian.little);
  add('unsigned raw length cannot wrap on JavaScript', oversizedRaw, 7);

  v1('v1 inconsistent payload sum', (_, d) => d.setUint32(8, 0, Endian.little));
  v1(
    'v1 excessive literal count',
    (_, d) => d.setUint32(12, 40004, Endian.little),
  );
  v1(
    'v1 unaligned literal count',
    (_, d) => d.setUint32(12, 259, Endian.little),
  );
  v1(
    'v1 excessive match count',
    (_, d) => d.setUint32(16, 10001, Endian.little),
  );
  v1(
    'v1 out-of-range literal state',
    (_, d) => d.setUint16(32, 1024, Endian.little),
  );
  v1('v1 out-of-range L state', (_, d) => d.setUint16(44, 64, Endian.little));
  v1('v1 out-of-range M state', (_, d) => d.setUint16(46, 64, Endian.little));
  v1('v1 out-of-range D state', (_, d) => d.setUint16(48, 256, Endian.little));
  v1(
    'v1 positive literal bit count',
    (_, d) => d.setInt32(28, 1, Endian.little),
  );
  v1(
    'v1 excessive literal padding',
    (_, d) => d.setInt32(28, -8, Endian.little),
  );
  v1('v1 positive LMD bit count', (_, d) => d.setInt32(40, 1, Endian.little));
  v1('v1 excessive LMD padding', (_, d) => d.setInt32(40, -8, Endian.little));
  v1('v1 empty frequency table', (p, _) => p.fillRange(50, 90, 0));
  v1(
    'v1 frequency sum too large',
    (_, d) => d.setUint16(50, 65535, Endian.little),
  );
  v1(
    'v1 frequency sum too small',
    (_, d) => d.setUint16(50, 60, Endian.little),
  );
  v1('v1 unsigned payload length cannot wrap', (_, d) {
    d.setUint32(8, 0xffffffff, Endian.little);
    d.setUint32(20, 0xffffffff, Endian.little);
    d.setUint32(24, 0, Endian.little);
  });
  v1('v1 truncated LMD minimum prefix', (_, d) {
    d.setUint32(24, 7, Endian.little);
    d.setUint32(8, d.getUint32(20, Endian.little) + 7, Endian.little);
  });
  v1('profile rejects nonzero LMD prefix', (p, d) {
    p[772 + d.getUint32(20, Endian.little)] = 1;
  });
  v1('profile rejects nonzero literal high-bit padding', (p, d) {
    p[772 + d.getUint32(20, Endian.little) - 1] |= 0x80;
  });
  v1('profile rejects nonzero LMD high-bit padding', (p, d) {
    p[772 + d.getUint32(8, Endian.little) - 1] |= 0x80;
  });
  for (final length in [0, 31, 753, 0xffffffff]) {
    v2(
      'v2 invalid header length $length',
      (_, d) => d.setUint32(24, length, Endian.little),
    );
  }
  v2(
    'v2 truncated compressed frequency table',
    (_, d) => d.setUint32(24, 33, Endian.little),
  );
  v2(
    'v2 zero frequency table',
    (p, d) => p.fillRange(32, d.getUint32(24, Endian.little), 0),
  );
  v2('v2 excessive literal count', (p, _) => _setBits(p, 8, 0, 20, 40004));
  v2('v2 excessive match count', (p, _) => _setBits(p, 8, 40, 20, 10001));
  v2(
    'v2 out-of-range L state across packed word',
    (p, _) => _setBits(p, 24, 32, 10, 64),
  );
  v2(
    'v2 out-of-range M state across packed word',
    (p, _) => _setBits(p, 24, 42, 10, 64),
  );
  v2(
    'v2 out-of-range D state across packed word',
    (p, _) => _setBits(p, 24, 52, 10, 256),
  );
  v2(
    'v2 unsigned output length cannot wrap',
    (_, d) => d.setUint32(4, 0xffffffff, Endian.little),
  );

  lzvn('LZVN missing inner end', [], 0);
  lzvn('LZVN truncated inner end', [6, 0], 0);
  lzvn('LZVN early inner end', lzfseLzvnEnd, 1);
  lzvn('LZVN trailing payload after inner end', [...lzfseLzvnEnd, 0], 0);
  lzvn('profile rejects nonzero LZVN end padding', [6, 1, 0, 0, 0, 0, 0, 0], 0);
  lzvn('LZVN missing small-distance operand', [0], 3);
  lzvn('LZVN missing medium-distance operand', [0xa0, 1], 3);
  lzvn('LZVN missing large-distance operand', [7, 1], 3);
  lzvn('LZVN missing extended literal length', [0xe0], 16);
  lzvn('LZVN missing extended match length', [0xf0], 16);
  lzvn('LZVN truncated literal bytes', [0xe2, 1], 2);
  lzvn('LZVN zero match distance', [0, 0, ...lzfseLzvnEnd], 3);
  lzvn('LZVN match before history', [0, 1, ...lzfseLzvnEnd], 3);
  lzvn('LZVN previous distance before first match', [0xf3, ...lzfseLzvnEnd], 3);
  lzvn('LZVN literal exceeds output', [0xe2, 1, 2, ...lzfseLzvnEnd], 1);
  lzvn('LZVN overlapping match exceeds output', [
    0xe1,
    42,
    0x38,
    1,
    ...lzfseLzvnEnd,
  ], 10);
  for (final opcode in [0x1e, 0x70, 0x7f, 0xd0, 0xdf]) {
    lzvn('LZVN undefined opcode $opcode', [opcode, ...lzfseLzvnEnd], 0);
  }
  add(
    'LZVN resets previous distance at a block boundary',
    lzfseStream([
      lzfseLzvnBlock([0xe1, 65, 0, 1, ...lzfseLzvnEnd], rawBytes: 4),
      lzfseLzvnBlock([0xf3, ...lzfseLzvnEnd], rawBytes: 3),
    ]),
    7,
  );
  add(
    'LZVN history cannot precede the entire stream',
    lzfseStream([
      lzfseStoredBlock([65, 66, 67]),
      lzfseLzvnBlock([0, 4, ...lzfseLzvnEnd], rawBytes: 3),
    ]),
    6,
  );
  final multi = lzfseMultiblockFixture.packed;
  add(
    'compressed second block requires preceding history',
    multi.sublist(40079),
    60310,
  );
  return cases;
}

void _setBits(Uint8List data, int base, int firstBit, int count, int value) {
  // Independent little-endian field mutation; never forms a 64-bit JS int.
  for (var i = 0; i < count; i++) {
    final bit = firstBit + i;
    final index = base + bit ~/ 8;
    final mask = 1 << (bit % 8);
    data[index] = (data[index] & ~mask) | (((value >> i) & 1) * mask);
  }
}
