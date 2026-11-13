import 'dart:io';

import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_file.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/archive_volume_fixtures.dart';

void main() {
  late Directory root;
  late String first;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('archive-volume-file-');
    final parts = volumeSplitBytes(
      volumeReferenceSevenZip(),
      sizes: volumeReferenceSizes,
    );
    for (var i = 0; i < parts.length; i++) {
      await File(
        p.join(root.path, 'fixture.7z.${(i + 1).toString().padLeft(3, '0')}'),
      ).writeAsBytes(parts[i]);
    }
    first = p.join(root.path, 'fixture.7z.001');
  });
  tearDown(() async => root.delete(recursive: true));

  test('native file opener captures every volume and preserves its read-only wrapper', () async {
    final archive = await openViewerArchiveFile(
      first,
      name: 'fixture.7z.001',
      streaming: true,
    );
    addTearDown(archive.close);
    expect(archive.formatName, 'volumes/7z');
    final member = archive.members.singleWhere(
      (member) => member.name == 'first.txt',
    );
    expect(await archive.readMember(member), volumeReferenceFirstFile());
    expect(archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
  });

  test('native extraction reads members spanning all numbered parts', () async {
    final target = p.join(root.path, 'extracted');
    final completed = await ArchiveService.extractArchive(first, target);
    expect(completed, contains(p.join(target, 'first.txt')));
    expect(
      await File(p.join(target, 'first.txt')).readAsBytes(),
      volumeReferenceFirstFile(),
    );
    expect(
      await File(p.join(target, 'nested', 'second.txt')).readAsString(),
      'Second member in another volume.\n',
    );
  });

  test(
    'native extraction refuses an incomplete set before creating outputs',
    () async {
      await File(p.join(root.path, 'fixture.7z.003')).delete();
      final target = p.join(root.path, 'extracted');
      await expectLater(
        ArchiveService.extractArchive(first, target),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await Directory(target).exists(), isFalse);
    },
  );

  test(
    'native extraction never overwrites an existing destination by default',
    () async {
      final target = Directory(p.join(root.path, 'extracted'));
      await target.create();
      final existing = File(p.join(target.path, 'first.txt'));
      await existing.writeAsString('keep existing');
      await expectLater(
        ArchiveService.extractArchive(first, target.path),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await existing.readAsString(), 'keep existing');
    },
  );
}
