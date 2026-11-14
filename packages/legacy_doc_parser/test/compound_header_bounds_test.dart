// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:test/test.dart';

import 'support/compound_header_fixture.dart';

void main() {
  for (final variant in compoundInvalidGeometry) {
    test('raw header rejects invalid geometry ${variant.$1}', () {
      final bytes = compoundGeometryFixture(variant);
      expect(
        () => CfbfHeader.parse(MemoryByteSource(bytes)),
        throwsA(isA<CfbfException>()),
      );
    });
    test('raw file rejects invalid geometry ${variant.$1}', () {
      final bytes = compoundGeometryFixture(variant);
      expect(() => CfbfFile.fromBytes(bytes), throwsA(isA<CfbfException>()));
    });
    test('bounded file rejects invalid geometry ${variant.$1}', () {
      expect(
        () => BoundedCfbReader(compoundGeometryFixture(variant)),
        throwsFormatException,
      );
    });
  }
  for (final version4 in [false, true]) {
    for (final miniFat in [false, true]) {
      test(
        'metadata bound precedes source access: v4=$version4 mini=$miniFat',
        () {
          final source = _GuardedSource(
            compoundPhantomMetadataFixture(
              version4: version4,
              miniFat: miniFat,
            ),
          );
          expect(() => CfbfFile.open(source), throwsA(isA<CfbfException>()));
          expect(source.outsideAttempts, 0);
          expect(() => BoundedCfbReader(source.bytes), throwsFormatException);
        },
      );
    }
  }
}

class _GuardedSource extends MemoryByteSource {
  _GuardedSource(this.bytes) : super(bytes);
  final Uint8List bytes;
  var outsideAttempts = 0;

  @override
  Uint8List view(int offset, int count) {
    if (offset < 0 || count < 0 || offset > length - count) {
      outsideAttempts++;
    }
    return super.view(offset, count);
  }
}
