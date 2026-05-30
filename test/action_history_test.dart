// test/action_history_test.dart
//
// Unit tests for ActionHistoryService and ActionHistoryNotifier.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:crisp_cloud/providers/action_history_provider.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ActionHistoryService
  // ---------------------------------------------------------------------------
  group('ActionHistoryService', () {
    late ActionHistoryService svc;

    setUp(() {
      svc = ActionHistoryService();
    });

    // --- record / getHistory ---

    test('history is empty initially', () {
      expect(svc.history, isEmpty);
    });

    test('record adds action and history returns most-recent first', () {
      svc.recordNew(type: ActionType.createFolder, originalPath: '/a', provider: 'local');
      svc.recordNew(type: ActionType.createFolder, originalPath: '/b', provider: 'local');
      expect(svc.history.length, 2);
      expect(svc.history.first.originalPath, '/b'); // most recent
    });

    test('recordNew returns a non-empty id', () {
      final id = svc.recordNew(type: ActionType.delete, originalPath: '/x', provider: 'local');
      expect(id, isNotEmpty);
    });

    test('history size is capped at 50', () {
      for (var i = 0; i < 60; i++) {
        svc.recordNew(type: ActionType.createFolder, originalPath: '/f$i', provider: 'local');
      }
      expect(svc.history.length, 50);
    });

    test('oldest entries are dropped when cap is exceeded', () {
      for (var i = 0; i < 51; i++) {
        svc.recordNew(type: ActionType.createFolder, originalPath: '/f$i', provider: 'local');
      }
      // /f0 (the very first) should have been evicted
      expect(svc.history.any((a) => a.originalPath == '/f0'), isFalse);
      // /f50 (the last) should still be present
      expect(svc.history.any((a) => a.originalPath == '/f50'), isTrue);
    });

    test('clear empties history', () {
      svc.recordNew(type: ActionType.delete, originalPath: '/x', provider: 'local');
      svc.clear();
      expect(svc.history, isEmpty);
    });

    // --- canUndo ---

    test('canUndo returns false for local delete', () {
      svc.recordNew(type: ActionType.delete, originalPath: '/x', provider: 'local');
      expect(svc.canUndo(svc.history.first), isFalse);
    });

    test('canUndo returns true for remote delete', () {
      svc.recordNew(type: ActionType.delete, originalPath: '/x', provider: 'filen');
      expect(svc.canUndo(svc.history.first), isTrue);
    });

    test('canUndo returns true for rename', () {
      svc.recordNew(type: ActionType.rename, originalPath: '/a/old', newPath: '/a/new', provider: 'local');
      expect(svc.canUndo(svc.history.first), isTrue);
    });

    test('canUndo returns true for move', () {
      svc.recordNew(type: ActionType.move, originalPath: '/src/f', newPath: '/dst/f', provider: 'local');
      expect(svc.canUndo(svc.history.first), isTrue);
    });

    test('canUndo returns true for copy', () {
      svc.recordNew(type: ActionType.copy, originalPath: '/dst/f', newPath: '/src/f', provider: 'local');
      expect(svc.canUndo(svc.history.first), isTrue);
    });

    test('canUndo returns true for createFolder', () {
      svc.recordNew(type: ActionType.createFolder, originalPath: '/new_dir', provider: 'local');
      expect(svc.canUndo(svc.history.first), isTrue);
    });

    // --- undo: action not found ---

    test('undo returns failure for unknown id', () async {
      final result = await svc.undo('nonexistent-id', const UndoContext());
      expect(result.success, isFalse);
      expect(result.message, contains('not found'));
    });

    // --- undo: createFolder (local) ---

    test('undo createFolder deletes the local directory', () async {
      final dir = await Directory.systemTemp.createTemp('crisp_test_');
      try {
        svc.recordNew(type: ActionType.createFolder, originalPath: dir.path, provider: 'local');
        expect(await dir.exists(), isTrue);

        final result = await svc.undo(svc.history.first.id, const UndoContext());
        expect(result.success, isTrue);
        expect(await dir.exists(), isFalse);
        // Should be removed from history after successful undo
        expect(svc.history, isEmpty);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    // --- undo: copy (local) ---

    test('undo copy deletes the copy file', () async {
      final tmpDir = await Directory.systemTemp.createTemp('crisp_copy_test_');
      final copyFile = File('${tmpDir.path}/copy.txt');
      await copyFile.writeAsString('data');
      try {
        // originalPath = the copy, newPath = source (per ActionHistoryService convention)
        svc.recordNew(
          type: ActionType.copy,
          originalPath: copyFile.path,
          newPath: '/src/copy.txt',
          provider: 'local',
        );

        final result = await svc.undo(svc.history.first.id, const UndoContext());
        expect(result.success, isTrue);
        expect(await copyFile.exists(), isFalse);
      } finally {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      }
    });

    // --- undo: rename (local) ---

    test('undo rename renames back to original name', () async {
      final tmpDir = await Directory.systemTemp.createTemp('crisp_rename_test_');
      final newFile = File('${tmpDir.path}/new.txt');
      await newFile.writeAsString('content');
      final originalPath = '${tmpDir.path}/old.txt';
      try {
        svc.recordNew(
          type: ActionType.rename,
          originalPath: originalPath,
          newPath: newFile.path,
          provider: 'local',
          metadata: {'oldName': 'old.txt', 'newName': 'new.txt'},
        );

        final result = await svc.undo(svc.history.first.id, const UndoContext());
        expect(result.success, isTrue);
        expect(await File(originalPath).exists(), isTrue);
        expect(await newFile.exists(), isFalse);
      } finally {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      }
    });

    // --- undo: move (local) ---

    test('undo move moves file back to original location', () async {
      final tmpDir = await Directory.systemTemp.createTemp('crisp_move_test_');
      final srcDir = Directory('${tmpDir.path}/src');
      final dstDir = Directory('${tmpDir.path}/dst');
      await srcDir.create();
      await dstDir.create();
      final movedFile = File('${dstDir.path}/file.txt');
      await movedFile.writeAsString('data');
      final originalPath = '${srcDir.path}/file.txt';
      try {
        svc.recordNew(
          type: ActionType.move,
          originalPath: originalPath,
          newPath: movedFile.path,
          provider: 'local',
        );

        final result = await svc.undo(svc.history.first.id, const UndoContext());
        expect(result.success, isTrue);
        expect(await File(originalPath).exists(), isTrue);
        expect(await movedFile.exists(), isFalse);
      } finally {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      }
    });

    // --- undo: delete (remote with trash restore) ---

    test('undo delete calls restoreFromTrash callback', () async {
      String? restoredPath;
      final ctx = UndoContext(
        restoreFromTrash: (path) async { restoredPath = path; },
      );
      svc.recordNew(type: ActionType.delete, originalPath: '/remote/file.txt', provider: 'filen');

      final result = await svc.undo(svc.history.first.id, ctx);
      expect(result.success, isTrue);
      expect(restoredPath, equals('/remote/file.txt'));
    });

    // --- undo: rename (remote) ---

    test('undo rename calls remoteRename callback with original name', () async {
      String? renamedFrom;
      String? renamedTo;
      final ctx = UndoContext(
        remoteRename: (current, name) async {
          renamedFrom = current;
          renamedTo = name;
        },
      );
      svc.recordNew(
        type: ActionType.rename,
        originalPath: '/docs/old.txt',
        newPath: '/docs/new.txt',
        provider: 'filen',
      );

      final result = await svc.undo(svc.history.first.id, ctx);
      expect(result.success, isTrue);
      expect(renamedFrom, equals('/docs/new.txt'));
      expect(renamedTo, equals('old.txt'));
    });
  });

  // ---------------------------------------------------------------------------
  // ActionHistoryNotifier
  // ---------------------------------------------------------------------------
  group('ActionHistoryNotifier', () {
    late ActionHistoryNotifier notifier;

    setUp(() {
      notifier = ActionHistoryNotifier();
    });

    test('history is empty initially', () {
      expect(notifier.history, isEmpty);
    });

    test('lastAction is null when history is empty', () {
      expect(notifier.lastAction, isNull);
    });

    test('record adds entry and lastAction reflects it', () {
      notifier.record(
        type: ActionType.createFolder,
        originalPath: '/dir',
        provider: 'local',
      );
      expect(notifier.history.length, 1);
      expect(notifier.lastAction?.type, ActionType.createFolder);
    });

    test('clear empties the notifier history', () {
      notifier.record(type: ActionType.delete, originalPath: '/f', provider: 'local');
      notifier.clear();
      expect(notifier.history, isEmpty);
      expect(notifier.lastAction, isNull);
    });

    test('undoLast returns null when history is empty', () async {
      final result = await notifier.undoLast(const UndoContext());
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ActionRecord.description
  // ---------------------------------------------------------------------------
  group('ActionRecord.description', () {
    ActionRecord make(ActionType type, {String orig = '/dir/file', String? newP}) =>
        ActionRecord(
          id: 'x',
          timestamp: DateTime.now(),
          type: type,
          originalPath: orig,
          newPath: newP,
          provider: 'local',
        );

    test('delete description names the file', () {
      expect(make(ActionType.delete).description, contains('file'));
    });

    test('rename description includes both names', () {
      final d = make(ActionType.rename, orig: '/dir/old.txt', newP: '/dir/new.txt').description;
      expect(d, contains('old.txt'));
      expect(d, contains('new.txt'));
    });

    test('move description mentions Moved', () {
      expect(make(ActionType.move).description, startsWith('Moved'));
    });

    test('copy description mentions Copied', () {
      expect(make(ActionType.copy).description, startsWith('Copied'));
    });

    test('createFolder description mentions folder name', () {
      expect(make(ActionType.createFolder, orig: '/dir/myfolder').description, contains('myfolder'));
    });
  });
}
