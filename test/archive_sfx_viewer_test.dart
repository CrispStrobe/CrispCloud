import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_format_registry.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_sfx_fixtures.dart';

void main() {
  test('executables retain their binary default while SFX remains explicitly browsable', () {
    const viewer = InternalViewerService();
    expect(
      viewer.detectMode('program.exe', header: sfxPeArchive(sfxReferenceZip())),
      ViewerMode.binary,
    );
    expect(
      viewer.detectMode('bundle.sfx', header: sfxPeArchive(sfxReferenceZip())),
      ViewerMode.archive,
    );
  });
  test('self-extracting suffixes are read-only routing hints', () {
    for (final name in ['bundle.exe', 'BUNDLE.SFX']) {
      final format = archiveFormatForName(name)!;
      expect(format.id, 'sfx');
      expect(format.canCreate, isFalse);
      expect(format.canModify, isFalse);
    }
  });

  for (final absolute in [false, true]) {
    for (final name in ['bundle.exe', 'disguised.zip', 'extensionless']) {
      test(
        'ZIP SFX $name ($absolute absolute offsets) preserves its wrapper',
        () async {
          final zip = absolute
              ? sfxAbsoluteZipOffsets(sfxReferenceZip(), sfxPayloadOffset)
              : sfxReferenceZip();
          final bytes = sfxPeArchive(zip);
          final archive = await openViewerArchive(bytes, name: name);
          addTearDown(archive.close);
          expect(archive.formatName, 'sfx/zip');
          expect(archive.notices.join(' '), contains('never run'));
          final readme = archive.members.singleWhere(
            (m) => m.name == 'readme.txt',
          );
          expect(
            utf8.decode(await archive.readMember(readme)),
            'SFX payload\n',
          );
          final streamed = <int>[];
          await for (final part in archive.openMember(readme)) {
            streamed.addAll(part);
          }
          expect(utf8.decode(streamed), 'SFX payload\n');
          final policy = await ArchiveEndpointPolicy.inspect(
            bytes,
            name,
            archive,
            null,
          );
          expect(policy.format, ArchiveEndpointFormat.readOnly);
          expect(policy.reason, contains('executable prefix'));
        },
      );
    }
  }

  for (final kind in ['7z', 'rar']) {
    test('$kind SFX uses the normal bounded member reader', () async {
      final payload = kind == '7z'
          ? File('test/fixtures/archives/sample.7z').readAsBytesSync()
          : sfxReferenceRar5();
      final archive = await openViewerArchive(
        sfxPeArchive(payload),
        name: 'bundle.exe',
      );
      addTearDown(archive.close);
      expect(archive.formatName, 'sfx/$kind');
      final member = archive.members.firstWhere((m) => m.isFile);
      expect((await archive.readMember(member)).length, member.size);
      await expectLater(
        archive.readMember(member, maxBytes: 1),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test(
    'SFX ZIP retains password errors and encrypted member protection',
    () async {
      final zip = Uint8List.fromList(
        ar.ZipEncoder(password: 'secret').encode(
          ar.Archive()..addFile(
            ar.ArchiveFile.bytes('private.txt', utf8.encode('private bytes')),
          ),
        ),
      );
      final bytes = sfxPeArchive(zip);
      final locked = await openViewerArchive(bytes, name: 'private.exe');
      addTearDown(locked.close);
      await expectLater(
        locked.readMember(locked.members.single),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      final opened = await openViewerArchive(
        bytes,
        name: 'private.exe',
        password: 'secret',
      );
      addTearDown(opened.close);
      expect(opened.members.single.isEncrypted, isTrue);
      expect(
        utf8.decode(await opened.readMember(opened.members.single)),
        'private bytes',
      );
      final policy = await ArchiveEndpointPolicy.inspect(
        bytes,
        'renamed.zip',
        opened,
        'secret',
      );
      expect(policy.format, ArchiveEndpointFormat.readOnly);
      expect(policy.encrypted, isTrue);
    },
  );

  test(
    'an invalid PE cannot fall through to generic prefixed ZIP detection',
    () async {
      final bytes = sfxPeArchive(sfxReferenceZip());
      bytes[sfxPeOffset] = 0;
      await expectLater(
        openViewerArchive(bytes, name: 'renamed.zip'),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('an encrypted 7z SFX still requests the header password', () async {
    final bytes = sfxPeArchive(
      File('test/fixtures/archives/header_encrypted.7z').readAsBytesSync(),
    );
    await expectLater(
      openViewerArchive(bytes, name: 'private.exe'),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );
  });
}
