import 'dart:typed_data';

import 'package:crisp_cloud/services/document_preview_source.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source extends ViewBytesSource {
  _Source(this.data, {int? reportedSize}) : super.memory(Uint8List(0)) {
    size = reportedSize ?? data.length;
  }
  final Uint8List data;
  int reads = 0;
  int validations = 0;
  bool shortRead = false;
  void Function(int)? onRead;
  void Function(int)? onValidate;
  @override
  Future<void> validateUnchanged() async {
    validations++;
    onValidate?.call(validations);
  }

  @override
  Uint8List readSync(int offset, int length) {
    reads++;
    onRead?.call(reads);
    return Uint8List.sublistView(
      data,
      offset,
      offset + length - (shortRead ? 1 : 0),
    );
  }
}

Matcher _fails(DocumentSourceError code) => throwsA(
  isA<DocumentSourceException>().having((error) => error.code, 'code', code),
);

void main() {
  test('copies complete windows and owns the snapshot', () async {
    final data = Uint8List(600000)..[599999] = 42;
    final source = _Source(data);
    final snapshot = await readDocumentPreviewSource(
      source,
      maxBytes: data.length,
    );
    expect(source.reads, 3);
    expect(source.validations, 2);
    expect(snapshot.last, 42);
    data[599999] = 7;
    expect(snapshot.last, 42);
  });
  test('rejects size before source validation or allocation', () async {
    final source = _Source(Uint8List(0), reportedSize: 5 * 1024 * 1024 * 1024);
    await expectLater(
      readDocumentPreviewSource(source, maxBytes: 64 * 1024 * 1024),
      _fails(DocumentSourceError.readLimit),
    );
    expect(source.reads, 0);
    expect(source.validations, 0);
  });
  test('never returns a short source as a complete document', () async {
    final source = _Source(Uint8List(12))..shortRead = true;
    await expectLater(
      readDocumentPreviewSource(source, maxBytes: 12),
      _fails(DocumentSourceError.readFailed),
    );
  });
  test('cancels stale viewer generation between bounded windows', () async {
    var current = true;
    final source = _Source(Uint8List(600000))..onRead = (_) => current = false;
    await expectLater(
      readDocumentPreviewSource(
        source,
        maxBytes: 600000,
        isCurrent: () => current,
      ),
      _fails(DocumentSourceError.sourceChanged),
    );
    expect(source.reads, 1);
  });
  test('rejects a source changed after the complete read', () async {
    final source = _Source(Uint8List(4))
      ..onValidate = (call) {
        if (call == 2) throw StateError('changed');
      };
    await expectLater(
      readDocumentPreviewSource(source, maxBytes: 4),
      _fails(DocumentSourceError.sourceChanged),
    );
  });
  test('accepts an empty complete snapshot without I/O', () async {
    final source = _Source(Uint8List(0));
    expect(await readDocumentPreviewSource(source, maxBytes: 4), isEmpty);
    expect(source.reads, 0);
    expect(source.validations, 2);
  });
}
