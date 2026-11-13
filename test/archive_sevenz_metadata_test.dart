@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_sevenz_byte_reader.dart';
import 'package:crisp_cloud/services/archive_sevenz_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart';

SevenZFileInfo readTimestamp(DateTime value) {
  final time = ByteData(8)
    ..setUint64(
      0,
      (value.microsecondsSinceEpoch + 11644473600000000) * 10,
      Endian.little,
    );
  return SevenZFileInfo.read(
    ByteReader(
      Uint8List.fromList([
        1, // One file.
        SevenZId.mTime, 10, 1, 0, // Ten-byte inline, all-defined time property.
        ...time.buffer.asUint8List(),
        SevenZId.end,
      ]),
    ),
  );
}

void main() {
  test('native 7z timestamps retain every supported microsecond', () {
    final value = DateTime.utc(2026, 11, 13, 1, 2, 3, 456, 789);
    expect(readTimestamp(value).mTimes.single, value);
  });

  test('native 7z accepts the final microsecond of year 9999', () {
    final value = DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999);
    expect(readTimestamp(value).mTimes.single, value);
  });

  test('native 7z refuses the exclusive year-10000 boundary', () {
    expect(
      () => readTimestamp(DateTime.utc(10000)),
      throwsA(isA<UnsupportedFeatureException>()),
    );
  });
}
