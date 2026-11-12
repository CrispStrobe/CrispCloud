import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/captured_file_target.dart';
import 'package:crisp_cloud/services/keepass_service.dart';
import 'package:crisp_cloud/widgets/keepass_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) => base64.decode(
  File('test/fixtures/keepass/$name.b64')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s'), ''),
);

Finder _key(String name) => find.byKey(ValueKey('keepass-$name'));

class _Target extends Fake implements CapturedFileTarget {
  _Target(this.bytes);
  Uint8List bytes;
  final writes = <Uint8List>[];
  Completer<void>? written;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<FileWriteOutcome> save(Uint8List bytes) async {
    this.bytes = Uint8List.fromList(bytes);
    writes.add(Uint8List.fromList(bytes));
    written?.complete();
    written = null;
    return FileWriteOutcome.savedOriginal;
  }
}

class _Harness {
  _Harness(Uint8List bytes) : target = _Target(bytes);
  final _Target target;
  KeePassSession? session;
  Completer<void>? unlocked;
  Future<KeePassSession> open(
    Uint8List bytes, {
    required String? password,
    Uint8List? keyFile,
  }) async {
    try {
      return session = await KeePassSession.open(
        bytes,
        password: password,
        keyFile: _fixture('demo.key'),
      );
    } finally {
      unlocked?.complete();
      unlocked = null;
    }
  }
}

