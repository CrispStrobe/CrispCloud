// test/viewer_live_test.dart
//
// "Live" tests against real files on disk (no mocks): text decoding, windowed
// file streaming, and real ZIP/TAR.GZ/TAR.BZ2/TAR.XZ/TAR.ZST/7z/RAR files
// written to a temp directory and read back through the viewer services.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';

const _svc = InternalViewerService();

Uint8List _archiveBytes() {
  return Uint8List.fromList(
    ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('real file')))
        ..addFile(ArchiveFile.bytes(
            'data/blob.bin', List<int>.generate(256, (i) => i))),
    ),
  );
}

Future<Uint8List> _writeAndRead(
  Directory dir,
  String name,
  Uint8List bytes,
) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  expect(await file.exists(), isTrue);
  expect(await file.length(), bytes.length);
  return file.readAsBytes();
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crisp_viewer_live_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('real UTF-8 file decodes and is detected as text', () async {
    final file = File('${dir.path}/notes.txt');
    await file.writeAsString('Grüße aus dem Viewer\nzweite Zeile\n');

    final bytes = await file.readAsBytes();
    expect(
      _svc.detectMode('notes.txt', header: bytes.sublist(0, 12)),
      ViewerMode.text,
    );
    final decoded = InternalViewerService.decodeTextForView(bytes);
    expect(decoded.text, contains('Grüße'));
    expect(decoded.encoding, 'utf8');
  });

  test('real binary file is detected as binary and hex-safe', () async {
    final data = Uint8List.fromList(List<int>.generate(4096, (i) => i & 0xFF));
    final file = File('${dir.path}/payload.bin');
    await file.writeAsBytes(data);

    final bytes = await file.readAsBytes();
    expect(
      _svc.detectMode('payload.bin', header: bytes.sublist(0, 16)),
      ViewerMode.binary,
    );
    final safe = InternalViewerService.renderSafeBytes(bytes);
    expect(safe.length, greaterThan(0));
    expect(safe.contains('\u0000'), isFalse);
  });

  test('real multi-MB file streams across the 256 KiB window', () async {
    const size = 2 * 1024 * 1024 + 17;
    final data = Uint8List(size);
    for (var i = 0; i < size; i++) {
      data[i] = i % 251;
    }
    final file = File('${dir.path}/big.bin');
    await file.writeAsBytes(data);

    final source = ViewBytesSource.file(file.path);
    await source.open();
    addTearDown(source.dispose);

    expect(source.isStreamed, isTrue);
    expect(source.size, size);
    const boundary = 256 * 1024 - 4;
    final crossing = source.readSync(boundary, 16);
    expect(crossing.length, 16);
    expect(crossing.first, boundary % 251);
    expect(crossing.last, (boundary + 15) % 251);
    final tail = source.readSync(size - 8, 64);
    expect(tail.length, 8);
    expect(tail.last, (size - 1) % 251);
  });

  test('real archives on disk open and read members', () async {
    final tar = Uint8List.fromList(
      TarEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.bytes('a.txt', utf8.encode('tar member'))),
      ),
    );

    final cases = <String, Uint8List>{
      'sample.zip': _archiveBytes(),
      'sample.tar.gz': Uint8List.fromList(const GZipEncoder().encode(tar)),
      'sample.tar.bz2': Uint8List.fromList(BZip2Encoder().encode(tar)),
      'sample.tar.xz': Uint8List.fromList(XZEncoder().encode(tar)),
      'sample.tar.zst': Uint8List.fromList(ZstdEncoder().encode(tar)),
    };

    for (final entry in cases.entries) {
      final bytes = await _writeAndRead(dir, entry.key, entry.value);
      final archive = await openViewerArchive(bytes, name: entry.key);
      expect(archive.members.where((m) => m.isFile), isNotEmpty,
          reason: entry.key);
      final member = archive.members.firstWhere(
        (m) => m.isFile && (m.name == 'a.txt' || m.name == 'readme.txt'),
      );
      final content = await archive.readMember(member);
      expect(content, isNotEmpty, reason: entry.key);
      await archive.close();
    }
  });

  test('real 7z and RAR fixtures open from disk', () async {
    for (final fixture in ['sample.7z', 'sample.rar']) {
      final source = File('test/fixtures/archives/$fixture');
      final bytes = await _writeAndRead(
        dir,
        fixture,
        await source.readAsBytes(),
      );

      final archive = await openViewerArchive(bytes, name: fixture);
      expect(archive.members.where((m) => m.isFile), isNotEmpty,
          reason: fixture);
      final member = archive.members.firstWhere((m) => m.isFile);
      final content = await archive.readMember(member);
      expect(content.length, member.size, reason: fixture);
      await archive.close();
    }
  });

  test('real encrypted archives unlock with the password from disk', () async {
    final source = File('test/fixtures/archives/header_encrypted.7z');
    final bytes = await _writeAndRead(
      dir,
      'private.7z',
      await source.readAsBytes(),
    );

    await expectLater(
      openViewerArchive(bytes, name: 'private.7z'),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );

    final archive = await openViewerArchive(
      bytes,
      name: 'private.7z',
      password: 'secret',
    );
    final member = archive.members.firstWhere((m) => m.isFile);
    expect(utf8.decode(await archive.readMember(member)).trim(), 'hello, 7z!');
    await archive.close();
  });

  test('real single-file .gz written to disk expands', () async {
    final gz = Uint8List.fromList(
      const GZipEncoder().encode(utf8.encode('live gzip payload')),
    );
    final bytes = await _writeAndRead(dir, 'notes.txt.gz', gz);

    expect(isSingleCompressedFile('notes.txt.gz'), isTrue);
    final expanded = decompressSingleFile(bytes, 'notes.txt.gz');
    expect(expanded.innerName, 'notes.txt');
    expect(utf8.decode(expanded.data), 'live gzip payload');
  });

  test('real 7z/RAR headers are detected without the extension', () async {
    final seven = await File(
      'test/fixtures/archives/sample.7z',
    ).readAsBytes();
    final rar = await File('test/fixtures/archives/sample.rar').readAsBytes();

    expect(
      _svc.detectMode('mystery', header: seven.sublist(0, 16)),
      ViewerMode.archive,
    );
    expect(
      _svc.detectMode('mystery', header: rar.sublist(0, 16)),
      ViewerMode.archive,
    );
  });
}
