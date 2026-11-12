import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/viewer_spool.dart';
import 'package:crisp_cloud/services/viewer_tail_service.dart';

import 'support/workflow_fake_client.dart';

void main() {
  late Directory temporary;
  late File file;
  late LocalOperationBackend local;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('viewer-stream-test-');
    file = File('${temporary.path}/log.txt');
    local = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'tail is bounded and follows append, truncation and a missing file',
    () async {
      await file.writeAsString('0123456789');
      final tail = ViewerTailService(
        local,
        (await local.stat(file.path))!,
        windowBytes: 4,
      );
      var sample = await tail.read();
      expect(utf8.decode(sample.bytes), '6789');
      expect(sample.offset, 6);
      expect(sample.totalBytes, 10);
      await file.writeAsString('AB', mode: FileMode.append);
      sample = await tail.read();
      expect(utf8.decode(sample.bytes), '89AB');
      expect(sample.replacedOrTruncated, false);
      await file.writeAsString('new');
      sample = await tail.read();
      expect(utf8.decode(sample.bytes), 'new');
      expect(sample.replacedOrTruncated, true);
      await file.delete();
      await expectLater(tail.read(), throwsStateError);
    },
  );

  test('tail aligns multibyte encodings and allows small windows', () async {
    await file.writeAsString('aaaébbb');
    final tail = ViewerTailService(
      local,
      (await local.stat(file.path))!,
      windowBytes: 4,
    );
    final sample = await tail.read();
    expect(utf8.decode(sample.bytes), 'bbb');
    await file.writeAsBytes([0xff, 0xfe, 65, 0, 66, 0, 67, 0]);
    final utf16 = await tail.read();
    expect(utf16.encoding, 'utf16le');
    expect(
      InternalViewerService.decodeTextForView(
        utf16.bytes,
        encoding: utf16.encoding,
      ).text,
      'BC',
    );
    final tiny = ViewerTailService(
      local,
      (await local.stat(file.path))!,
      windowBytes: 1,
    );
    expect((await tiny.read()).bytes, isEmpty);
    await file.writeAsBytes([0xff, 0xfe, 0, 0, 0x41, 0, 0, 0, 0x42, 0, 0, 0]);
    final utf32 = await tail.read();
    expect(utf32.encoding, 'utf32le');
    expect(
      InternalViewerService.decodeTextForView(
        utf32.bytes,
        encoding: utf32.encoding,
      ).text,
      'B',
    );
    expect(
      InternalViewerService.decodeTextForView(
        Uint8List.fromList(await file.readAsBytes()),
      ).text,
      'AB',
    );
  });

  test('explicit legacy tail windows retain leading high bytes', () async {
    await file.writeAsBytes([65, 66, 0x82, 0x93, 0x80, 0x97]);
    final tail = ViewerTailService(
      local,
      (await local.stat(file.path))!,
      windowBytes: 4,
    );
    for (final encoding in ['cp437', 'windows1252']) {
      final window = await tail.read(encodingOverride: encoding);
      expect(window.offset, 2);
      expect(window.bytes, [0x82, 0x93, 0x80, 0x97]);
      expect(window.encoding, encoding);
    }
  });

  test(
    'tail refuses repeated full downloads and stale captured accounts',
    () async {
      final client = WorkflowFakeClient()
        ..put('/log.txt', '0123456789'.codeUnits);
      var current = true;
      final backend = CloudOperationBackend(client, isCurrent: () => current);
      final item = (await backend.stat('/log.txt'))!;
      final tail = ViewerTailService(backend, item, windowBytes: 4);
      await expectLater(tail.read(), throwsUnsupportedError);
      current = false;
      await expectLater(tail.read(), throwsStateError);
    },
  );

  test('remote spooling streams bytes and releases its owned file', () async {
    final client = WorkflowFakeClient()
      ..put('/log.txt', 'hello streamed'.codeUnits);
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final counts = <int>[];
    final spool = await createViewerSpool(
      backend,
      (await backend.stat('/log.txt'))!,
      onProgress: (bytes, _) => counts.add(bytes),
    );
    expect(await File(spool.path).readAsString(), 'hello streamed');
    expect(counts.length, greaterThan(1));
    expect(counts.last, 14);
    expect(spool.path, endsWith('.txt'));
    await spool.close();
    await spool.close();
    expect(File(spool.path).existsSync(), false);
  });

  test(
    'spooling rejects size overflow, cancellation, source loss and changed versions',
    () async {
      final client = WorkflowFakeClient()..put('/log.txt', 'abcdef'.codeUnits);
      var current = true;
      final backend = CloudOperationBackend(client, isCurrent: () => current);
      final item = (await backend.stat('/log.txt'))!;
      await expectLater(
        createViewerSpool(backend, item, maxBytes: 3),
        throwsStateError,
      );
      var cancelled = false;
      await expectLater(
        createViewerSpool(
          backend,
          item,
          isCancelled: () => cancelled,
          onProgress: (_, _) => cancelled = true,
        ),
        throwsStateError,
      );
      await expectLater(
        createViewerSpool(backend, item, onProgress: (_, _) => current = false),
        throwsStateError,
      );
      current = true;
      await expectLater(
        createViewerSpool(
          backend,
          item,
          onProgress: (_, _) =>
              client.put('/log.txt', 'changed size'.codeUnits),
        ),
        throwsStateError,
      );
    },
  );
}