Future<_Harness> _open(
  WidgetTester tester, {
  Uint8List? bytes,
  bool readOnly = false,
}) async {
  final harness = (await tester.runAsync(
    () async => _Harness(bytes ?? _fixture('demo.kdbx')),
  ))!;
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: KeePassEditorDialog(
          file: FileItem(
            name: 'vault.kdbx',
            path: '/vault.kdbx',
            isFolder: false,
          ),
          side: PanelSide.local,
          targetOverride: harness.target,
          sessionOpener: harness.open,
          readOnly: readOnly,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _unlock(tester, harness);
  return harness;
}

Future<void> _unlock(WidgetTester tester, _Harness harness) async {
  await tester.enterText(_key('master-password'), 'demo');
  await tester.runAsync(() async {
    final done = Completer<void>();
    harness.unlocked = done;
    await tester.tap(_key('unlock'));
    await done.future.timeout(const Duration(seconds: 20));
  });
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.pump();
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, _Harness harness) async {
  await tester.runAsync(() async {
    final done = Completer<void>();
    harness.target.written = done;
    await tester.tap(_key('save'));
    await done.future.timeout(const Duration(seconds: 20));
  });
  await tester.pumpAndSettle();
}

Future<KeePassSession> _reopen(WidgetTester tester, _Harness harness) async {
  final session = (await tester.runAsync(
    () => KeePassSession.open(
      harness.target.bytes,
      password: 'demo',
      keyFile: _fixture('demo.key'),
    ),
  ))!;
  addTearDown(session.dispose);
  return session;
}

Future<void> _group(WidgetTester tester, String path) async {
  await _tap(tester, _key('group-filter'));
  await _tap(
    tester,
    find.descendant(of: find.byType(AlertDialog), matching: find.text(path)),
  );
}

Future<void> _nameGroup(
  WidgetTester tester,
  String name, {
  bool rename = false,
}) async {
  await _tap(tester, _key(rename ? 'rename-group' : 'new-group'));
  await tester.enterText(_key('group-name'), name);
  await _tap(tester, _key('apply-group'));
}

void main() {
  testWidgets(
    'group controls create, rename, move and recycle without changing the original before Save',
    (tester) async {
      final harness = await _open(tester);
      final session = harness.session!;
      final root = session.groups.first;
      await _nameGroup(tester, 'UI parent');
      final parent = session.groups
          .firstWhere((group) => group.name == 'UI parent')
          .id;
      await _nameGroup(tester, 'Renamed parent', rename: true);
      await _nameGroup(tester, 'UI child');
      final child = session.groups
          .firstWhere((group) => group.name == 'UI child')
          .id;
      expect(
        session.groups.firstWhere((group) => group.id == child).parentId,
        parent,
      );
      await _tap(tester, _key('move-group'));
      await _tap(tester, _key('destination-${root.id}'));
      expect(
        session.groups.firstWhere((group) => group.id == child).parentId,
        root.id,
      );
      await _tap(tester, _key('delete-group'));
      await _tap(tester, _key('confirm-delete-group'));
      expect(
        session.groups.firstWhere((group) => group.id == child).isRecycled,
        isTrue,
      );
      const entryId = 'vqcoCvE9/k6PSgutKI6snw==';
      await _tap(tester, _key('entry-$entryId'));
      await _tap(tester, _key('move-entry'));
      await tester.scrollUntilVisible(
        _key('destination-$parent'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _tap(tester, _key('destination-$parent'));
      expect(
        session.entries.firstWhere((entry) => entry.id == entryId).groupId,
        parent,
      );
      expect(harness.target.writes, isEmpty);
      await _save(tester, harness);
      final reopened = await _reopen(tester, harness);
      expect(
        reopened.groups.firstWhere((group) => group.id == parent).name,
        'Renamed parent',
      );
      expect(
        reopened.groups.firstWhere((group) => group.id == child).isRecycled,
        isTrue,
      );
      expect(
        reopened.entries.firstWhere((entry) => entry.id == entryId).groupId,
        parent,
      );
      await _group(tester, root.path);
      expect(tester.widget<IconButton>(_key('move-group')).onPressed, isNull);
      expect(tester.widget<IconButton>(_key('delete-group')).onPressed, isNull);
    },
  );

  testWidgets(
    'protected custom drafts survive failed lock validation and save encrypted after correction',
    (tester) async {
      final harness = await _open(tester);
      await _tap(tester, _key('new-entry'));
      await tester.enterText(_key('field-title'), 'Custom draft');
      await _tap(tester, _key('add-field'));
      await tester.enterText(_key('custom-value-0'), 'sensitive custom draft');
      expect(
        tester.widget<TextField>(_key('custom-value-0')).obscureText,
        isTrue,
      );
      await _tap(tester, _key('lock'));
      expect(_key('custom-value-0'), findsNothing);
      expect(
        find.textContaining('Pending changes could not be encrypted.'),
        findsOneWidget,
      );
      expect(harness.target.writes, isEmpty);
      await _unlock(tester, harness);
      expect(
        tester.widget<TextField>(_key('custom-value-0')).controller!.text,
        'sensitive custom draft',
      );
      expect(
        tester.widget<TextField>(_key('custom-value-0')).obscureText,
        isTrue,
      );
      await tester.enterText(_key('custom-name-0'), 'Recovery code');
      await _tap(tester, _key('apply-entry'));
      expect(find.text('sensitive custom draft'), findsNothing);
      await _tap(tester, _key('reveal-field-Recovery code'));
      expect(find.text('sensitive custom draft'), findsOneWidget);
      await _save(tester, harness);
      expect(
        utf8.decode(harness.target.bytes, allowMalformed: true),
        isNot(contains('sensitive custom draft')),
      );
      final reopened = await _reopen(tester, harness);
      final entry = reopened.entries.firstWhere(
        (entry) => entry.title == 'Custom draft',
      );
      expect(reopened.customFields(entry.id).single.name, 'Recovery code');
      expect(
        reopened.customFields(entry.id).single.value,
        'sensitive custom draft',
      );
      expect(reopened.customFields(entry.id).single.isProtected, isTrue);
    },
  );

  Future<(Uint8List, String)> historyFixture(
    WidgetTester tester,
  ) async => (await tester.runAsync(() async {
    final session = await KeePassSession.open(
      _fixture('demo.kdbx'),
      password: 'demo',
      keyFile: _fixture('demo.key'),
    );
    try {
      final id = session.addEntry(
        groupId: session.groups.first.id,
        fields: const KeePassEntryFields(
          title: 'Past title',
          password: 'historical password',
        ),
        customFields: const [
          KeePassCustomField(name: 'Past field', value: 'historical custom'),
        ],
      );
      session.updateEntry(
        id,
        const KeePassEntryFields(
          title: 'Current title',
          password: 'current password',
        ),
        customFields: const [
          KeePassCustomField(name: 'Present field', value: 'current custom'),
        ],
      );
      return (await session.save(), id);
    } finally {
      session.dispose();
    }
  }))!;

  testWidgets(
    'history is inspected with masked secrets and explicitly restored to encrypted storage',
    (tester) async {
      final (bytes, id) = await historyFixture(tester);
      final harness = await _open(tester, bytes: bytes);
      await _tap(tester, _key('entry-$id'));
      await _tap(tester, _key('history'));
      await _tap(tester, _key('history-0'));
      expect(find.text('historical password'), findsNothing);
      expect(find.text('historical custom'), findsNothing);
      await _tap(tester, _key('history-reveal'));
      expect(find.text('historical password'), findsOneWidget);
      await _tap(tester, _key('restore-history'));
      expect(harness.session!.entryFields(id).title, 'Current title');
      await _tap(tester, _key('confirm-restore'));
      expect(harness.session!.entryFields(id).title, 'Past title');
      expect(harness.session!.entryHistory(id).length, 2);
      await _save(tester, harness);
      final reopened = await _reopen(tester, harness);
      expect(reopened.entryFields(id).password, 'historical password');
      expect(reopened.customFields(id).single.value, 'historical custom');
      expect(reopened.historyFields(id, 1).password, 'current password');
    },
  );

  testWidgets(
    'background lock hides revealed history while its dialog is closing',
    (tester) async {
      final (bytes, id) = await historyFixture(tester);
      await _open(tester, bytes: bytes, readOnly: true);
      await _tap(tester, _key('entry-$id'));
      await _tap(tester, _key('history'));
      await _tap(tester, _key('history-0'));
      await _tap(tester, _key('history-reveal'));
      await _tap(tester, _key('reveal-field-Past field'));
      expect(find.text('historical password'), findsOneWidget);
      expect(find.text('historical custom'), findsOneWidget);

      // Start the pop without settling its reverse animation. The route is
      // already inactive when the lock arrives, but its content still paints.
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('historical password'), findsNothing);
      expect(find.text('historical custom'), findsNothing);
      expect(_key('dialog-shield'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('historical password'), findsNothing);
      expect(find.text('historical custom'), findsNothing);
      expect(find.text('KeePass database locked'), findsOneWidget);
    },
  );

  testWidgets(
    'read-only history has no restore or group mutation and closes on background lock',
    (tester) async {
      final (bytes, id) = await historyFixture(tester);
      await _open(tester, bytes: bytes, readOnly: true);
      expect(_key('new-group'), findsNothing);
      await _tap(tester, _key('entry-$id'));
      expect(_key('edit-entry'), findsNothing);
      expect(_key('move-entry'), findsNothing);
      await _tap(tester, _key('history'));
      await _tap(tester, _key('history-0'));
      expect(_key('restore-history'), findsNothing);
      await _tap(tester, _key('reveal-field-Past field'));
      expect(find.text('historical custom'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('historical custom'), findsNothing);
      expect(find.text('KeePass database locked'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );
}
