import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/metadata_sidecar_service.dart';

class _FailSidecarBackend extends LocalOperationBackend {
  _FailSidecarBackend() : super(LocalFileService(), isCurrent: () => true);
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    throw StateError('Sidecar write unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalOperationBackend backend;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('metadata-sidecar-');
    backend = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
  });
  tearDown(() => root.delete(recursive: true));
  Future<List<FileSystemEntity>> copy({bool sidecars = true}) async {
    await Directory('${root.path}/source').create();
    await Directory('${root.path}/target').create();
    final file = await File('${root.path}/source/example.txt')
        .writeAsString('content');
    await file.setLastModified(DateTime.utc(2020, 1, 2));
    final plan = await const FileOperationService().prepare(
      files: [(await backend.stat(file.path))!],
      source: backend,
      destination: backend,
      targetDirectory: '${root.path}/target',
      options: FileOperationOptions(
        verifyContents: true,
        saveMetadataSidecars: sidecars,
      ),
    );
    expect(plan.errors, isEmpty);
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(
      plan.entries.where((e) => e.failed),
      isEmpty,
      reason: '${plan.entries.map((e) => e.message)}',
    );
    return Directory('${root.path}/target').list().toList();
  }

  test(
    'default off and old profiles remain off; verification is mandatory',
    () {
      expect(const FileOperationOptions().saveMetadataSidecars, isFalse);
      expect(
        FileOperationOptions.fromJson(
          const FileOperationOptions().toJson()..remove('saveMetadataSidecars'),
        ).saveMetadataSidecars,
        isFalse,
      );
      expect(
        const FileOperationOptions(saveMetadataSidecars: true)
            .validateTransferSettings,
        throwsFormatException,
      );
      final o = FileOperationOptions.fromJson(
        const FileOperationOptions(
          saveMetadataSidecars: true,
          verifyContents: true,
        ).toJson(),
      );
      expect(o.saveMetadataSidecars, isTrue);
    },
  );
  test(
    'verified copy saves portable record and explicitly restores timestamp',
    () async {
      final files = await copy();
      final sidecar = files.singleWhere(
        (f) => MetadataSidecarService.isSidecarName(f.uri.pathSegments.last),
      );
      final item = (await backend.stat(sidecar.path))!;
      final record = await MetadataSidecarService.read(backend, item);
      expect(record['name'], 'example.txt');
      expect(
        record['contentSha256'],
        sha256.convert(utf8.encode('content')).toString(),
      );
      expect(
        await File(sidecar.path).readAsString(),
        isNot(contains(root.path)),
      );
      final target = File('${root.path}/target/example.txt');
      await target.setLastModified(DateTime.utc(2025));
      await MetadataSidecarService.restore(backend, item);
      expect((await target.lastModified()).toUtc(), DateTime.utc(2020, 1, 2));
      await target.writeAsString('changed');
      await expectLater(
        MetadataSidecarService.restore(backend, item),
        throwsStateError,
      );
    },
  );
  test('no sidecar is created without explicit opt-in', () async {
    expect((await copy(sidecars: false)).length, 1);
  });
  test('tampered records and path traversal are rejected', () async {
    final files = await copy();
    final sidecar = files.singleWhere((f) => f.path.endsWith('.json'));
    final content = jsonDecode(
      await File(sidecar.path).readAsString(),
    ) as Map<String, dynamic>;
    content['name'] = '../outside';
    final bytes = utf8.encode(jsonEncode(content));
    await File(sidecar.path).writeAsBytes(bytes);
    await expectLater(
      MetadataSidecarService.read(backend, (await backend.stat(sidecar.path))!),
      throwsFormatException,
    );
    final malicious = await File(
      '${root.path}/target/.crispmeta-${sha256.convert(bytes)}.json',
    ).writeAsBytes(bytes);
    await expectLater(
      MetadataSidecarService.restore(
        backend,
        (await backend.stat(malicious.path))!,
      ),
      throwsFormatException,
    );
  });
  test('failed sidecar creation retains source during Move', () async {
    final source = await File('${root.path}/original.txt')
        .writeAsString('keep me');
    final destination = await Directory('${root.path}/target').create();
    final plan = await const FileOperationService().prepare(
      files: [(await backend.stat(source.path))!],
      source: backend,
      destination: _FailSidecarBackend(),
      targetDirectory: destination.path,
      options: const FileOperationOptions(
        kind: FileOperationKind.move,
        saveMetadataSidecars: true,
        verifyContents: true,
      ),
    );
    expect(plan.errors, isEmpty);
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(await source.readAsString(), 'keep me');
    expect(plan.entries.single.outcome, FileOperationOutcome.metadataFailed);
  });

  test('symbolic-link destination is never restored', () async {
    final files = await copy();
    final sidecar = files.singleWhere((f) => f.path.endsWith('.json'));
    final target = File('${root.path}/target/example.txt');
    await target.delete();
    await Link(target.path).create('${root.path}/source/example.txt');
    await expectLater(
      MetadataSidecarService.restore(
        backend,
        (await backend.stat(sidecar.path))!,
      ),
      throwsStateError,
    );
  });
}
