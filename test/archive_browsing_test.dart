// test/archive_browsing_test.dart
//
// Tests for archive-as-folder browsing (Phase 1.1).

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';

void main() {
  group('ArchiveService.isArchive', () {
    test('recognises .zip', () {
      expect(ArchiveService.isArchive('foo.zip'), isTrue);
      expect(ArchiveService.isArchive('FOO.ZIP'), isTrue);
    });

    test('recognises .tar.gz and .tgz', () {
      expect(ArchiveService.isArchive('data.tar.gz'), isTrue);
      expect(ArchiveService.isArchive('data.tgz'), isTrue);
    });

    test('recognises .tar.bz2 and .tbz2', () {
      expect(ArchiveService.isArchive('data.tar.bz2'), isTrue);
      expect(ArchiveService.isArchive('data.tbz2'), isTrue);
    });

    test('recognises .tar', () {
      expect(ArchiveService.isArchive('data.tar'), isTrue);
    });

    test('rejects non-archive files', () {
      expect(ArchiveService.isArchive('readme.txt'), isFalse);
      expect(ArchiveService.isArchive('photo.jpg'), isFalse);
    });
  });

  group('ArchiveService.listArchiveContents', () {
    late String tempDir;
    late String zipPath;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('archive_test_')).path;

      // Create a test ZIP with structure:
      // root.txt
      // subdir/nested.txt
      // subdir/deep/deep.txt
      final archive = Archive();
      archive.addFile(ArchiveFile('root.txt', 10, List.filled(10, 65)));
      archive.addFile(ArchiveFile('subdir/nested.txt', 20, List.filled(20, 66)));
      archive.addFile(ArchiveFile('subdir/deep/deep.txt', 5, List.filled(5, 67)));

      final zipBytes = ZipEncoder().encode(archive)!;
      zipPath = p.join(tempDir, 'test.zip');
      await File(zipPath).writeAsBytes(zipBytes);
    });

    tearDown(() async {
      await Directory(tempDir).delete(recursive: true);
    });

    test('lists root level entries', () async {
      final items = await ArchiveService.listArchiveContents(zipPath, '');
      final names = items.map((e) => e.name).toSet();
      expect(names, contains('root.txt'));
      expect(names, contains('subdir'));
      expect(items.firstWhere((i) => i.name == 'subdir').isFolder, isTrue);
      expect(items.firstWhere((i) => i.name == 'root.txt').isFolder, isFalse);
    });

    test('lists subdirectory entries', () async {
      final items = await ArchiveService.listArchiveContents(zipPath, 'subdir/');
      final names = items.map((e) => e.name).toSet();
      expect(names, contains('nested.txt'));
      expect(names, contains('deep'));
      expect(items.firstWhere((i) => i.name == 'deep').isFolder, isTrue);
    });

    test('lists deep subdirectory', () async {
      final items = await ArchiveService.listArchiveContents(zipPath, 'subdir/deep/');
      expect(items.length, 1);
      expect(items.first.name, 'deep.txt');
      expect(items.first.isFolder, isFalse);
    });

    test('file items have correct size', () async {
      final items = await ArchiveService.listArchiveContents(zipPath, '');
      final rootTxt = items.firstWhere((i) => i.name == 'root.txt');
      expect(rootTxt.size, 10);
    });
  });

  group('ArchiveService.extractArchiveEntry', () {
    late String tempDir;
    late String zipPath;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('extract_test_')).path;
      final archive = Archive();
      archive.addFile(ArchiveFile('hello.txt', 5, [72, 101, 108, 108, 111])); // "Hello"
      final zipBytes = ZipEncoder().encode(archive)!;
      zipPath = p.join(tempDir, 'test.zip');
      await File(zipPath).writeAsBytes(zipBytes);
    });

    tearDown(() async {
      await Directory(tempDir).delete(recursive: true);
    });

    test('extracts a single entry by path', () async {
      final bytes = await ArchiveService.extractArchiveEntry(zipPath, 'hello.txt');
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'Hello');
    });

    test('returns null for non-existent entry', () async {
      final bytes = await ArchiveService.extractArchiveEntry(zipPath, 'missing.txt');
      expect(bytes, isNull);
    });
  });

  group('PanelSourceService archive navigation', () {
    test('enterArchive creates ArchivePanelSource at root', () {
      const service = PanelSourceService();
      const parent = LocalPanelSource('/home/user');
      final source = service.enterArchive('/home/user/archive.zip', parent);
      expect(source.archivePath, '/home/user/archive.zip');
      expect(source.innerPath, '');
      expect(source.parent, parent);
      expect(source.isArchive, isTrue);
    });

    test('withPath navigates into subdirectory', () {
      const service = PanelSourceService();
      const parent = LocalPanelSource('/home/user');
      final root = service.enterArchive('/tmp/test.zip', parent);
      final sub = root.withPath('subdir/');
      expect(sub is ArchivePanelSource, isTrue);
      expect((sub as ArchivePanelSource).innerPath, 'subdir/');
      expect(sub.archivePath, '/tmp/test.zip');
    });

    test('exitToParent returns parent source', () {
      const service = PanelSourceService();
      const parent = LocalPanelSource('/home/user');
      final source = service.enterArchive('/tmp/test.zip', parent);
      final exited = service.exitToParent(source);
      expect(exited, parent);
    });
  });
}
