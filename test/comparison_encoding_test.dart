import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/file_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

void main() {
  for (final encoding in [
    EditorEncoding.utf16le,
    EditorEncoding.utf16be,
    EditorEncoding.utf32le,
    EditorEncoding.utf32be,
  ]) {
    test(
      'explicit ${encoding.label} preserves BOM-less bytes and newlines',
      () {
        final original = EditorDocument(
          text: 'café 😀\nlast\n',
          encoding: encoding,
          lineEnding: EditorLineEnding.crlf,
          writeBom: false,
        );
        final bytes = original.encode();
        final decoded = EditorDocument.decode(
          bytes,
          encodingOverride: encoding,
        );
        expect(decoded.text, original.text);
        expect(decoded.hadBom, isFalse);
        expect(decoded.lineEnding, EditorLineEnding.crlf);
        expect(decoded.encode(), bytes);
      },
    );
  }

  test(
    'explicit UTF-8 rejects malformed input rather than choosing another encoding',
    () {
      expect(
        () => EditorDocument.decode([
          0xE9,
        ], encodingOverride: EditorEncoding.utf8),
        throwsA(isA<EditorEncodingException>()),
      );
      expect(
        EditorDocument.decode([
          0xE9,
        ], encodingOverride: EditorEncoding.latin1).text,
        'é',
      );
    },
  );

  test(
    'malformed Unicode units cannot be silently dropped by editable comparison',
    () {
      for (final bytes in <List<int>>[
        [0xFF, 0xFE, 1],
        [0xFF, 0xFE, 0, 0xD8],
        [0xFF, 0xFE, 0, 0, 1],
        [0, 0, 0xFE, 0xFF, 0, 0x11, 0, 0],
        [0xEF, 0xBB, 0xBF, 0xE9],
      ]) {
        expect(
          () => EditorDocument.decode(bytes),
          throwsA(isA<EditorEncodingException>()),
        );
      }
    },
  );

  test(
    'an explicit right encoding is retained across repeated verified merge saves',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'merge-encoding-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/utf16.txt');
      const document = EditorDocument(
        text: 'old\n',
        encoding: EditorEncoding.utf16be,
        lineEnding: EditorLineEnding.crlf,
        writeBom: false,
      );
      await file.writeAsBytes(document.encode());
      final source = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      final session = await MergeDocumentSession.open(
        source,
        (await source.stat(file.path))!,
        encodingOverride: EditorEncoding.utf16be,
      );
      await session.save('merged\n');
      expect(await file.readAsBytes(), document.encode('merged\n'));
      await session.save('second longer save\n');
      expect(await file.readAsBytes(), document.encode('second longer save\n'));
    },
  );

  for (final encoding in [EditorEncoding.cp437, EditorEncoding.windows1252]) {
    test(
      '${encoding.label} comparison saves retain encoding and reject unrepresentable merges',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'legacy-merge-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/text.txt');
        final document = EditorDocument(
          text: 'café\n',
          encoding: encoding,
          lineEnding: EditorLineEnding.crlf,
        );
        final original = document.encode();
        await file.writeAsBytes(original);
        final source = LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => true,
        );
        final session = await MergeDocumentSession.open(
          source,
          (await source.stat(file.path))!,
          encodingOverride: encoding,
        );
        await expectLater(
          session.save('東京\n'),
          throwsA(isA<EditorEncodingException>()),
        );
        expect(await file.readAsBytes(), original);
        await session.save('café edited\n');
        expect(await file.readAsBytes(), document.encode('café edited\n'));
      },
    );
  }
}
