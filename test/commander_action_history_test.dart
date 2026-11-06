import 'dart:async';

import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String recordRename(
    ActionHistoryService history,
    String name, {
    Future<UndoResult> Function()? undoAction,
  }) => history.recordNew(
    type: ActionType.rename,
    originalPath: '/$name',
    newPath: '/${name}_new',
    provider: 'Cloud',
    undoAction: undoAction ?? () async => const UndoResult.success('Restored'),
  );

  test('clearing history during undo does not turn a completed mutation into failure', () async {
    final history = ActionHistoryService();
    final completion = Completer<UndoResult>();
    final id = recordRename(history, 'pending', undoAction: () => completion.future);
    final pending = history.undo(id, const UndoContext());
    history.clear();
    completion.complete(const UndoResult.success('Restored'));
    expect((await pending).success, isTrue);
    expect(history.history, isEmpty);
  });

  test('a new action recorded after clearing pending history is preserved', () async {
    final history = ActionHistoryService();
    final completion = Completer<UndoResult>();
    final id = recordRename(history, 'pending', undoAction: () => completion.future);
    final pending = history.undo(id, const UndoContext());
    history.clear();
    final fresh = recordRename(history, 'fresh');
    completion.complete(const UndoResult.success('Restored'));
    expect((await pending).success, isTrue);
    expect(history.history.map((action) => action.id), [fresh]);
  });

  test('history trimming during undo cannot remove a newer action', () async {
    final history = ActionHistoryService();
    for (var index = 0; index < 49; index++) {
      recordRename(history, 'older-$index');
    }
    final completion = Completer<UndoResult>();
    final id = recordRename(history, 'pending', undoAction: () => completion.future);
    final pending = history.undo(id, const UndoContext());
    recordRename(history, 'newer-one');
    recordRename(history, 'newer-two');
    final expected = history.history
        .where((action) => action.id != id)
        .map((action) => action.id)
        .toList();
    completion.complete(const UndoResult.success('Restored'));
    expect((await pending).success, isTrue);
    expect(history.history.map((action) => action.id), expected);
    expect(history.history, hasLength(49));
  });

  test('an action trimmed out while undoing does not remove any surviving history', () async {
    final history = ActionHistoryService();
    final completion = Completer<UndoResult>();
    final id = recordRename(history, 'oldest', undoAction: () => completion.future);
    final pending = history.undo(id, const UndoContext());
    for (var index = 0; index < 50; index++) {
      recordRename(history, 'fresh-$index');
    }
    final expected = history.history.map((action) => action.id).toList();
    expect(expected, isNot(contains(id)));
    completion.complete(const UndoResult.success('Restored'));
    expect((await pending).success, isTrue);
    expect(history.history.map((action) => action.id), expected);
    expect(history.history, hasLength(50));
  });

  test('overlapping undo requests for one action invoke its mutation once', () async {
    final history = ActionHistoryService();
    final completion = Completer<UndoResult>();
    var calls = 0;
    final id = recordRename(history, 'pending', undoAction: () {
      calls++;
      return completion.future;
    });
    final pending = history.undo(id, const UndoContext());
    expect(history.canUndo(history.history.single), isFalse);
    final duplicate = await history.undo(id, const UndoContext());
    expect(duplicate.success, isFalse);
    expect(duplicate.message, contains('already being undone'));
    expect(calls, 1);
    completion.complete(const UndoResult.success('Restored'));
    expect((await pending).success, isTrue);
    expect(history.history, isEmpty);
  });

  test('independent undo actions can finish concurrently without stale indices', () async {
    final history = ActionHistoryService();
    final firstCompletion = Completer<UndoResult>();
    final secondCompletion = Completer<UndoResult>();
    final calls = <String>[];
    final first = recordRename(history, 'first', undoAction: () {
      calls.add('first');
      return firstCompletion.future;
    });
    final second = recordRename(history, 'second', undoAction: () {
      calls.add('second');
      return secondCompletion.future;
    });
    final firstPending = history.undo(first, const UndoContext());
    final secondPending = history.undo(second, const UndoContext());
    expect(calls, ['first', 'second']);
    firstCompletion.complete(const UndoResult.success('First restored'));
    expect((await firstPending).success, isTrue);
    expect(history.history.map((action) => action.id), [second]);
    secondCompletion.complete(const UndoResult.success('Second restored'));
    expect((await secondPending).success, isTrue);
    expect(history.history, isEmpty);
  });

  test('a failed undo releases its per-action lock for a later retry', () async {
    final history = ActionHistoryService();
    var calls = 0;
    final id = recordRename(history, 'retry', undoAction: () async {
      calls++;
      if (calls == 1) throw StateError('Temporary storage failure');
      return const UndoResult.success('Restored');
    });
    expect((await history.undo(id, const UndoContext())).success, isFalse);
    expect(history.canUndo(history.history.single), isTrue);
    expect((await history.undo(id, const UndoContext())).success, isTrue);
    expect(calls, 2);
    expect(history.history, isEmpty);
  });

  test(
    'captured rename undo never falls back to the active pane client',
    () async {
      final history = ActionHistoryService();
      var originalCalls = 0;
      var wrongAccountCalls = 0;
      final id = history.recordNew(
        type: ActionType.rename,
        originalPath: '/photos/old.jpg',
        newPath: '/photos/new.jpg',
        provider: 'Cloud',
        isCurrent: () => true,
        undoAction: () async {
          originalCalls++;
          return const UndoResult.success('Renamed back');
        },
      );
      final result = await history.undo(
        id,
        UndoContext(
          remoteRename: (_, _) async {
            wrongAccountCalls++;
          },
        ),
      );
      expect(result.success, isTrue);
      expect(originalCalls, 1);
      expect(wrongAccountCalls, 0);
      expect(history.history, isEmpty);
    },
  );

  test(
    'account change blocks a recorded rename and preserves history',
    () async {
      final history = ActionHistoryService();
      var current = true;
      var calls = 0;
      final id = history.recordNew(
        type: ActionType.rename,
        originalPath: '/old',
        newPath: '/new',
        provider: 'Cloud',
        isCurrent: () => current,
        undoAction: () async {
          calls++;
          return const UndoResult.success('Done');
        },
      );
      expect(history.canUndo(history.history.single), isTrue);
      current = false;
      expect(history.canUndo(history.history.single), isFalse);
      expect((await history.undo(id, const UndoContext())).success, isFalse);
      expect(calls, 0);
      expect(history.history, hasLength(1));
    },
  );

  test(
    'collision failure from a captured undo remains actionable in history',
    () async {
      final history = ActionHistoryService();
      final id = history.recordNew(
        type: ActionType.rename,
        originalPath: '/old',
        newPath: '/new',
        provider: 'local',
        isCurrent: () => true,
        undoAction: () async =>
            throw StateError('Original name is now occupied'),
      );
      final result = await history.undo(id, const UndoContext());
      expect(result.success, isFalse);
      expect(result.message, contains('occupied'));
      expect(history.history, hasLength(1));
    },
  );
}
