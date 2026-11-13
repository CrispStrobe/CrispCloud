import 'dart:typed_data';

import '../lib/services/binary_structure_service.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Iterable<BinaryStructureField> flatten(
  List<BinaryStructureField> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* flatten(field.children);
  }
}

void main() {
  for (final little in [true, false]) {
    final backing = Uint8List(80);
    final bytes = Uint8List.sublistView(backing, 9, 73);
    bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, little ? 1 : 2]);
    final exact = [0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10];
    bytes.setAll(24, little ? exact.reversed : exact);
    final analysis = inspectBinaryStructure(bytes, totalBytes: bytes.length);
    check(analysis.format == BinaryStructureFormat.elf, 'ELF detection');
    final entry = flatten(analysis.fields)
        .singleWhere((f) => f.name == 'Entry point');
    check(entry.value == '0xFEDCBA9876543210', 'exact uint64 decoding');
    bytes.fillRange(24, 32, 0xff);
    final maximum = inspectBinaryStructure(bytes, totalBytes: bytes.length);
    check(
      flatten(maximum.fields)
              .singleWhere((f) => f.name == 'Entry point')
              .value ==
          '0xFFFFFFFFFFFFFFFF',
      'unsigned64 maximum',
    );
    for (var size = 0; size < bytes.length; size++) {
      final sliced = Uint8List.sublistView(bytes, 0, size);
      final partial = inspectBinaryStructure(sliced, totalBytes: size);
      for (final field in flatten(partial.fields)) {
        check(
          field.start >= 0 && field.end <= size && field.start < field.end,
          'bounded partial field',
        );
      }
    }
  }
  final pe = Uint8List(64)..setAll(0, [0x4d, 0x5a]);
  pe.fillRange(60, 64, 0xff);
  final result = inspectBinaryStructure(pe, totalBytes: 64);
  check(
    result.issues.contains(BinaryStructureIssue.invalidHeader),
    'oversized PE offset',
  );
  check(
    result.issues.contains(BinaryStructureIssue.truncated),
    'out of file PE offset',
  );
  print(
    'Binary header portability checks passed: exact uint64, typed-data offsets, truncation and hostile PE pointer.',
  );
}
