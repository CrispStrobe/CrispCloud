// test/archive_viewer_service_test.dart
//
// Unit tests for the F3 viewer's archive layer: format coverage (ZIP, TAR,
// TAR.GZ/BZ2/XZ/ZST, 7z, RAR), member reading, encryption/password handling,
// decompression-bomb caps, and malformed-input robustness.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';

Archive _sampleArchive() {
  return Archive()
    ..addFile(ArchiveFile.bytes('hello.txt', utf8.encode('hello archive')))
    ..addFile(ArchiveFile.bytes('dir/nested.bin', <int>[1, 2, 3, 4]));
}

Uint8List _zip() => Uint8List.fromList(ZipEncoder().encode(_sampleArchive()));

Uint8List _tar() => Uint8List.fromList(TarEncoder().encode(_sampleArchive()));

Uint8List _tarGz() => Uint8List.fromList(const GZipEncoder().encode(_tar()));

Uint8List _tarBz2() => Uint8List.fromList(BZip2Encoder().encode(_tar()));

Uint8List _tarXz() => Uint8List.fromList(XZEncoder().encode(_tar()));

Uint8List _tarZst() => Uint8List.fromList(ZstdEncoder().encode(_tar()));

Uint8List _fixture(String name) =>
    File('test/fixtures/archives/$name').readAsBytesSync();

Future<ViewerArchiveMember> _member(
  ViewerArchive archive,
  String name,
) async {
  final matches = archive.members.where((m) => m.name == name).toList();
  expect(matches, isNotEmpty, reason: 'missing member $name');
  return matches.first;
}

