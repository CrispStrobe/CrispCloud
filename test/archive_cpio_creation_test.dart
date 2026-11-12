import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';

class _DatedBackend extends ArchiveCreationBackend {
  DateTime? modified;

  @override
  Future<FileItem?> stat(String path) async {
    final file = await super.stat(path);
    if (file == null || modified == null || !path.startsWith('/input/')) {
      return file;
    }
    return file.copyWith(updatedAt: modified);
  }
}

void main() {
  for (final (format, signature, variant) in [
    (ArchiveCreationFormat.cpioOdc, ascii.encode('070707'), '070707'),
    (ArchiveCreationFormat.cpioBinaryLittleEndian, [0xc7, 0x71], 'binary-le'),
    (ArchiveCreationFormat.cpioBinaryBigEndian, [0x71, 0xc7], 'binary-be'),
  ]) {
    late _DatedBackend backend;
    setUp(() {
      backend = _DatedBackend()
        ..put('/input/docs/Ünicode.txt', utf8.encode('A captured CPIO member.'))
        ..put('/input/docs/empty.txt', []);
      backend.directories.add('/input/docs/empty-folder');
    });

    Future<ArchiveCreationResult> create({String? password}) async =>
        const ArchiveCreationService().create(
          source: backend,
          destination: backend,
          files: [(await backend.stat('/input/docs'))!],
          destinationDirectory: '/output',
          options: ArchiveCreationOptions(
            name: 'output.cpio',
            format: format,
            compression: format.defaultCompression,
            password: password,
          ),
        );

    test(
      '${format.name} publishes the requested physical CPIO layout',
      () async {
        final result = await create();
        final bytes = backend.contents[result.path]!;
        expect(bytes.take(signature.length), signature);
        final archive = await openViewerArchive(bytes, name: result.path);
        addTearDown(archive.close);
        final inspection = await inspectPackageRewrite(bytes, 'cpio', archive);
        expect(inspection.supported, isTrue, reason: inspection.reason);
        expect(inspection.container['cpio.variant'], variant);
        expect(archive.members.map((m) => m.name).toSet(), {
          'docs',
          'docs/Ünicode.txt',
          'docs/empty.txt',
          'docs/empty-folder',
        });
        final member = archive.members.singleWhere(
          (m) => m.name.endsWith('Ünicode.txt'),
        );
        expect(
          utf8.decode(await archive.readMember(member)),
          'A captured CPIO member.',
        );
        expect(member.modified, DateTime.utc(2026, 1, 1));
        expect(backend.writes, [result.path]);
        expect(backend.contents.containsKey('/input/docs/Ünicode.txt'), isTrue);
      },
    );

    test('${format.name} refuses encryption before publication', () async {
      await expectLater(
        create(password: 'must not be silently ignored'),
        throwsA(isA<ArchiveCreationException>()),
      );
      expect(backend.writes, isEmpty);
      expect(
        backend.contents.keys.where((path) => path.startsWith('/output/')),
        isEmpty,
      );
    });

    test(
      '${format.name} refuses unrepresentable timestamps without output',
      () async {
        backend.modified = DateTime.utc(2500);
        await expectLater(create(), throwsA(isA<ArchiveViewException>()));
        expect(backend.writes, isEmpty);
        expect(
          backend.contents.keys.where((path) => path.startsWith('/output/')),
          isEmpty,
        );
        expect(
          backend.contents['/input/docs/Ünicode.txt'],
          utf8.encode('A captured CPIO member.'),
        );
      },
    );
  }
}
