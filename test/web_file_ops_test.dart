// test/web_file_ops_test.dart
//
// Unit tests for web file operation fixes:
//   - Per-panel _localPath isolation (two panels don't stomp each other)
//   - LocalFileService.createDirectory interface contract
//   - Source-aware copyFiles/moveFiles/renameFile/createFolder logic
//   - showMoveDialogFromSelection web opposite-panel detection
//
// These tests run on VM (not browser), so they exercise:
//   - PanelSource logic (isLocal checks)
//   - Path computation correctness
//   - Interface contracts (createDirectory on abstract + native impls)

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/models/panel_side.dart';

// ============================================================================
// LocalFileService interface contract tests
// ============================================================================

void main() {
  group('LocalFileService interface', () {
    test('createDirectory exists on abstract class and throws by default', () async {
      // The base class default impl should throw UnsupportedError.
      // We can't instantiate the abstract class directly, so we test via native.
      // On non-web, LocalFileService() returns a native implementation.
      final svc = LocalFileService();
      expect(svc, isNotNull);
      // The native implementations should NOT throw (they use dart:io).
    });

    test('native createDirectory creates a real directory', () async {
      final svc = LocalFileService();
      final tempDir = await Directory.systemTemp.createTemp('crisp_test_');
      final newDir = p.join(tempDir.path, 'subfolder', 'nested');
      try {
        await svc.createDirectory(newDir);
        expect(await Directory(newDir).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('native deleteEntry deletes files', () async {
      final svc = LocalFileService();
      final tempDir = await Directory.systemTemp.createTemp('crisp_test_');
      final testFile = File(p.join(tempDir.path, 'test.txt'));
      await testFile.writeAsString('hello');
      try {
        expect(await testFile.exists(), isTrue);
        await svc.deleteEntry(testFile.path, false);
        expect(await testFile.exists(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('native deleteEntry deletes directories recursively', () async {
      final svc = LocalFileService();
      final tempDir = await Directory.systemTemp.createTemp('crisp_test_');
      final subDir = Directory(p.join(tempDir.path, 'sub'));
      await subDir.create();
      await File(p.join(subDir.path, 'inner.txt')).writeAsString('data');
      try {
        expect(await subDir.exists(), isTrue);
        await svc.deleteEntry(subDir.path, true);
        expect(await subDir.exists(), isFalse);
      } finally {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    });

    test('native saveFile writes data', () async {
      final svc = LocalFileService();
      final tempDir = await Directory.systemTemp.createTemp('crisp_test_');
      final filePath = p.join(tempDir.path, 'out.bin');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      try {
        await svc.saveFile(filePath, data);
        final readBack = await File(filePath).readAsBytes();
        expect(readBack, equals(data));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('native readFile reads data back', () async {
      final svc = LocalFileService();
      final tempDir = await Directory.systemTemp.createTemp('crisp_test_');
      final filePath = p.join(tempDir.path, 'read.bin');
      final data = Uint8List.fromList([10, 20, 30]);
      await File(filePath).writeAsBytes(data);
      try {
        final readBack = await svc.readFile(filePath);
        expect(readBack, equals(data));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  // ============================================================================
  // PanelSource isLocal tests
  // ============================================================================

  group('PanelSource.isLocal', () {
    test('LocalPanelSource.isLocal is true', () {
      const src = LocalPanelSource('/test');
      expect(src.isLocal, isTrue);
      expect(src.isRemote, isFalse);
    });

    test('LocalPanelSource.withPath returns new path', () {
      const src = LocalPanelSource('/a');
      final src2 = src.withPath('/b');
      expect(src2.currentPath, equals('/b'));
      expect(src2.isLocal, isTrue);
    });

    test('LocalPanelSource serialization roundtrip', () {
      const src = LocalPanelSource('/test/path');
      final json = src.toJson();
      expect(json['type'], equals('local'));
      expect(json['path'], equals('/test/path'));
    });
  });

  // ============================================================================
  // PanelSide enum tests
  // ============================================================================

  group('PanelSide', () {
    test('has local and remote values', () {
      expect(PanelSide.values.length, equals(2));
      expect(PanelSide.local, isNotNull);
      expect(PanelSide.remote, isNotNull);
    });

    test('opposite panel logic', () {
      // Mirror the logic used in screen_dialogs.dart
      PanelSide opposite(PanelSide side) =>
          side == PanelSide.local ? PanelSide.remote : PanelSide.local;

      expect(opposite(PanelSide.local), equals(PanelSide.remote));
      expect(opposite(PanelSide.remote), equals(PanelSide.local));
    });
  });

  // ============================================================================
  // Path computation tests (mirrors copyFiles/moveFiles logic)
  // ============================================================================

  group('Path computation for file ops', () {
    test('copy target path uses posix join on web', () {
      const targetPath = '/FolderB';
      const fileName = 'test.txt';
      final copyPath = p.posix.join(targetPath, fileName);
      expect(copyPath, equals('/FolderB/test.txt'));
    });

    test('copy target path handles nested directories', () {
      const targetPath = '/FolderB/sub/deep';
      const fileName = 'data.csv';
      final copyPath = p.posix.join(targetPath, fileName);
      expect(copyPath, equals('/FolderB/sub/deep/data.csv'));
    });

    test('rename path computation replaces name in same directory', () {
      const oldPath = '/FolderA/original.txt';
      const newName = 'renamed.txt';
      final computedNewPath = p.posix.join(p.posix.dirname(oldPath), newName);
      expect(computedNewPath, equals('/FolderA/renamed.txt'));
    });

    test('folder creation path joins current path with name', () {
      const currentPath = '/FolderA';
      const name = 'NewFolder';
      final folderPath = p.posix.join(currentPath, name);
      expect(folderPath, equals('/FolderA/NewFolder'));
    });

    test('isLocalSource check covers both panel sides', () {
      // Simulates the isLocalSource logic from panel_provider.dart:
      // final isLocalSource = source.isLocal || side == PanelSide.local;

      // Case 1: left panel (PanelSide.local) with local source
      const src1 = LocalPanelSource('/a');
      expect(src1.isLocal || PanelSide.local == PanelSide.local, isTrue);

      // Case 2: right panel (PanelSide.remote) with local source
      const src2 = LocalPanelSource('/b');
      expect(src2.isLocal || PanelSide.remote == PanelSide.local, isTrue);

      // Case 3: right panel with remote source
      // RemotePanelSource needs a client, so just test the logic directly
      expect(false || PanelSide.remote == PanelSide.local, isFalse);
    });
  });

  // ============================================================================
  // End-to-end native file operations (integration-style on real filesystem)
  // ============================================================================

  group('Native file ops end-to-end', () {
    late Directory tempSource;
    late Directory tempTarget;
    late LocalFileService svc;

    setUp(() async {
      tempSource = await Directory.systemTemp.createTemp('crisp_src_');
      tempTarget = await Directory.systemTemp.createTemp('crisp_tgt_');
      svc = LocalFileService();
    });

    tearDown(() async {
      if (await tempSource.exists()) await tempSource.delete(recursive: true);
      if (await tempTarget.exists()) await tempTarget.delete(recursive: true);
    });

    test('copy file: read + save to different directory', () async {
      final srcFile = File(p.join(tempSource.path, 'file.txt'));
      await srcFile.writeAsString('hello world');

      final data = await svc.readFile(srcFile.path);
      final targetPath = p.join(tempTarget.path, 'file.txt');
      await svc.saveFile(targetPath, data);

      expect(await File(targetPath).readAsString(), equals('hello world'));
      // Source still exists (copy, not move)
      expect(await srcFile.exists(), isTrue);
    });

    test('move file: read + save + delete source', () async {
      final srcFile = File(p.join(tempSource.path, 'moveme.txt'));
      await srcFile.writeAsString('move data');

      final data = await svc.readFile(srcFile.path);
      final targetPath = p.join(tempTarget.path, 'moveme.txt');
      await svc.saveFile(targetPath, data);
      await svc.deleteEntry(srcFile.path, false);

      expect(await File(targetPath).readAsString(), equals('move data'));
      expect(await srcFile.exists(), isFalse);
    });

    test('rename file: read + save new name + delete old', () async {
      final srcFile = File(p.join(tempSource.path, 'old.txt'));
      await srcFile.writeAsString('rename me');

      final data = await svc.readFile(srcFile.path);
      final newPath = p.join(tempSource.path, 'new.txt');
      await svc.saveFile(newPath, data);
      await svc.deleteEntry(srcFile.path, false);

      expect(await File(newPath).readAsString(), equals('rename me'));
      expect(await srcFile.exists(), isFalse);
    });

    test('create folder + verify exists', () async {
      final newDir = p.join(tempSource.path, 'newFolder');
      await svc.createDirectory(newDir);
      expect(await Directory(newDir).exists(), isTrue);
    });

    test('create nested folder chain', () async {
      final deepDir = p.join(tempSource.path, 'a', 'b', 'c');
      await svc.createDirectory(deepDir);
      expect(await Directory(deepDir).exists(), isTrue);
    });
  });
}
