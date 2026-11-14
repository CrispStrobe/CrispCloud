// SDK-only acceptance driver for the real decoder and its browser-safe vectors.
// Run both VM and compiled JavaScript, without Flutter, plugins or native codecs:
//   dart test/support/lzfse_web_acceptance.dart
//   dart compile js -O2 test/support/lzfse_web_acceptance.dart -o /tmp/lzfse.js
//   node /tmp/lzfse.js
import 'dart:convert';
import 'dart:typed_data';

import '../../lib/services/archive_lzfse_codec.dart';
import '../../lib/services/archive_types.dart';
import 'lzfse_fixture.dart';
import 'lzfse_malformed_fixture.dart';

void _equal(List<int> actual, List<int> expected, String name) {
  if (actual.length != expected.length) {
    throw StateError(
      '$name: length ${actual.length}, expected ${expected.length}',
    );
  }
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i])
      throw StateError('$name: byte mismatch at $i');
  }
}

void _reject(String name, void Function() action) {
  try {
    action();
  } on ArchiveViewException {
    return;
  }
  throw StateError('$name: malformed stream was accepted');
}

void main() {
  var bytes = 0;
  for (final fixture in lzfseReferenceFixtures) {
    final expected = fixture.plain;
    final actual = decodeArchiveLzfse(
      fixture.packed,
      expectedBytes: expected.length,
    );
    _equal(actual, expected, fixture.name);
    bytes += actual.length;
  }

  final malformed = lzfseMalformedFixtures();
  for (final fixture in malformed) {
    _reject(fixture.name, () {
      decodeArchiveLzfse(fixture.packed, expectedBytes: fixture.expectedBytes);
    });
  }

  var truncations = 0;
  for (final fixture in [
    lzfseRawFixture,
    lzfseLzvnFixture,
    lzfseV1Fixture,
    lzfseV2Fixture,
  ]) {
    final packed = fixture.packed;
    final length = fixture.plain.length;
    for (var end = 0; end < packed.length; end++) {
      _reject('${fixture.name} prefix $end', () {
        decodeArchiveLzfse(
          Uint8List.sublistView(packed, 0, end),
          expectedBytes: length,
        );
      });
      truncations++;
    }
  }

  final packed = lzfseV2Fixture.packed;
  final backing = Uint8List(packed.length + 19)
    ..fillRange(0, packed.length + 19, 0xa5);
  backing.setAll(7, packed);
  final original = Uint8List.fromList(backing);
  final view = Uint8List.sublistView(backing, 7, 7 + packed.length);
  _equal(
    decodeArchiveLzfse(view, expectedBytes: 32768),
    lzfseV2Fixture.plain,
    'offset view',
  );
  _equal(backing, original, 'input preserved');

  final empty = lzfseStoredBlock([]);
  _equal(
    decodeArchiveLzfse(lzfseStream(List.filled(4096, empty)), expectedBytes: 0),
    [],
    'block budget boundary',
  );
  _reject('empty block budget exceeded', () {
    decodeArchiveLzfse(lzfseStream(List.filled(4097, empty)), expectedBytes: 0);
  });
  _reject('input ceiling', () {
    decodeArchiveLzfse(
      Uint8List(kArchiveLzfseChunkLimit + 1),
      expectedBytes: 0,
    );
  });
  for (final length in [-1, kArchiveLzfseChunkLimit + 1]) {
    _reject('output ceiling $length', () {
      decodeArchiveLzfse(Uint8List(0), expectedBytes: length);
    });
  }
  _reject('caller output ceiling', () {
    decodeArchiveLzfse(
      lzfseLzvnFixture.packed,
      expectedBytes: 1024,
      maxOutputBytes: 1023,
    );
  });
  for (final limit in [-1, 0, kArchiveLzfseChunkLimit + 1]) {
    var rejected = false;
    try {
      decodeArchiveLzfse(Uint8List(0), expectedBytes: 0, maxOutputBytes: limit);
    } on ArgumentError {
      rejected = true;
    }
    if (!rejected) throw StateError('invalid caller ceiling $limit accepted');
  }

  print(
    jsonEncode({
      'result': 'passed',
      'reference_fixtures': lzfseReferenceFixtures.length,
      'reference_output_bytes': bytes,
      'malformed_and_profile_cases': malformed.length,
      'truncated_prefixes': truncations,
      'offset_view_and_input_preservation': 'passed',
      'block_and_memory_budgets': 'passed',
    }),
  );
}
