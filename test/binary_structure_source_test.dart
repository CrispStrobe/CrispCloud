import 'dart:typed_data';

import 'package:crisp_cloud/services/binary_structure_service.dart';
import 'package:crisp_cloud/services/binary_structure_source.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSource extends ViewBytesSource {
  _RecordingSource({required int length, this.changeAt, this.shortRead = false})
    : super.memory(Uint8List(0)) {
    size = length;
  }

  final int? changeAt;
  final bool shortRead;
  int validations = 0;
  final reads = <(int, int)>[];

  @override
  Future<void> validateUnchanged() async {
    if (++validations == changeAt) throw StateError('source changed');
  }

  @override
  Uint8List readSync(int offset, int length) {
    reads.add((offset, length));
    if (shortRead) return Uint8List(0);
    final data = Uint8List(length);
    if (length >= 8) data.setAll(0, [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
    return data;
  }
}

void main() {
  test('multi-gigabyte input uses one bounded prefix read', () async {
    final source = _RecordingSource(length: 5 * 1024 * 1024 * 1024);
    final result = await inspectBinaryStructureSource(source);
    expect(source.reads, [(0, binaryStructurePrefixBytes)]);
    expect(source.validations, 2);
    expect(result.inspectedBytes, binaryStructurePrefixBytes);
    expect(result.byteLength, source.size);
    expect(result.format, BinaryStructureFormat.wasm);
    expect(result.issues, contains(BinaryStructureIssue.prefixLimit));
  });

  test('small source reads only its actual length', () async {
    final source = _RecordingSource(length: 8);
    final result = await inspectBinaryStructureSource(source);
    expect(source.reads, [(0, 8)]);
    expect(result.inspectedBytes, 8);
    expect(result.issues, isEmpty);
  });

  test('changed source is rejected before any read', () async {
    final source = _RecordingSource(length: 8, changeAt: 1);
    await expectLater(inspectBinaryStructureSource(source), throwsStateError);
    expect(source.reads, isEmpty);
  });

  test('change during the read prevents publishing an analysis', () async {
    final source = _RecordingSource(length: 8, changeAt: 2);
    await expectLater(inspectBinaryStructureSource(source), throwsStateError);
    expect(source.reads, [(0, 8)]);
    expect(source.validations, 2);
  });

  test('short read is reported as a read failure', () async {
    final source = _RecordingSource(length: 8, shortRead: true);
    await expectLater(inspectBinaryStructureSource(source), throwsStateError);
  });

  test('closed source cannot be inspected', () async {
    final source = ViewBytesSource.memory(Uint8List(8));
    await source.open();
    source.dispose();
    await expectLater(inspectBinaryStructureSource(source), throwsStateError);
  });
}
