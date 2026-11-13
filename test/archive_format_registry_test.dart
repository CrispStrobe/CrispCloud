import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_format_registry.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewer = InternalViewerService();
const _panel = PanelSourceService();

void main() {
  group('archive recognition across entry points', () {
    test(
      'public extension inventory includes every archive suffix exactly once',
      () {
        final inventory = _viewer.getSupportedExtensions();
        final archiveSuffixes = inventory[ViewerMode.archive];
        expect(archiveSuffixes, isNotNull);
        expect(
          archiveSuffixes,
          unorderedEquals([
            for (final format in archiveFormatCapabilities) ...format.suffixes,
          ]),
        );
        expect(archiveSuffixes!.toSet().length, archiveSuffixes.length);
        for (final document in ['.docx', '.xlsx', '.pptx', '.epub']) {
          expect(archiveSuffixes, isNot(contains(document)));
          expect(inventory[ViewerMode.office], contains(document));
        }
      },
    );

    for (final format in archiveFormatCapabilities) {
      test('${format.label} suffixes agree across navigation, F3 and MIME', () {
        for (final suffix in format.suffixes) {
          for (final name in [
            'sample$suffix',
            'SAMPLE${suffix.toUpperCase()}',
            '/cloud/Folder with spaces/日本語$suffix',
            'C:\\Downloads\\sample$suffix',
          ]) {
            expect(ArchiveService.isArchive(name), isTrue, reason: name);
            expect(_panel.isArchive(name), isTrue, reason: name);
            expect(_panel.canEnter(name), isTrue, reason: name);
            final expectedViewerMode =
                format.id == 'sfx' && name.toLowerCase().endsWith('.exe')
                ? ViewerMode.binary
                : ViewerMode.archive;
            expect(_viewer.detectMode(name), expectedViewerMode, reason: name);
            final content = _viewer.loadContent(Uint8List(1), name);
            expect(content.mode, expectedViewerMode, reason: name);
            if (expectedViewerMode == ViewerMode.archive) {
              expect(content.mimeType, format.mimeType, reason: name);
            }
            expect(
              isArchiveVirtualPath('$name:/folder/file.txt'),
              isTrue,
              reason: name,
            );
          }
          expect(ArchiveService.isArchive('sample$suffix.partial'), isFalse);
          expect(_panel.isArchive('sample$suffix/'), isFalse);
        }
      });
    }

    test('compound suffixes route before single-file compression aliases', () {
      const expected = {
        'bundle.tar.gz': 'tar-gzip',
        'bundle.tgz': 'tar-gzip',
        'bundle.tar.bz2': 'tar-bzip2',
        'bundle.tar.bzip2': 'tar-bzip2',
        'bundle.tbz2': 'tar-bzip2',
        'bundle.tbz': 'tar-bzip2',
        'bundle.tar.xz': 'tar-xz',
        'bundle.txz': 'tar-xz',
        'bundle.tar.zst': 'tar-zstd',
        'bundle.tar.zstd': 'tar-zstd',
        'bundle.tzst': 'tar-zstd',
        'bundle.tar.lz4': 'tar-lz4',
        'bundle.tar.lzma': 'tar-lzma',
        'bundle.tlz': 'tar-lzma',
        'bundle.tar.lz': 'tar-lzip',
        'bundle.tar.Z': 'tar-compress',
        'bundle.taz': 'tar-compress',
      };
      for (final entry in expected.entries) {
        expect(archiveFormatForName(entry.key)?.id, entry.value);
        expect(isSingleCompressedFile(entry.key), isFalse, reason: entry.key);
        expect(
          isSingleCompressedFile(entry.key.toUpperCase()),
          isFalse,
          reason: entry.key,
        );
      }
      for (final suffix in [
        '.gz',
        '.gzip',
        '.bz2',
        '.bzip2',
        '.xz',
        '.zst',
        '.zstd',
        '.lz4',
        '.lzma',
        '.lz',
        '.Z',
      ]) {
        final name = 'notes.txt$suffix';
        expect(isSingleCompressedFile(name), isTrue, reason: name);
        expect(stripCompressionSuffix(name), 'notes.txt');
      }
    });

    test(
      'nested virtual routes distinguish archive delimiters from drive letters',
      () {
        for (final path in [
          '/images/disc.iso:/DOCS',
          r'C:\images\installer.dmg:/files/001-volume',
          'C:/images/disc.iso:/DOCS',
          '/packages/outer.deb:/data.tar.xz:/usr/share',
          '/extensions/app.msix:/assets',
          '/objects/libsample.a:/object.o',
          '/packages/app.rpm:/usr/share',
          '/packages/app.cab:/readme.txt',
          '/packages/data.pbzx:/docs',
          '/packages/data.tar.lz4:/docs',
          '/packages/data.tlz:/docs',
          '/packages/data.tar.lz:/docs',
          '/packages/data.taz:/docs',
        ]) {
          expect(isArchiveVirtualPath(path), isTrue, reason: path);
        }
        for (final path in [
          'C:/Windows',
          r'C:\images\disc.iso',
          '/images/disc.iso',
          '/images/disc.iso.partial:/DOCS',
          '/images/disc.iso/folder:/DOCS',
          '/unsupported/data.arj:/entry',
          'https://example.test/data.iso',
        ]) {
          expect(isArchiveVirtualPath(path), isFalse, reason: path);
        }
      },
    );

    test('new container families have explicit MIME types', () {
      const expected = {
        'disc.iso': 'application/x-iso9660-image',
        'installer.dmg': 'application/x-apple-diskimage',
        'volume.hfs': 'application/octet-stream',
        'volume.hfsx': 'application/octet-stream',
        'package.deb': 'application/x-archive',
        'library.a': 'application/x-archive',
        'payload.cpio': 'application/x-cpio',
        'installer.pkg': 'application/x-xar',
        'signed.xip': 'application/x-xar',
        'extension.crx': 'application/x-chrome-extension',
        'package.rpm': 'application/x-rpm',
        'cabinet.cab': 'application/vnd.ms-cab-compressed',
        'payload.pbzx': 'application/octet-stream',
        'payload.lz4': 'application/x-lz4',
        'payload.lzma': 'application/x-lzma',
        'payload.lz': 'application/x-lzip',
        'payload.Z': 'application/x-compress',
      };
      for (final entry in expected.entries) {
        expect(
          _viewer.loadContent(Uint8List(0), entry.key).mimeType,
          entry.value,
        );
      }
    });

    test(
      'Office and EPUB keep specialized viewers despite their ZIP payloads',
      () {
        final zipHeader = Uint8List.fromList([0x50, 0x4b, 3, 4, 20, 0, 0, 0]);
        for (final suffix in [
          '.docx',
          '.docm',
          '.dotx',
          '.dotm',
          '.xlsx',
          '.xlsm',
          '.xltx',
          '.pptx',
          '.pptm',
          '.potx',
          '.odt',
          '.ods',
          '.odp',
          '.epub',
        ]) {
          final name = 'document$suffix';
          expect(archiveFormatForName(name), isNull, reason: name);
          expect(ArchiveService.isArchive(name), isFalse, reason: name);
          expect(_panel.isArchive(name), isFalse, reason: name);
          expect(_viewer.detectMode(name), ViewerMode.office, reason: name);
          expect(
            _viewer.detectMode(name, header: zipHeader),
            ViewerMode.office,
            reason: name,
          );
          expect(
            _viewer.loadContent(zipHeader, name).mimeType,
            isNot('application/zip'),
            reason: name,
          );
        }
      },
    );

    test('unsupported formats are not advertised as browsable or writable', () {
      for (final suffix in [
        '.arj',
        '.lzh',
        '.lha',
        '.ace',
        '.uc2',
        '.udf',
        '.vhd',
        '.vhdx',
        '.vmdk',
        '.qcow2',
        '.vdi',
        '.apfs',
        '.img',
        '.sparseimage',
        '.sparsebundle',
        '.lzo',
        '.zipx',
      ]) {
        final name = 'unsupported$suffix';
        expect(archiveFormatForName(name), isNull, reason: name);
        expect(ArchiveService.isArchive(name), isFalse, reason: name);
        expect(_panel.canEnter(name), isFalse, reason: name);
        expect(
          _viewer.detectMode(name),
          isNot(ViewerMode.archive),
          reason: name,
        );
        expect(isArchiveVirtualPath('$name:/entry'), isFalse, reason: name);
      }
    });

    test(
      'encrypted vault navigation remains separate from archive recognition',
      () {
        for (final name in ['vault.vc', 'vault.hc', 'vault.cryptomator']) {
          expect(archiveFormatForName(name), isNull, reason: name);
          expect(ArchiveService.isArchive(name), isFalse, reason: name);
          expect(_panel.isEncryptedContainer(name), isTrue, reason: name);
          expect(_panel.canEnter(name), isTrue, reason: name);
        }
      },
    );
  });

  group('writer capabilities require content-specific eligibility', () {
    test('creation and editing advertise their distinct format families', () {
      expect(
        archiveFormatCapabilities
            .where((format) => format.canCreate)
            .map((format) => format.id)
            .toSet(),
        {
          'zip',
          'zip-alias',
          'java-archive',
          '7z',
          '7z-alias',
          'rar',
          'tar',
          'tar-alias',
          'tar-gzip',
          'tar-bzip2',
          'tar-xz',
          'tar-zstd',
          'tar-lz4',
          'tar-lzma',
          'tar-compress',
          'gzip',
          'bzip2',
          'xz',
          'zstd',
          'lz4',
          'lzma',
          'compress',
          'iso',
          'dmg',
          'hfs',
          'ar',
          'cpio',
          'xar',
        },
      );
      expect(
        archiveFormatCapabilities
            .where((format) => format.canModify)
            .map((format) => format.id)
            .toSet(),
        {
          'zip',
          'zip-alias',
          'java-archive',
          '7z',
          '7z-alias',
          'rar',
          'tar',
          'tar-alias',
          'tar-gzip',
          'tar-bzip2',
          'tar-xz',
          'tar-zstd',
          'tar-lz4',
          'tar-lzma',
          'gzip',
          'tar-compress',
          'bzip2',
          'xz',
          'zstd',
          'lz4',
          'lzma',
          'iso',
          'dmg',
          'compress',
          'ar',
          'deb',
          'cpio',
          'xar',
        },
      );
    });

    test('Lzip remains read-only and UNIX compress has bounded writers', () {
      for (final name in ['file.lz', 'files.tar.lz']) {
        final format = archiveFormatForName(name)!;
        expect(format.canCreate, isFalse, reason: name);
        expect(format.canModify, isFalse, reason: name);
        expect(format.notes, contains('Read-only'), reason: name);
      }
      for (final name in ['file.Z', 'files.tar.Z', 'files.taz']) {
        final format = archiveFormatForName(name)!;
        expect(format.canCreate, isTrue, reason: name);
        expect(format.canModify, isTrue, reason: name);
        expect(format.notes, contains('no content checksum'), reason: name);
        expect(format.notes, contains('14-bit block coding'), reason: name);
      }
      expect(
        archiveFormatForName('file.lzma')!.notes,
        contains('no content checksum'),
      );
      expect(archiveFormatForName('file.lzma')!.notes, contains('filename'));
      expect(archiveFormatForName('file.lz4')!.notes, contains('skippable'));
    });

    final zipAliases = archiveFormatCapabilities
        .singleWhere((format) => format.id == 'zip-package')
        .suffixes;
    for (final suffix in zipAliases) {
      test(
        '$suffix members can be read while repacking stays disabled',
        () async {
          final bytes = _packageZip();
          final original = Uint8List.fromList(bytes);
          final name = 'package${suffix.toUpperCase()}';
          final archive = await openViewerArchive(bytes, name: name);
          addTearDown(archive.close);
          expect(archive.formatName, 'zip');
          final member = archive.members.singleWhere(
            (member) => member.name == 'payload.txt',
          );
          expect(
            utf8.decode(await archive.readMember(member)),
            'package content',
          );
          expect(
            archive.notices.join(' '),
            contains('signatures are not verified'),
          );
          final policy = await ArchiveEndpointPolicy.inspect(
            bytes,
            name,
            archive,
            null,
          );
          expect(policy.format, ArchiveEndpointFormat.readOnly);
          expect(policy.reason, isNotNull);
          expect(archiveFormatForName(name)!.canModify, isFalse);
          expect(bytes, original);
        },
      );
    }

    test(
      'a plain ZIP with the same members retains its existing writer policy',
      () async {
        final bytes = _packageZip();
        final archive = await openViewerArchive(bytes, name: 'ordinary.zip');
        addTearDown(archive.close);
        final policy = await ArchiveEndpointPolicy.inspect(
          bytes,
          'ordinary.zip',
          archive,
          null,
        );
        expect(policy.format, ArchiveEndpointFormat.zip);
        expect(policy.reason, isNull);
        expect(policy.encrypted, isFalse);
        expect(policy.encryptNames, isFalse);
      },
    );

    test(
      'a CRX3 wrapper exposes ZIP contents without gaining a writer',
      () async {
        final zip = _packageZip();
        // Structural CRX3 header with opaque protobuf/signature metadata. The
        // reader deliberately does not authenticate that metadata or package.
        final bytes = Uint8List(16 + zip.length);
        bytes.setAll(0, ascii.encode('Cr24'));
        ByteData.sublistView(bytes)
          ..setUint32(4, 3, Endian.little)
          ..setUint32(8, 4, Endian.little);
        bytes.setAll(12, [8, 1, 16, 1]);
        bytes.setAll(16, zip);
        final archive = await openViewerArchive(bytes, name: 'extension.crx');
        addTearDown(archive.close);
        expect(archive.formatName, 'zip');
        final member = archive.members.singleWhere(
          (member) => member.name == 'payload.txt',
        );
        expect(
          utf8.decode(await archive.readMember(member)),
          'package content',
        );
        expect(
          archive.notices.join(' '),
          contains('signatures are not verified'),
        );
        final policy = await ArchiveEndpointPolicy.inspect(
          bytes,
          'extension.crx',
          archive,
          null,
        );
        expect(policy.format, ArchiveEndpointFormat.readOnly);
        expect(policy.reason, isNotNull);
      },
    );

    test(
      'renaming ZIP bytes to a disk-image suffix cannot enable image writes',
      () async {
        for (final name in [
          'image.iso',
          'image.dmg',
          'volume.hfs',
          'installer.pkg',
        ]) {
          final bytes = _packageZip();
          final archive = await openViewerArchive(bytes, name: name);
          try {
            expect(archive.formatName, 'zip', reason: name);
            final policy = await ArchiveEndpointPolicy.inspect(
              bytes,
              name,
              archive,
              null,
            );
            expect(policy.reason, isNotNull, reason: name);
          } finally {
            await archive.close();
          }
        }
      },
    );

    test('a filename hint never makes invalid bytes a valid archive', () async {
      for (final format in archiveFormatCapabilities) {
        await expectLater(
          openViewerArchive(
            Uint8List.fromList([1, 2, 3]),
            name: 'invalid${format.suffixes.first}',
          ),
          throwsA(isA<ArchiveViewException>()),
          reason: format.id,
        );
      }
    });
  });
}

Uint8List _packageZip() {
  final archive = codec.Archive()
    ..addFile(
      codec.ArchiveFile.bytes('payload.txt', utf8.encode('package content')),
    )
    // Synthetic signature-shaped members ensure the aliases stay read-only;
    // these test bytes make no claim to be authenticated publisher signatures.
    ..addFile(
      codec.ArchiveFile.bytes('META-INF/CERT.SF', utf8.encode('unverified')),
    )
    ..addFile(codec.ArchiveFile.bytes('AppxSignature.p7x', [1, 2, 3]));
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}
