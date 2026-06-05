// test/fkey_action_test.dart
//
// Tests for FKeyActionService, FKeyAction enum, and FKeyContext.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fkey_action_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';

// ---------------------------------------------------------------------------
// Minimal stub CloudStorageClient for tests
// ---------------------------------------------------------------------------

class _StubClient extends CloudStorageClient {
  @override
  String get providerName => 'Dropbox';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => false;

  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {}

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {}

  @override
  String? get userId => null;

  @override
  String? get bucketId => null;

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async =>
      {'folders': <dynamic>[], 'files': <dynamic>[]};

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {}

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {}

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async =>
      Uint8List(0);

  @override
  Future<void> createFolderPath(String path) async {}

  @override
  Future<void> deletePath(String path) async {}

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}

  @override
  Future<void> renamePath(String path, String newName) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _service = FKeyActionService();

const _localLeft = LocalPanelSource('/home/user');
const _localRight = LocalPanelSource('/tmp');

FileItem _file(String name, {bool isFolder = false}) => FileItem(
      name: name,
      path: '/home/user/$name',
      isFolder: isFolder,
    );

FKeyContext _ctx({
  PanelSource? active,
  PanelSource? opposite,
  List<FileItem>? selected,
}) =>
    FKeyContext(
      activePanel: active ?? _localLeft,
      oppositePanel: opposite ?? _localRight,
      selectedFiles: selected ?? const [],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- All 6 actions have labels ------------------------------------------

  group('FKeyAction labels', () {
    test('all 6 actions have non-empty labels', () {
      for (final action in FKeyAction.values) {
        final label = _service.getActionLabel(action);
        expect(label, isNotEmpty, reason: '$action should have a label');
      }
    });

    test('view label', () => expect(_service.getActionLabel(FKeyAction.view), 'View'));
    test('edit label', () => expect(_service.getActionLabel(FKeyAction.edit), 'Edit'));
    test('copy label', () => expect(_service.getActionLabel(FKeyAction.copy), 'Copy'));
    test('move label', () => expect(_service.getActionLabel(FKeyAction.move), 'Move'));
    test('mkdir label', () => expect(_service.getActionLabel(FKeyAction.mkdir), 'MkDir'));
    test('delete label', () => expect(_service.getActionLabel(FKeyAction.delete), 'Delete'));
  });

  // ---- All 6 actions have shortcuts F3-F8 ----------------------------------

  group('FKeyAction shortcuts', () {
    test('all 6 actions have non-empty shortcuts', () {
      for (final action in FKeyAction.values) {
        final shortcut = _service.getActionShortcut(action);
        expect(shortcut, isNotEmpty, reason: '$action should have a shortcut');
      }
    });

    test('view shortcut is F3', () => expect(_service.getActionShortcut(FKeyAction.view), 'F3'));
    test('edit shortcut is F4', () => expect(_service.getActionShortcut(FKeyAction.edit), 'F4'));
    test('copy shortcut is F5', () => expect(_service.getActionShortcut(FKeyAction.copy), 'F5'));
    test('move shortcut is F6', () => expect(_service.getActionShortcut(FKeyAction.move), 'F6'));
    test('mkdir shortcut is F7', () => expect(_service.getActionShortcut(FKeyAction.mkdir), 'F7'));
    test('delete shortcut is F8', () => expect(_service.getActionShortcut(FKeyAction.delete), 'F8'));

    test('F-key numbers are 3–8 in order', () {
      final numbers = FKeyAction.values.map(_service.getFKeyNumber).toList();
      expect(numbers, [3, 4, 5, 6, 7, 8]);
    });

    test('shortcuts follow Fn pattern', () {
      for (final action in FKeyAction.values) {
        final shortcut = _service.getActionShortcut(action);
        expect(shortcut, matches(RegExp(r'^F\d$')));
      }
    });
  });

  // ---- Availability: no selection ------------------------------------------

  group('Action availability — no selection', () {
    final ctxNoSelection = _ctx(selected: []);

    test('copy unavailable with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.copy, ctxNoSelection), isFalse);
    });

    test('move unavailable with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.move, ctxNoSelection), isFalse);
    });

    test('delete unavailable with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.delete, ctxNoSelection), isFalse);
    });

    test('view unavailable with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.view, ctxNoSelection), isFalse);
    });

    test('edit unavailable with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.edit, ctxNoSelection), isFalse);
    });

    test('mkdir always available with no selection', () {
      expect(_service.isActionAvailable(FKeyAction.mkdir, ctxNoSelection), isTrue);
    });
  });

  // ---- Availability: with selection ----------------------------------------

  group('Action availability — with selection', () {
    final ctxOneFile = _ctx(selected: [_file('photo.jpg')]);
    final ctxMultiple = _ctx(selected: [_file('a.txt'), _file('b.txt')]);
    final ctxFolder = _ctx(selected: [_file('docs', isFolder: true)]);

    test('copy available with 1 file', () {
      expect(_service.isActionAvailable(FKeyAction.copy, ctxOneFile), isTrue);
    });

    test('move available with multiple files', () {
      expect(_service.isActionAvailable(FKeyAction.move, ctxMultiple), isTrue);
    });

    test('delete available with 1 file', () {
      expect(_service.isActionAvailable(FKeyAction.delete, ctxOneFile), isTrue);
    });

    test('view available with exactly 1 non-folder file', () {
      expect(_service.isActionAvailable(FKeyAction.view, ctxOneFile), isTrue);
    });

    test('edit available with exactly 1 non-folder file', () {
      expect(_service.isActionAvailable(FKeyAction.edit, ctxOneFile), isTrue);
    });

    test('view unavailable for a folder', () {
      expect(_service.isActionAvailable(FKeyAction.view, ctxFolder), isFalse);
    });

    test('edit unavailable for a folder', () {
      expect(_service.isActionAvailable(FKeyAction.edit, ctxFolder), isFalse);
    });

    test('view unavailable when multiple files selected', () {
      expect(_service.isActionAvailable(FKeyAction.view, ctxMultiple), isFalse);
    });

    test('mkdir always available regardless of selection', () {
      expect(_service.isActionAvailable(FKeyAction.mkdir, ctxOneFile), isTrue);
      expect(_service.isActionAvailable(FKeyAction.mkdir, ctxMultiple), isTrue);
    });
  });

  // ---- F3 View opens viewer ------------------------------------------------

  group('F3 View', () {
    test('returns FKeyOpenViewer for single file', () {
      final ctx = _ctx(selected: [_file('readme.txt')]);
      final result = _service.executeAction(FKeyAction.view, ctx);
      expect(result, isA<FKeyOpenViewer>());
    });

    test('viewer receives the selected file', () {
      final file = _file('image.png');
      final ctx = _ctx(selected: [file]);
      final result = _service.executeAction(FKeyAction.view, ctx) as FKeyOpenViewer;
      expect(result.file, file);
    });

    test('viewer receives active panel source', () {
      const activePanel = LocalPanelSource('/docs');
      final ctx = _ctx(active: activePanel, selected: [_file('note.txt')]);
      final result = _service.executeAction(FKeyAction.view, ctx) as FKeyOpenViewer;
      expect(result.source, activePanel);
    });
  });

  // ---- F4 Edit opens editor ------------------------------------------------

  group('F4 Edit', () {
    test('returns FKeyOpenEditor for single file', () {
      final ctx = _ctx(selected: [_file('code.dart')]);
      final result = _service.executeAction(FKeyAction.edit, ctx);
      expect(result, isA<FKeyOpenEditor>());
    });

    test('editor receives the selected file', () {
      final file = _file('main.dart');
      final ctx = _ctx(selected: [file]);
      final result = _service.executeAction(FKeyAction.edit, ctx) as FKeyOpenEditor;
      expect(result.file, file);
    });
  });

  // ---- F5 Copy direction (active → opposite) --------------------------------

  group('F5 Copy direction', () {
    test('returns FKeyNeedsConfirm', () {
      final ctx = _ctx(selected: [_file('photo.jpg')]);
      final result = _service.executeAction(FKeyAction.copy, ctx);
      expect(result, isA<FKeyNeedsConfirm>());
    });

    test('confirm message mentions destination (opposite) panel', () {
      const oppositeSrc = LocalPanelSource('/backup');
      final ctx = _ctx(
        active: const LocalPanelSource('/home'),
        opposite: oppositeSrc,
        selected: [_file('data.csv')],
      );
      final result = _service.executeAction(FKeyAction.copy, ctx) as FKeyNeedsConfirm;
      expect(result.message, contains(oppositeSrc.displayName));
    });

    test('copyDirectionLabel shows active → opposite', () {
      final ctx = FKeyContext(
        activePanel: const LocalPanelSource('/src'),
        oppositePanel: RemotePanelSource(
          providerName: 'Dropbox',
          client: _StubClient(),
          path: '/',
        ),
        selectedFiles: const [],
      );
      final label = _service.copyDirectionLabel(ctx);
      expect(label, contains('Local'));
      expect(label, contains('Dropbox'));
      expect(label, contains('→'));
    });

    test('confirm completes with FKeySuccess', () async {
      final ctx = _ctx(selected: [_file('a.txt')]);
      final confirm = _service.executeAction(FKeyAction.copy, ctx) as FKeyNeedsConfirm;
      final result = await confirm.onConfirm();
      expect(result, isA<FKeySuccess>());
    });

    test('cancel returns FKeyCancelled', () {
      final ctx = _ctx(selected: [_file('a.txt')]);
      final confirm = _service.executeAction(FKeyAction.copy, ctx) as FKeyNeedsConfirm;
      final cancelled = confirm.onCancel();
      expect(cancelled, isA<FKeyCancelled>());
    });
  });

  // ---- F6 Move = copy + delete semantics -----------------------------------

  group('F6 Move', () {
    test('returns FKeyNeedsConfirm', () {
      final ctx = _ctx(selected: [_file('doc.pdf')]);
      final result = _service.executeAction(FKeyAction.move, ctx);
      expect(result, isA<FKeyNeedsConfirm>());
    });

    test('move message mentions destination', () {
      const oppositeSrc = LocalPanelSource('/archive');
      final ctx = _ctx(
        opposite: oppositeSrc,
        selected: [_file('report.pdf')],
      );
      final result = _service.executeAction(FKeyAction.move, ctx) as FKeyNeedsConfirm;
      expect(result.message, contains(oppositeSrc.displayName));
    });

    test('move confirm completes with FKeySuccess', () async {
      final ctx = _ctx(selected: [_file('x.txt')]);
      final confirm = _service.executeAction(FKeyAction.move, ctx) as FKeyNeedsConfirm;
      final result = await confirm.onConfirm();
      expect(result, isA<FKeySuccess>());
    });
  });

  // ---- F7 MkDir ------------------------------------------------------------

  group('F7 MkDir', () {
    test('returns FKeyNeedsPrompt', () {
      final ctx = _ctx();
      final result = _service.executeAction(FKeyAction.mkdir, ctx);
      expect(result, isA<FKeyNeedsPrompt>());
    });

    test('prompt has a title', () {
      final ctx = _ctx();
      final prompt = _service.executeAction(FKeyAction.mkdir, ctx) as FKeyNeedsPrompt;
      expect(prompt.title, isNotEmpty);
    });

    test('prompt has a hint', () {
      final ctx = _ctx();
      final prompt = _service.executeAction(FKeyAction.mkdir, ctx) as FKeyNeedsPrompt;
      expect(prompt.hint, isNotEmpty);
    });

    test('mkdir with valid name returns FKeySuccess', () async {
      final ctx = _ctx();
      final prompt = _service.executeAction(FKeyAction.mkdir, ctx) as FKeyNeedsPrompt;
      final result = await prompt.onConfirm('NewFolder');
      expect(result, isA<FKeySuccess>());
      expect((result as FKeySuccess).message, contains('NewFolder'));
    });

    test('mkdir with empty name returns FKeyError', () async {
      final ctx = _ctx();
      final prompt = _service.executeAction(FKeyAction.mkdir, ctx) as FKeyNeedsPrompt;
      final result = await prompt.onConfirm('  ');
      expect(result, isA<FKeyError>());
    });

    test('mkdir always available when no files selected', () {
      final ctx = _ctx(selected: []);
      expect(_service.isActionAvailable(FKeyAction.mkdir, ctx), isTrue);
    });
  });

  // ---- F8 Delete -----------------------------------------------------------

  group('F8 Delete', () {
    test('returns FKeyNeedsConfirm', () {
      final ctx = _ctx(selected: [_file('old.log')]);
      final result = _service.executeAction(FKeyAction.delete, ctx);
      expect(result, isA<FKeyNeedsConfirm>());
    });

    test('delete message mentions file count', () {
      final ctx = _ctx(selected: [_file('a.txt'), _file('b.txt')]);
      final confirm = _service.executeAction(FKeyAction.delete, ctx) as FKeyNeedsConfirm;
      expect(confirm.message, contains('2'));
    });

    test('delete message mentions filename for single file', () {
      final ctx = _ctx(selected: [_file('important.pdf')]);
      final confirm = _service.executeAction(FKeyAction.delete, ctx) as FKeyNeedsConfirm;
      expect(confirm.message, contains('important.pdf'));
    });

    test('delete confirm completes with FKeySuccess', () async {
      final ctx = _ctx(selected: [_file('temp.txt')]);
      final confirm = _service.executeAction(FKeyAction.delete, ctx) as FKeyNeedsConfirm;
      final result = await confirm.onConfirm();
      expect(result, isA<FKeySuccess>());
    });

    test('delete cancel returns FKeyCancelled', () {
      final ctx = _ctx(selected: [_file('temp.txt')]);
      final confirm = _service.executeAction(FKeyAction.delete, ctx) as FKeyNeedsConfirm;
      expect(confirm.onCancel(), isA<FKeyCancelled>());
    });

    test('execute delete with no selection returns FKeyError', () {
      final ctx = _ctx(selected: []);
      final result = _service.executeAction(FKeyAction.delete, ctx);
      expect(result, isA<FKeyError>());
    });
  });

  // ---- FKeyContext helpers --------------------------------------------------

  group('FKeyContext', () {
    test('hasSelection is false with empty list', () {
      final ctx = _ctx(selected: []);
      expect(ctx.hasSelection, isFalse);
    });

    test('hasSelection is true with one file', () {
      final ctx = _ctx(selected: [_file('a.txt')]);
      expect(ctx.hasSelection, isTrue);
    });

    test('hasSingleFile is false for folder', () {
      final ctx = _ctx(selected: [_file('dir', isFolder: true)]);
      expect(ctx.hasSingleFile, isFalse);
    });

    test('hasSingleFile is false for multiple files', () {
      final ctx = _ctx(selected: [_file('a.txt'), _file('b.txt')]);
      expect(ctx.hasSingleFile, isFalse);
    });

    test('hasSingleFile is true for exactly one non-folder file', () {
      final ctx = _ctx(selected: [_file('a.txt')]);
      expect(ctx.hasSingleFile, isTrue);
    });
  });
}
