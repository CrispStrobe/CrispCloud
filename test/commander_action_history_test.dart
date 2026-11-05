import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
