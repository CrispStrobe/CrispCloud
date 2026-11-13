import 'dart:typed_data';

import 'package:crisp_cloud/services/binary_structure_service.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<BinaryStructureField> _flatten(
  List<BinaryStructureField> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* _flatten(field.children);
  }
}

BinaryStructureField _field(BinaryStructureAnalysis result, String name) =>
    _flatten(result.fields).singleWhere((field) => field.name == name);

void _expectPresentRanges(BinaryStructureAnalysis result) {
  void check(List<BinaryStructureField> fields, int start, int end) {
    for (final field in fields) {
      expect(field.start, greaterThanOrEqualTo(start), reason: field.name);
      expect(field.end, greaterThan(field.start), reason: field.name);
      expect(field.end, lessThanOrEqualTo(end), reason: field.name);
      check(field.children, field.start, field.end);
    }
  }

  check(result.fields, 0, result.inspectedBytes);
  expect(_flatten(result.fields).length, lessThanOrEqualTo(24));
}

Uint8List _png() {
  final bytes = Uint8List(33)
    ..setAll(0, [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])
    ..setAll(12, 'IHDR'.codeUnits);
  ByteData.sublistView(bytes)
    ..setUint32(8, 13)
    ..setUint32(16, 640)
    ..setUint32(20, 480);
  bytes[24] = 8;
  bytes[25] = 6;
  return bytes;
}

Uint8List _elf({bool is64 = true, Endian endian = Endian.little}) {
  final bytes = Uint8List(is64 ? 64 : 52)
    ..setAll(0, [
      0x7f,
      0x45,
      0x4c,
      0x46,
      is64 ? 2 : 1,
      endian == Endian.little ? 1 : 2,
      1,
    ]);
  final view = ByteData.sublistView(bytes)
    ..setUint16(16, 2, endian)
    ..setUint16(18, 0x3e, endian);
  if (is64) {
    _set64(view, 24, 0x12345678, 0x9abcdef0, endian);
  } else {
    view.setUint32(24, 0xfedcba98, endian);
  }
  return bytes;
}

void _set64(ByteData view, int offset, int high, int low, Endian endian) {
  view.setUint32(offset + (endian == Endian.little ? 4 : 0), high, endian);
  view.setUint32(offset + (endian == Endian.little ? 0 : 4), low, endian);
}

Uint8List _pe({int optionalSize = 2}) {
  final bytes = Uint8List(128)..setAll(0, [0x4d, 0x5a]);
  bytes.setAll(64, [0x50, 0x45, 0, 0]);
  ByteData.sublistView(bytes)
    ..setUint32(0x3c, 64, Endian.little)
    ..setUint16(68, 0x8664, Endian.little)
    ..setUint16(70, 3, Endian.little)
    ..setUint16(84, optionalSize, Endian.little)
    ..setUint16(88, 0x20b, Endian.little);
  return bytes;
}

Uint8List _machO({bool is64 = true, Endian endian = Endian.big}) {
  final bytes = Uint8List(is64 ? 32 : 28);
  ByteData.sublistView(bytes)
    ..setUint32(0, is64 ? 0xfeedfacf : 0xfeedface, endian)
    ..setUint32(4, 0x01000007, endian)
    ..setUint32(8, 3, endian)
    ..setUint32(12, 2, endian);
  return bytes;
}

Uint8List _zip() {
  final bytes = Uint8List(34)..setAll(0, [0x50, 0x4b, 3, 4]);
  ByteData.sublistView(bytes)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 8, Endian.little)
    ..setUint16(8, 8, Endian.little)
    ..setUint32(18, 12, Endian.little)
    ..setUint16(26, 4, Endian.little);
  return bytes;
}

Uint8List _java() =>
    Uint8List.fromList([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 61, 0, 2]);

Uint8List _fat({bool is64 = false, Endian endian = Endian.big}) {
  final bytes = Uint8List(is64 ? 44 : 36);
  final view = ByteData.sublistView(bytes)
    ..setUint32(0, is64 ? 0xcafebabf : 0xcafebabe, endian)
    ..setUint32(4, 1, endian)
    ..setUint32(8, 0x0100000c, endian);
  if (is64) {
    _set64(view, 16, 0, 40, endian);
    _set64(view, 24, 0, 4, endian);
  } else {
    view
      ..setUint32(16, 32, endian)
      ..setUint32(20, 4, endian);
  }
  return bytes;
}