void main() {
  group('ZIP', () {
    test('lists and reads members', () async {
      final archive = await openViewerArchive(_zip(), name: 'sample.zip');
      addTearDown(archive.close);

      expect(archive.formatName, 'zip');
      final hello = await _member(archive, 'hello.txt');
      expect(hello.size, 13);
      expect(hello.isFile, isTrue);
      expect(hello.isEncrypted, isFalse);

      final bytes = await archive.readMember(hello);
      expect(utf8.decode(bytes), 'hello archive');

      final nested = await _member(archive, 'dir/nested.bin');
      expect(await archive.readMember(nested), <int>[1, 2, 3, 4]);
    });

    test('sanitizes and flags path traversal attempts', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('../escaped.txt', utf8.encode('nope')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final opened = await openViewerArchive(bytes, name: 'evil.zip');
      addTearDown(opened.close);
      final member = opened.members.firstWhere((m) => m.isFile);
      expect(member.name.contains('..'), isFalse);
      expect(member.pathEscapedRoot, isTrue);
    });
  });

  group('TAR variants', () {
    test('tar', () async {
      final archive = await openViewerArchive(_tar(), name: 'sample.tar');
      addTearDown(archive.close);
      expect((await _member(archive, 'hello.txt')).size, 13);
    });

    test('tar.gz', () async {
      final archive = await openViewerArchive(
        _tarGz(),
        name: 'sample.tar.gz',
      );
      addTearDown(archive.close);
      expect(
          utf8.decode(await archive.readMember(
            await _member(archive, 'hello.txt'),
          )),
          'hello archive');
    });

    test('tar.bz2', () async {
      final archive = await openViewerArchive(
        _tarBz2(),
        name: 'sample.tar.bz2',
      );
      addTearDown(archive.close);
      expect((await _member(archive, 'dir/nested.bin')).size, 4);
    });

    test('tbz2', () async {
      final archive = await openViewerArchive(_tarBz2(), name: 'sample.tbz2');
      addTearDown(archive.close);
      expect((await _member(archive, 'hello.txt')).size, 13);
    });

    test('tar.xz / txz', () async {
      for (final name in ['sample.tar.xz', 'sample.txz']) {
        final archive = await openViewerArchive(_tarXz(), name: name);
        await archive.close();
        expect(archive.formatName, 'tar', reason: name);
      }
    });

    test('tar.zst / tzst', () async {
      for (final name in ['sample.tar.zst', 'sample.tzst']) {
        final archive = await openViewerArchive(_tarZst(), name: name);
        await archive.close();
        expect(archive.formatName, 'tar', reason: name);
      }
    });
  });

  group('7z', () {
    test('lists and reads real fixture', () async {
      final archive = await openViewerArchive(
        _fixture('sample.7z'),
        name: 'sample.7z',
      );
      addTearDown(archive.close);

      expect(archive.formatName, '7z');
      final data = await _member(archive, 'nested/deep/data.bin');
      expect(data.size, 100000);
      expect((await archive.readMember(data)).length, 100000);
    });

    test('handles UTF-8 entry names', () async {
      final archive = await openViewerArchive(
        _fixture('deflate.7z'),
        name: 'deflate.7z',
      );
      addTearDown(archive.close);
      final names = archive.members.map((m) => m.name).toList();
      expect(names, contains('日本語/ページ001.txt'));
      final member = await _member(archive, 'hello.txt');
      expect(
          utf8.decode(await archive.readMember(member)).trim(), 'hello, 7z!');
    });

    test('encrypted archive requests a password on member read', () async {
      final bytes = _fixture('encrypted.7z');
      final locked = await openViewerArchive(bytes, name: 'encrypted.7z');
      final lockedMember = await _member(locked, 'hello.txt');
      expect(lockedMember.isEncrypted, isTrue);
      await expectLater(
        locked.readMember(lockedMember),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      await locked.close();

      final archive = await openViewerArchive(
        bytes,
        name: 'encrypted.7z',
        password: 'secret',
      );
      addTearDown(archive.close);
      final member = await _member(archive, 'hello.txt');
      expect(
          utf8.decode(await archive.readMember(member)).trim(), 'hello, 7z!');
    });

    test('unsupported compression reports a typed error (no hang)', () async {
      final archive = await openViewerArchive(
        _fixture('bcj2.7z'),
        name: 'bcj2.7z',
      );
      addTearDown(archive.close);
      final member = archive.members.firstWhere((m) => m.isFile);
      await expectLater(
        archive.readMember(member),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('encrypted headers require the password at open', () async {
      final bytes = _fixture('header_encrypted.7z');
      await expectLater(
        openViewerArchive(bytes, name: 'header_encrypted.7z'),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );

      final archive = await openViewerArchive(
        bytes,
        name: 'header_encrypted.7z',
        password: 'secret',
      );
      addTearDown(archive.close);
      final file = archive.members.firstWhere((m) => m.isFile);
      expect((await archive.readMember(file)).isNotEmpty, isTrue);
    });
  });

  group('RAR', () {
    test('lists and reads real RAR4 fixture', () async {
      final archive = await openViewerArchive(
        _fixture('sample.rar'),
        name: 'sample.rar',
      );
      addTearDown(archive.close);

      expect(archive.formatName, 'rar');
      final bitmap = await _member(archive, 'grad.bmp');
      expect(bitmap.size, 27702);
      final bytes = await archive.readMember(bitmap);
      expect(bytes.length, 27702);
      expect(bytes.sublist(0, 2), <int>[0x42, 0x4D]); // "BM"
    });

    test('encrypted RAR4 prompts on member read and decrypts', () async {
      final bytes = _fixture('encrypted.rar');
      final locked = await openViewerArchive(bytes, name: 'encrypted.rar');
      final lockedMember = await _member(locked, 'hello.txt');
      expect(lockedMember.isEncrypted, isTrue);
      await expectLater(
        locked.readMember(lockedMember),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      await locked.close();

      final archive = await openViewerArchive(
        bytes,
        name: 'encrypted.rar',
        password: 'secret',
      );
      addTearDown(archive.close);
      final member = await _member(archive, 'hello.txt');
      expect(
          utf8.decode(await archive.readMember(member)).trim(), 'hello, rar!');
    });

    test('wrong RAR4 password is reported as a password failure', () async {
      final bytes = _fixture('encrypted.rar');
      try {
        final archive = await openViewerArchive(
          bytes,
          name: 'encrypted.rar',
          password: 'definitely-wrong',
        );
        final member = archive.members.firstWhere((m) => m.isFile);
        await expectLater(
          archive.readMember(member),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
        await archive.close();
      } on ArchivePasswordRequiredException catch (e) {
        expect(e.wrongPassword, isTrue);
      }
    });
  });

  group('safety', () {
    test('garbage input throws a typed archive error', () async {
      final garbage = Uint8List.fromList(List<int>.filled(256, 0x41));
      await expectLater(
        openViewerArchive(garbage, name: 'not-an-archive.zip'),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('random inputs never escape the typed error contract', () async {
      final rng = Random(20261104);
      for (var i = 0; i < 100; i++) {
        final bytes = Uint8List.fromList(
          List<int>.generate(rng.nextInt(512), (_) => rng.nextInt(256)),
        );
        try {
          final archive = await openViewerArchive(bytes, name: 'fuzz.bin');
          await archive.close();
        } on ArchiveViewException {
          // Clean, typed rejection.
        } on ArchivePasswordRequiredException {
          // Also a documented rejection.
        }
      }
    });

    test('gzip expansion bomb is rejected by maxOutputSize', () {
      final bomb = Uint8List.fromList(
        const GZipEncoder().encode(Uint8List(1024 * 1024)),
      );
      expect(
        () => decompressSingleFile(bomb, 'bomb.gz', maxBytes: 4096),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('archive member size cap is enforced', () async {
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(Archive()
          ..addFile(ArchiveFile.bytes('big.bin', Uint8List(64 * 1024)))),
      );
      final archive = await openViewerArchive(
        bytes,
        name: 'big.zip',
        maxMemberBytes: 1024,
      );
      addTearDown(archive.close);
      final member = archive.members.firstWhere((m) => m.isFile);
      await expectLater(
        archive.readMember(member),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  });

  group('office text extraction', () {
    test('extracts text from a DOCX-shaped zip', () async {
      const xml =
          '<w:document><w:body><w:p><w:t>Hello office</w:t></w:p></w:body></w:document>';
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes('word/document.xml', utf8.encode(xml)),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(
        await extractOfficeText(bytes, 'report.docx'),
        contains('Hello office'),
      );
    });

    test('oversized XML parts are skipped without decompressing', () async {
      final big = Uint8List(20 * 1024 * 1024);
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('word/document.xml', big));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(
        await extractOfficeText(bytes, 'huge.docx'),
        '(No text content found)',
      );
    });
  });

  group('single-file compression', () {
    final payload = utf8.encode('expanded content');

    test('gz/bz2/xz/zst expand and report the inner name', () {
      final cases = <String, List<int>>{
        'notes.txt.gz': const GZipEncoder().encode(payload),
        'notes.txt.bz2': BZip2Encoder().encode(payload),
        'notes.txt.xz': XZEncoder().encode(payload),
        'notes.txt.zst': ZstdEncoder().encode(payload),
      };
      for (final entry in cases.entries) {
        final result = decompressSingleFile(
          Uint8List.fromList(entry.value),
          entry.key,
        );
        expect(result.innerName, 'notes.txt', reason: entry.key);
        expect(utf8.decode(result.data), 'expanded content', reason: entry.key);
      }
    });

    test('identifies single-file compression vs tar containers', () {
      expect(isSingleCompressedFile('a.txt.gz'), isTrue);
      expect(isSingleCompressedFile('a.txt.bz2'), isTrue);
      expect(isSingleCompressedFile('a.txt.xz'), isTrue);
      expect(isSingleCompressedFile('a.txt.zst'), isTrue);
      expect(isSingleCompressedFile('a.tar.gz'), isFalse);
      expect(isSingleCompressedFile('a.tgz'), isFalse);
      expect(isSingleCompressedFile('a.tar.bz2'), isFalse);
      expect(isSingleCompressedFile('a.tbz2'), isFalse);
      expect(isSingleCompressedFile('a.tar.xz'), isFalse);
      expect(isSingleCompressedFile('a.tzst'), isFalse);
    });
  });
}
