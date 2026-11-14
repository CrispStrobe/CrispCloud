// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_integrity_service.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'support/archive_ext_disk_fixture.dart';
import 'support/archive_ext_reference_data.dart';

ViewerArchiveMember _member(String path, int index, {bool special = false}) =>
    ViewerArchiveMember(
      name: path,
      index: index,
      size: 0,
      isFile: true,
      isSpecial: special,
      isEncrypted: false,
      pathEscapedRoot: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('ext-extract-');
  });
  tearDown(() => temp.delete(recursive: true));

  for (final native in [false, true]) {
    for (final partitioned in [false, true]) {
      test(
        '${native ? 'native Extract here API' : 'buffered API'} extracts '
        '${partitioned ? 'Linux GPT' : 'ext'} regulars and omits special metadata',
        () async {
          final Uint8List bytes;
          if (partitioned) {
            final source = extGptFixture(volumes: [ExtReferenceSource('ext2')]);
            bytes = await source.read(0, source.length);
            await source.close();
          } else {
            bytes = extReferenceBytes('ext2');
          }
          final before = sha256.convert(bytes).toString();
          final image = File(
            p.join(temp.path, partitioned ? 'volume.img' : 'volume.ext2'),
          );
          await image.writeAsBytes(bytes);
          final target = p.join(temp.path, 'output');
          final List<String> extracted;
          if (native) {
            extracted = await ArchiveService.extractArchive(image.path, target);
          } else {
            // Actual content determines the image-only omission policy even if
            // the supplied filename resembles an ordinary writable archive.
            extracted = await ArchiveService.extractArchiveBytes(
              'renamed.zip',
              bytes,
              target,
            );
          }
          final prefix = partitioned ? 'partition-001/files' : '';
          final expected = extReferenceImages['ext2']!.files;
          expect(extracted.length, expected.length + (partitioned ? 1 : 0));
          for (final entry in expected.entries) {
            final path = p.joinAll([
              target,
              if (prefix.isNotEmpty) prefix,
              ...entry.key.split('/'),
            ]);
            expect(
              await FileSystemEntity.type(path, followLinks: false),
              FileSystemEntityType.file,
            );
            expect(await File(path).length(), entry.value.$1);
            expect(
              (await sha256.bind(File(path).openRead()).single).toString(),
              entry.value.$2,
            );
          }
          for (final special in extReferenceSpecials) {
            final path = p.joinAll([
              target,
              if (prefix.isNotEmpty) prefix,
              special,
            ]);
            expect(
              await FileSystemEntity.type(path, followLinks: false),
              FileSystemEntityType.notFound,
            );
          }
          for (final directory in extReferenceDirectories) {
            expect(
              await Directory(
                p.joinAll([target, if (prefix.isNotEmpty) prefix, directory]),
              ).exists(),
              isTrue,
            );
          }
          if (partitioned) {
            expect(
              (await sha256
                      .bind(
                        File(p.join(target, 'partition-001', 'raw.img'))
                            .openRead(),
                      )
                      .single)
                  .toString(),
              extReferenceImages['ext2']!.sha256,
            );
          }
          expect(
            (await sha256.bind(image.openRead()).single).toString(),
            before,
          );
          expect(sha256.convert(bytes).toString(), before);
          expect(
            (await Directory(target)
                    .list(recursive: true, followLinks: false)
                    .toList())
                .whereType<Link>(),
            isEmpty,
          );
        },
      );
    }
  }

  for (final format in ['ext', 'disk-image']) {
    for (final (label, entries) in <(String, List<ViewerArchiveMember>)>[
      (
        'duplicate hidden path',
        [
          _member('safe.txt', 0),
          _member('same', 1, special: true),
          _member('same', 2),
        ],
      ),
      (
        'hidden file ancestor',
        [
          _member('safe.txt', 0),
          _member('link', 1, special: true),
          _member('link/file', 2),
        ],
      ),
      (
        'later hidden ancestor',
        [
          _member('safe.txt', 0),
          _member('link/file', 1),
          _member('link', 2, special: true),
        ],
      ),
      (
        'normalized duplicate',
        [
          _member('safe.txt', 0),
          _member('dir//same', 1, special: true),
          _member('dir/same', 2),
        ],
      ),
      (
        'hidden traversal',
        [_member('safe.txt', 0), _member('../escape', 1, special: true)],
      ),
    ]) {
      test(
        '$format refuses $label before any extraction or payload read',
        () async {
          var reads = 0;
          final archive = ViewerArchive.reader(
            formatName: format,
            members: entries,
            read: (_, __) async {
              reads++;
              return Uint8List(0);
            },
            close: () async {},
          );
          addTearDown(archive.close);
          final target = p.join(temp.path, 'output');
          await expectLater(
            ArchiveService.extractOpenedSnapshot(archive, target),
            throwsA(isA<ArchiveViewException>()),
          );
          expect(reads, 0);
          expect(await Directory(target).exists(), isFalse);
          expect(await temp.list().toList(), isEmpty);
        },
      );
    }
  }

  test(
    'generic archive extraction still rejects special entries before writes',
    () async {
      for (final format in ['zip', 'tar', 'fat', 'udf']) {
        var reads = 0;
        final archive = ViewerArchive.reader(
          formatName: format,
          members: [_member('safe.txt', 0), _member('link', 1, special: true)],
          read: (_, __) async {
            reads++;
            return Uint8List(0);
          },
          close: () async {},
        );
        addTearDown(archive.close);
        final target = p.join(temp.path, format);
        await expectLater(
          ArchiveService.extractOpenedSnapshot(archive, target),
          throwsA(isA<ArchiveViewException>()),
          reason: format,
        );
        expect(reads, 0);
        expect(await Directory(target).exists(), isFalse);
      }
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test('integrity keeps special metadata as explicit skips without a namespace error', () async {
    final archive = await openViewerArchive(
      extReferenceBytes('ext2'),
      name: 'volume.ext2',
    );
    addTearDown(archive.close);
    final report = await checkArchiveIntegrity(archive);
    expect(report.namespaceIssue, isNull);
    expect(report.failedCount, 0);
    expect(report.checkedCount, extReferenceImages['ext2']!.files.length);
    expect(report.skippedCount, extReferenceSpecials.length);
    expect(
      report.entries
          .where((e) => e.status == ArchiveIntegrityStatus.skipped)
          .every(
            (e) => e.skipReason == ArchiveIntegritySkipReason.specialEntry,
          ),
      isTrue,
    );
    expect(report.allRegularMembersChecked, isFalse);
  });
}