void main() {
  BinaryStructureAnalysis inspect(Uint8List bytes, {int? total}) =>
      inspectBinaryStructure(bytes, totalBytes: total ?? bytes.length);

  test('inspects PNG fields without interpreting image data or CRC', () {
    final result = inspect(_png());
    expect(result.format, BinaryStructureFormat.png);
    expect(_field(result, 'Width').value, '640');
    expect(_field(result, 'Height').value, '480');
    expect(_field(result, 'Width').start, 16);
    expect(_field(result, 'Width').end, 20);
    expect(result.issues, isEmpty);
    _expectPresentRanges(result);
  });

  test(
    'rejects malformed first PNG chunk values without following lengths',
    () {
      final bytes = _png();
      ByteData.sublistView(bytes).setUint32(8, 0xffffffff);
      final result = inspect(bytes);
      expect(result.issues, contains(BinaryStructureIssue.invalidHeader));
      expect(
        _flatten(result.fields).any((field) => field.name == 'Width'),
        isFalse,
      );
      _expectPresentRanges(result);
    },
  );

  test('inspects WASM version and discloses an unsupported version', () {
    final bytes = Uint8List.fromList([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
    expect(inspect(bytes).format, BinaryStructureFormat.wasm);
    expect(_field(inspect(bytes), 'Version').value, '1');
    bytes[4] = 2;
    expect(inspect(bytes).issues, contains(BinaryStructureIssue.invalidHeader));
  });

  for (final endian in [Endian.big, Endian.little]) {
    for (final is64 in [false, true]) {
      test('ELF ${is64 ? 64 : 32} ${endian == Endian.big ? 'BE' : 'LE'}', () {
        final result = inspect(_elf(is64: is64, endian: endian));
        expect(result.format, BinaryStructureFormat.elf);
        expect(_field(result, 'Machine').value, '0x3E');
        expect(
          _field(result, 'Entry point').value,
          is64 ? '0x123456789ABCDEF0' : '0xFEDCBA98',
        );
        expect(result.issues, isEmpty);
        _expectPresentRanges(result);
      });

      test(
        'Mach-O ${is64 ? 64 : 32} ${endian == Endian.big ? 'BE' : 'LE'}',
        () {
          final result = inspect(_machO(is64: is64, endian: endian));
          expect(result.format, BinaryStructureFormat.machO);
          expect(_field(result, 'CPU type').value, '0x1000007');
          expect(_field(result, 'File type').value, '0x2');
          expect(result.issues, isEmpty);
          _expectPresentRanges(result);
        },
      );

      test(
        'fat Mach-O ${is64 ? 64 : 32} ${endian == Endian.big ? 'BE' : 'LE'}',
        () {
          final result = inspect(_fat(is64: is64, endian: endian));
          expect(result.format, BinaryStructureFormat.machOFat);
          expect(_field(result, 'Architecture count').value, '1');
          expect(_field(result, 'Slice offset').value, is64 ? '0x28' : '0x20');
          expect(result.issues, isEmpty);
          _expectPresentRanges(result);
        },
      );
    }

    test('keeps all 64 bits exact (${endian == Endian.big ? 'BE' : 'LE'})', () {
      final bytes = _elf(endian: endian);
      _set64(ByteData.sublistView(bytes), 24, 0xffffffff, 0xffffffff, endian);
      expect(_field(inspect(bytes), 'Entry point').value, '0xFFFFFFFFFFFFFFFF');
    });
  }

  test('does not invent an ELF byte order or class for malformed headers', () {
    for (final offset in [4, 5]) {
      final bytes = _elf()..[offset] = 0;
      final result = inspect(bytes);
      expect(result.issues, contains(BinaryStructureIssue.invalidHeader));
      expect(
        _flatten(result.fields).any((f) => f.name == 'Entry point'),
        isFalse,
      );
      _expectPresentRanges(result);
    }
  });

  test('inspects PE signature and bounded optional header', () {
    final result = inspect(_pe());
    expect(result.format, BinaryStructureFormat.pe);
    expect(_field(result, 'Machine').value, '0x8664');
    expect(_field(result, 'Number of sections').value, '3');
    expect(_field(result, 'Optional header magic').value, '0x20B');
    expect(result.issues, isEmpty);
    _expectPresentRanges(result);
  });

  test('never reads optional-header magic beyond its declared size', () {
    for (final size in [0, 1]) {
      final result = inspect(_pe(optionalSize: size));
      expect(
        _flatten(result.fields).any((f) => f.name == 'Optional header magic'),
        isFalse,
      );
      if (size == 1) {
        expect(result.issues, contains(BinaryStructureIssue.invalidHeader));
      }
    }
  });

  test(
    'discloses PE pointer outside file without exposing a phantom field',
    () {
      final bytes = Uint8List(64)..setAll(0, [0x4d, 0x5a]);
      ByteData.sublistView(bytes).setUint32(0x3c, 0xffffffff, Endian.little);
      final result = inspect(bytes);
      expect(
        result.issues,
        containsAll([
          BinaryStructureIssue.invalidHeader,
          BinaryStructureIssue.truncated,
        ]),
      );
      expect(result.fields.length, 2);
      _expectPresentRanges(result);
    },
  );

  test(
    'a PE header outside the prefix is uninspected, not a truncated file',
    () {
      final bytes = Uint8List(binaryStructurePrefixBytes)
        ..setAll(0, [0x4d, 0x5a]);
      ByteData.sublistView(bytes)
          .setUint32(0x3c, binaryStructurePrefixBytes + 8, Endian.little);
      final result = inspect(bytes, total: binaryStructurePrefixBytes + 1024);
      expect(result.issues, [BinaryStructureIssue.prefixLimit]);
      expect(result.fields.length, 2);
      _expectPresentRanges(result);
    },
  );

  test('inspects ZIP local metadata without extracting entries', () {
    final result = inspect(_zip());
    expect(result.format, BinaryStructureFormat.zip);
    expect(_field(result, 'Compression').value, '8');
    expect(_field(result, 'Filename length').value, '4');
    expect(result.issues, isEmpty);
    _expectPresentRanges(result);
    for (final marker in [5, 7]) {
      final other = Uint8List(marker == 5 ? 22 : 16)
        ..setAll(0, [0x50, 0x4b, marker, marker == 5 ? 6 : 8]);
      expect(inspect(other).format, BinaryStructureFormat.zip);
      expect(inspect(other).fields.length, 1);
    }
  });

  test(
    'inspects Java class only with compatible version and pool evidence',
    () {
      final result = inspect(_java());
      expect(result.format, BinaryStructureFormat.javaClass);
      expect(_field(result, 'Major version').value, '61');
      expect(_field(result, 'Constant pool count').value, '2');
      expect(result.issues, isEmpty);
      _expectPresentRanges(result);
      for (final bytes in [
        Uint8List.fromList([0xca, 0xfe, 0xba, 0xbe]),
        _java()..[7] = 0,
        _java()..[9] = 0,
      ]) {
        final ambiguous = inspect(bytes);
        expect(ambiguous.format, BinaryStructureFormat.raw);
        expect(ambiguous.issues, contains(BinaryStructureIssue.ambiguousMagic));
      }
    },
  );

  test(
    'retains ambiguity if both Java and fat Mach-O headers are plausible',
    () {
      final bytes = Uint8List(28);
      ByteData.sublistView(bytes)
        ..setUint32(0, 0xcafebabe)
        ..setUint32(4, 61)
        ..setUint32(8, 0x0100000c)
        ..setUint32(16, 1300)
        ..setUint32(20, 4);
      final result = inspect(bytes, total: 1400);
      expect(result.format, BinaryStructureFormat.raw);
      expect(result.issues, contains(BinaryStructureIssue.ambiguousMagic));
      _expectPresentRanges(result);
    },
  );

  test('large input counts and lengths never expand the header tree', () {
    final fat = _fat(is64: true);
    ByteData.sublistView(fat).setUint32(4, 0xffffffff);
    final fatResult = inspect(fat);
    expect(fatResult.issues, contains(BinaryStructureIssue.truncated));
    expect(_flatten(fatResult.fields).length, lessThan(12));
    final zip = _zip();
    ByteData.sublistView(zip)
      ..setUint16(26, 65535, Endian.little)
      ..setUint16(28, 65535, Endian.little);
    expect(inspect(zip).issues, contains(BinaryStructureIssue.truncated));
    _expectPresentRanges(inspect(zip));
    _expectPresentRanges(fatResult);
  });

  test('missing fat architecture evidence keeps a short prefix ambiguous', () {
    final bytes = _java();
    final result = inspect(bytes, total: 1400);
    expect(result.format, BinaryStructureFormat.raw);
    expect(
      result.issues,
      containsAll([
        BinaryStructureIssue.ambiguousMagic,
        BinaryStructureIssue.prefixLimit,
      ]),
    );
    expect(result.issues, isNot(contains(BinaryStructureIssue.truncated)));
    expect(result.fields.length, 1);
    _expectPresentRanges(result);
  });

  test(
    'unfamiliar CPU code cannot make a plausible fat header become Java',
    () {
      final bytes = Uint8List(28);
      ByteData.sublistView(bytes)
        ..setUint32(0, 0xcafebabe)
        ..setUint32(4, 61)
        ..setUint32(8, 0x01000004)
        ..setUint32(16, 1300)
        ..setUint32(20, 4);
      final result = inspect(bytes, total: 1400);
      expect(result.format, BinaryStructureFormat.raw);
      expect(result.issues, contains(BinaryStructureIssue.ambiguousMagic));
      _expectPresentRanges(result);
    },
  );

  test(
    'inspects every truncated header prefix without unsafe ranges or reads',
    () {
      final fixtures = [
        _png(),
        _elf(),
        _pe(),
        _machO(),
        _zip(),
        _java(),
        _fat(),
        _fat(is64: true),
        Uint8List.fromList([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]),
      ];
      for (final fixture in fixtures) {
        for (var length = 0; length <= fixture.length; length++) {
          final result = inspect(Uint8List.sublistView(fixture, 0, length));
          _expectPresentRanges(result);
        }
      }
    },
  );

  test('distinguishes a truncated file from a partial prefix', () {
    final prefix = Uint8List.sublistView(_elf(), 0, 28);
    final partial = inspect(prefix, total: 64);
    final truncated = inspect(prefix);
    expect(partial.issues, [BinaryStructureIssue.prefixLimit]);
    expect(truncated.issues, [BinaryStructureIssue.truncated]);
    expect(
      _flatten(partial.fields).any((f) => f.name == 'Entry point'),
      isFalse,
    );
    _expectPresentRanges(partial);
    _expectPresentRanges(truncated);
  });

  test(
    'honors a nonzero typed-data view offset and does not retain byte data',
    () {
      final fixture = _elf();
      final backing = Uint8List(fixture.length + 123)..setAll(123, fixture);
      final prefix = Uint8List.sublistView(backing, 123);
      final result = inspect(prefix);
      expect(_field(result, 'Entry point').value, '0x123456789ABCDEF0');
      prefix.fillRange(0, prefix.length, 0);
      expect(_field(result, 'Entry point').value, '0x123456789ABCDEF0');
    },
  );

  test('rejects inconsistent and oversized inputs before header access', () {
    expect(
      () => inspectBinaryStructure(Uint8List(2), totalBytes: 1),
      throwsArgumentError,
    );
    expect(
      () => inspectBinaryStructure(Uint8List(0), totalBytes: -1),
      throwsArgumentError,
    );
    expect(
      () => inspect(Uint8List(binaryStructurePrefixBytes + 1)),
      throwsArgumentError,
    );
  });

  test('unknown and empty files remain raw without invented fields', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([0x52, 0x41, 0x57]),
    ]) {
      final result = inspect(bytes);
      expect(result.format, BinaryStructureFormat.raw);
      expect(result.fields, isEmpty);
      expect(result.issues, isEmpty);
      expect(result.inspectedBytes, bytes.length);
      expect(result.byteLength, bytes.length);
    }
    final sampled = inspect(Uint8List(0), total: 100);
    expect(sampled.byteLength, 100);
    expect(sampled.issues, [BinaryStructureIssue.prefixLimit]);
  });

  test('returned field, child and issue lists are immutable', () {
    final result = inspect(_png());
    expect(() => result.fields.clear(), throwsUnsupportedError);
    expect(
      () => _field(result, 'IHDR').children.clear(),
      throwsUnsupportedError,
    );
    expect(() => result.issues.clear(), throwsUnsupportedError);
  });
}
