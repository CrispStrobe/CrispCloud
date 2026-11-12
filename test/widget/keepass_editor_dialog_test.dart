import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/captured_file_target.dart';
import 'package:crisp_cloud/services/keepass_service.dart';
import 'package:crisp_cloud/widgets/keepass_editor_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _initialFields = KeePassEntryFields(
  title: 'Personal login',
  userName: 'alice@example.test',
  password: 'entry-secret-42',
  url: 'https://example.test',
  notes: 'A private note',
);

class _Record {
  const _Record(this.groupId, this.fields);
  final String groupId;
  final KeePassEntryFields fields;
}

/// Deterministic ciphertext handles keep widget tests independent of crypto
/// timing. Backend tests separately verify real KDBX encryption/round trips.
class _Sessions {
  final snapshots = <int, Map<String, _Record>>{
    0: {'one': const _Record('personal', _initialFields)},
  };
  final opened = <_Session>[];
  final receivedPasswords = <String?>[];
  final receivedKeyFiles = <Uint8List?>[];
  Completer<void>? openBarrier;
  Completer<void>? saveBarrier;
  bool failSerialization = false;
  bool failMutation = false;

  Uint8List bytes(int id) =>
      Uint8List.fromList([3, 217, 162, 154, 103, 251, 75, 181, id]);

  Future<KeePassSession> open(
    Uint8List bytes, {
    required String? password,
    Uint8List? keyFile,
  }) async {
    receivedPasswords.add(password);
    receivedKeyFiles.add(keyFile == null ? null : Uint8List.fromList(keyFile));
    await openBarrier?.future;
    if (password != 'master' && !(password == null && keyFile != null)) {
      throw const KeePassException(KeePassErrorCode.invalidCredentials);
    }
    final session = _Session(this, Map.of(snapshots[bytes.last]!));
    opened.add(session);
    return session;
  }
}

class _Session extends Fake implements KeePassSession {
  _Session(this.owner, this.records);
  final _Sessions owner;
  final Map<String, _Record> records;
  bool disposed = false;
  int saveCount = 0;

  @override
  String get databaseName => 'Private vault';
  @override
  String get formatLabel => 'KDBX 4.1 · AES-256 · Argon2id';
  @override
  List<KeePassGroupInfo> get groups => const [
    KeePassGroupInfo(id: 'root', name: 'Vault', path: '/Vault'),
    KeePassGroupInfo(id: 'personal', name: 'Personal', path: '/Vault/Personal'),
  ];
  @override
  List<KeePassEntryInfo> get entries => records.entries
      .map(
        (entry) => KeePassEntryInfo(
          id: entry.key,
          groupId: entry.value.groupId,
          title: entry.value.fields.title,
          userName: entry.value.fields.userName,
        ),
      )
      .toList();
  @override
  KeePassEntryFields entryFields(String id) => records[id]!.fields;
  @override
  String addEntry({
    required String groupId,
    required KeePassEntryFields fields,
  }) {
    if (owner.failMutation) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    final id = 'new-${records.length}';
    records[id] = _Record(groupId, fields);
    return id;
  }

  @override
  void updateEntry(String id, KeePassEntryFields fields) {
    if (owner.failMutation) {
      throw const KeePassException(KeePassErrorCode.resourceLimit);
    }
    records[id] = _Record(records[id]!.groupId, fields);
  }

  @override
  void deleteEntry(String id) => records.remove(id);
  @override
  Future<Uint8List> save() async {
    saveCount++;
    await owner.saveBarrier?.future;
    if (owner.failSerialization) {
      throw const KeePassException(KeePassErrorCode.corrupt);
    }
    final id = owner.snapshots.length;
    owner.snapshots[id] = Map.of(records);
    return owner.bytes(id);
  }

  @override
  void dispose() => disposed = true;
}

class _Target extends Fake implements CapturedFileTarget {
  _Target(this.bytes);
  Uint8List bytes;
  final writes = <Uint8List>[];
  final firstWrite = Completer<void>();
  bool current = true;
  FileWriteOutcome outcome = FileWriteOutcome.savedOriginal;
  Completer<void>? barrier;

  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<FileWriteOutcome> save(Uint8List bytes) async {
    await barrier?.future;
    if (!current) throw const FileTargetConflict('Test source changed');
    writes.add(Uint8List.fromList(bytes));
    if (outcome == FileWriteOutcome.savedOriginal) {
      this.bytes = Uint8List.fromList(bytes);
    }
    if (!firstWrite.isCompleted) firstWrite.complete();
    return outcome;
  }
}

class _Picker extends FilePicker {
  _Picker(this.file);
  final PlatformFile file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([file]);
}

Finder _key(String value) => find.byKey(ValueKey('keepass-$value'));

Future<void> _open(
  WidgetTester tester,
  _Sessions sessions, {
  _Target? target,
  bool readOnly = false,
  bool detached = false,
  Duration inactivity = const Duration(minutes: 5),
  KeePassSessionOpener? opener,
  ValueNotifier<_Target>? targetSwitcher,
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final initialTarget = target ?? _Target(sessions.bytes(0));
  final file = FileItem(
    name: 'vault.kdbx',
    path: '/vault.kdbx',
    isFolder: false,
    size: 9,
  );
  Widget editor(_Target selectedTarget) => KeePassEditorDialog(
    file: file,
    side: PanelSide.local,
    targetOverride: detached ? null : selectedTarget,
    bytesOverride: detached ? sessions.bytes(0) : null,
    sessionOpener: opener ?? sessions.open,
    readOnly: readOnly,
    inactivityTimeout: inactivity,
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog.fullscreen(
                  child: targetSwitcher == null
                      ? editor(initialTarget)
                      : ValueListenableBuilder<_Target>(
                          valueListenable: targetSwitcher,
                          builder: (_, selectedTarget, _) =>
                              editor(selectedTarget),
                        ),
                ),
              ),
              child: const Text('Open database'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open database'));
  await tester.pumpAndSettle();
}

Future<void> _unlock(WidgetTester tester, {String password = 'master'}) async {
  await tester.enterText(_key('master-password'), password);
  await tester.tap(_key('unlock'));
  await tester.pumpAndSettle();
}

Future<void> _editPassword(WidgetTester tester, String password) async {
  await tester.tap(_key('entry-one'));
  await tester.pump();
  await tester.tap(_key('edit-entry'));
  await tester.pump();
  await tester.enterText(_key('field-password'), password);
  await tester.pump();
}

void main() {
  setUp(() {
    FilePicker.platform = _Picker(
      PlatformFile(
        name: 'unused.key',
        size: 0,
        readStream: const Stream.empty(),
      ),
    );
  });

  testWidgets(
    'an old save cannot clean a replacement document with the same file name',
    (tester) async {
      final sessions = _Sessions();
      final first = _Target(sessions.bytes(0))..barrier = Completer<void>();
      final second = _Target(sessions.bytes(0));
      final current = ValueNotifier(first);
      addTearDown(current.dispose);
      await _open(tester, sessions, targetSwitcher: current);
      await _unlock(tester);
      await _editPassword(tester, 'first-document-edit');
      await tester.tap(_key('save'));
      await tester.pump();
      current.value = second;
      await tester.pumpAndSettle();
      expect(find.text('KeePass database locked'), findsOneWidget);
      expect(sessions.opened.first.disposed, isTrue);
      await _unlock(tester);
      await _editPassword(tester, 'second-document-edit');
      await tester.ensureVisible(_key('apply-entry'));
      await tester.tap(_key('apply-entry'));
      await tester.pump();
      first.barrier!.complete();
      await tester.pumpAndSettle();
      expect(first.writes, hasLength(1));
      expect(second.writes, isEmpty);
      expect(find.text('vault.kdbx *'), findsOneWidget);
      expect(tester.widget<IconButton>(_key('save')).onPressed, isNotNull);
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(second.writes, hasLength(1));
      expect(
        sessions.snapshots[second.bytes.last]!['one']!.fields.password,
        'second-document-edit',
      );
      expect(find.text('vault.kdbx *'), findsNothing);
    },
  );

  testWidgets(
    'delayed clipboard cleanup cannot erase a newer copied password',
    (tester) async {
      String? clipboard;
      final delayedRead = Completer<Object?>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') {
            if (reads++ == 0) return delayedRead.future;
            return {'text': clipboard};
          }
          return null;
        },
      );
      final sessions = _Sessions();
      sessions.snapshots[0]!['two'] = const _Record(
        'personal',
        KeePassEntryFields(
          title: 'Second login',
          password: 'newer-clipboard-secret',
        ),
      );
      await _open(tester, sessions);
      await _unlock(tester);
      await tester.tap(_key('entry-one'));
      await tester.pump();
      await tester.tap(_key('copy-password'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(reads, 1);
      await tester.tap(_key('entry-two'));
      await tester.pump();
      await tester.tap(_key('copy-password'));
      await tester.pump();
      expect(clipboard, 'newer-clipboard-secret');
      delayedRead.complete({'text': 'entry-secret-42'});
      await tester.pump();
      expect(clipboard, 'newer-clipboard-secret');
    },
  );

  testWidgets(
    'real KeePass fixture unlocks, edits and saves a reopenable encrypted file',
    (tester) async {
      Uint8List fixture(String name) => base64.decode(
        File('test/fixtures/keepass/$name.b64')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s'), ''),
      );
      final keyFile = fixture('demo.key');
      final target = (await tester.runAsync(
        () async => _Target(fixture('demo.kdbx')),
      ))!;
      final originalPicker = FilePicker.platform;
      FilePicker.platform = _Picker(
        PlatformFile(
          name: 'demo.key',
          size: keyFile.length,
          readStream: Stream.value(keyFile),
        ),
      );
      addTearDown(() => FilePicker.platform = originalPicker);
      final unlocked = (await tester.runAsync(() async => Completer<void>()))!;
      await _open(
        tester,
        _Sessions(),
        target: target,
        opener: (bytes, {required password, keyFile}) async {
          try {
            return await KeePassSession.open(
              bytes,
              password: password,
              keyFile: keyFile,
            );
          } finally {
            unlocked.complete();
          }
        },
      );
      await tester.tap(_key('key-file'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('master-password'), 'demo');
      await tester.runAsync(() async {
        await tester.tap(_key('unlock'));
        await unlocked.future.timeout(const Duration(seconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('demo'), findsOneWidget);
      await tester.tap(_key('entry-vqcoCvE9/k6PSgutKI6snw=='));
      await tester.pump();
      await tester.tap(_key('edit-entry'));
      await tester.pump();
      await tester.enterText(_key('field-password'), 'real-encrypted-edit');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(_key('save'));
        await target.firstWrite.future.timeout(const Duration(seconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('vault.kdbx *'), findsNothing);
      final reopened = await tester.runAsync(
        () => KeePassSession.open(
          target.bytes,
          password: 'demo',
          keyFile: keyFile,
        ),
      );
      expect(
        reopened!.entryFields('vqcoCvE9/k6PSgutKI6snw==').password,
        'real-encrypted-edit',
      );
      reopened.dispose();
    },
  );

  testWidgets(
    'unlock clears credentials and requires explicit reveal and copy',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      final sessions = _Sessions();
      await _open(tester, sessions);
      expect(
        tester.widget<TextField>(_key('master-password')).obscureText,
        isTrue,
      );
      await _unlock(tester, password: 'wrong-master');
      expect(
        tester.widget<TextField>(_key('master-password')).controller!.text,
        isEmpty,
      );
      expect(
        find.text('The master password or key file is incorrect.'),
        findsOneWidget,
      );
      expect(find.textContaining('wrong-master'), findsNothing);
      await _unlock(tester);
      expect(find.text('Private vault'), findsOneWidget);
      await tester.tap(_key('entry-one'));
      await tester.pumpAndSettle();
      expect(find.text('entry-secret-42'), findsNothing);
      expect(_key('hidden-password'), findsOneWidget);
      await tester.tap(_key('reveal-password'));
      await tester.pump();
      expect(find.text('entry-secret-42'), findsOneWidget);
      await tester.tap(_key('copy-password'));
      await tester.pump();
      expect(clipboard, 'entry-secret-42');
      await tester.tap(_key('lock'));
      await tester.pumpAndSettle();
      expect(find.text('entry-secret-42'), findsNothing);
      expect(clipboard, isEmpty);
      expect(sessions.opened.single.disposed, isTrue);
      expect(
        tester.widget<TextField>(_key('master-password')).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'detached attachment bytes remain read only even without a readOnly flag',
    (tester) async {
      await _open(tester, _Sessions(), detached: true);
      await _unlock(tester);
      await tester.tap(_key('entry-one'));
      await tester.pump();
      expect(find.text('Read only'), findsOneWidget);
      expect(_key('save'), findsNothing);
      expect(_key('edit-entry'), findsNothing);
      expect(_key('delete-entry'), findsNothing);
      expect(_key('new-entry'), findsNothing);
    },
  );

  testWidgets(
    'add, edit, delete and save send only the serialized ciphertext to the captured target',
    (tester) async {
      final sessions = _Sessions();
      final target = _Target(sessions.bytes(0));
      await _open(tester, sessions, target: target);
      await _unlock(tester);
      await _editPassword(tester, 'new-private-password');
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(target.writes, hasLength(1));
      expect(target.writes.single, sessions.bytes(1));
      expect(
        sessions.snapshots[1]!['one']!.fields.password,
        'new-private-password',
      );
      expect(find.text('vault.kdbx *'), findsNothing);
      await tester.tap(_key('new-entry'));
      await tester.pump();
      await tester.enterText(_key('field-title'), 'Second login');
      await tester.enterText(_key('field-userName'), 'bob');
      await tester.enterText(_key('field-password'), 'second-secret');
      await tester.ensureVisible(_key('apply-entry'));
      await tester.tap(_key('apply-entry'));
      await tester.pumpAndSettle();
      expect(sessions.opened.single.entries, hasLength(2));
      expect(find.text('vault.kdbx *'), findsOneWidget);
      await tester.tap(_key('delete-entry'));
      await tester.pumpAndSettle();
      await tester.tap(_key('confirm-delete'));
      await tester.pumpAndSettle();
      expect(sessions.opened.single.entries, hasLength(1));
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(target.writes, hasLength(2));
      expect(sessions.snapshots[2], hasLength(1));
      expect(find.text('vault.kdbx *'), findsNothing);
    },
  );

  testWidgets('downloaded copies and source conflicts keep changes dirty', (
    tester,
  ) async {
    final sessions = _Sessions();
    final target = _Target(sessions.bytes(0))
      ..outcome = FileWriteOutcome.downloadedCopy;
    await _open(tester, sessions, target: target);
    await _unlock(tester);
    await _editPassword(tester, 'changed');
    await tester.tap(_key('save'));
    await tester.pumpAndSettle();
    expect(find.text('vault.kdbx *'), findsOneWidget);
    expect(
      find.text(
        'An encrypted copy was downloaded. The original file was not updated.',
      ),
      findsOneWidget,
    );
    target.current = false;
    await tester.tap(_key('save'));
    await tester.pumpAndSettle();
    expect(target.writes, hasLength(1));
    expect(find.text('vault.kdbx *'), findsOneWidget);
    expect(
      find.textContaining('The original file or storage changed.'),
      findsOneWidget,
    );
    expect(find.text('Test source changed'), findsNothing);
    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
    expect(_key('unsaved-dialog'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(KeePassEditorDialog), findsOneWidget);
    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
    await tester.tap(_key('discard'));
    await tester.pumpAndSettle();
    expect(find.byType(KeePassEditorDialog), findsNothing);
  });

  testWidgets(
    'inactivity encrypts a draft without writing it and unlock preserves dirty work',
    (tester) async {
      final sessions = _Sessions();
      final target = _Target(sessions.bytes(0));
      await _open(
        tester,
        sessions,
        target: target,
        inactivity: const Duration(seconds: 10),
      );
      await _unlock(tester);
      await _editPassword(tester, 'unsaved-secret');
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('KeePass database locked'), findsOneWidget);
      expect(_key('field-password'), findsNothing);
      expect(sessions.opened.single.disposed, isTrue);
      expect(target.writes, isEmpty);
      expect(sessions.snapshots[1]!['one']!.fields.password, 'unsaved-secret');
      await _unlock(tester);
      expect(find.text('vault.kdbx *'), findsOneWidget);
      await tester.tap(_key('entry-one'));
      await tester.pump();
      await tester.tap(_key('reveal-password'));
      await tester.pump();
      expect(find.text('unsaved-secret'), findsOneWidget);
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(target.writes, hasLength(1));
      expect(find.text('vault.kdbx *'), findsNothing);
    },
  );

  testWidgets(
    'backgrounding hides data immediately while an encrypted save is in flight',
    (tester) async {
      final sessions = _Sessions();
      final target = _Target(sessions.bytes(0))..barrier = Completer<void>();
      await _open(tester, sessions, target: target);
      await _unlock(tester);
      await _editPassword(tester, 'pending-upload-secret');
      await tester.tap(_key('save'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Private vault'), findsNothing);
      expect(find.text('A private note'), findsNothing);
      expect(find.text('Locking database…'), findsOneWidget);
      target.barrier!.complete();
      await tester.pumpAndSettle();
      expect(sessions.opened.single.disposed, isTrue);
      expect(target.writes, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('KeePass database locked'), findsOneWidget);
    },
  );

  testWidgets(
    'an unlock finishing after backgrounding cannot expose a session',
    (tester) async {
      final sessions = _Sessions()..openBarrier = Completer<void>();
      await _open(tester, sessions);
      await tester.enterText(_key('master-password'), 'master');
      await tester.tap(_key('unlock'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      sessions.openBarrier!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Private vault'), findsNothing);
      expect(sessions.opened.single.disposed, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('KeePass database locked'), findsOneWidget);
    },
  );

  testWidgets(
    'failed lock encryption preserves hidden edits behind reauthentication',
    (tester) async {
      final sessions = _Sessions();
      await _open(tester, sessions);
      await _unlock(tester);
      await _editPassword(tester, 'must-not-be-lost');
      sessions.failSerialization = true;
      await tester.tap(_key('lock'));
      await tester.pumpAndSettle();
      expect(find.text('Private vault'), findsNothing);
      expect(sessions.opened.first.disposed, isFalse);
      expect(
        find.textContaining('Pending changes could not be encrypted.'),
        findsOneWidget,
      );
      await _unlock(tester, password: 'incorrect');
      expect(find.text('Private vault'), findsNothing);
      sessions.failSerialization = false;
      await _unlock(tester);
      expect(find.text('Private vault'), findsOneWidget);
      expect(sessions.opened.last.disposed, isTrue);
      expect(
        sessions.opened.first.records['one']!.fields.password,
        'must-not-be-lost',
      );
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(find.text('vault.kdbx *'), findsNothing);
    },
  );

  testWidgets(
    'a failed draft application survives lock without losing entry identity',
    (tester) async {
      final sessions = _Sessions();
      await _open(tester, sessions);
      await _unlock(tester);
      await _editPassword(tester, 'retained-draft');
      sessions.failMutation = true;
      await tester.tap(_key('lock'));
      await tester.pumpAndSettle();
      expect(_key('field-password'), findsNothing);
      sessions.failMutation = false;
      await _unlock(tester);
      expect(
        tester.widget<TextField>(_key('field-password')).controller!.text,
        'retained-draft',
      );
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(
        sessions.opened.first.records['one']!.fields.password,
        'retained-draft',
      );
      expect(find.text('vault.kdbx *'), findsNothing);
    },
  );

  testWidgets(
    'group and search controls filter titles and users without searching passwords',
    (tester) async {
      final sessions = _Sessions();
      sessions.snapshots[0]!['two'] = const _Record(
        'root',
        KeePassEntryFields(title: 'Work login', userName: 'bob'),
      );
      await _open(tester, sessions, readOnly: true);
      await _unlock(tester);
      await tester.enterText(_key('search'), 'entry-secret-42');
      await tester.pump();
      expect(find.text('No matching entries.'), findsOneWidget);
      await tester.enterText(_key('search'), 'alice');
      await tester.pump();
      expect(_key('entry-one'), findsOneWidget);
      expect(_key('entry-two'), findsNothing);
      await tester.enterText(_key('search'), '');
      await tester.tap(_key('group-filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('/Vault/Personal'));
      await tester.pumpAndSettle();
      expect(_key('entry-one'), findsOneWidget);
      expect(_key('entry-two'), findsNothing);
      await tester.tap(_key('group-filter'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('/Vault/Personal'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets(
    'key-file-only unlock omits the password component and consumes the key file',
    (tester) async {
      final sessions = _Sessions();
      final original = FilePicker.platform;
      FilePicker.platform = _Picker(
        PlatformFile(
          name: 'vault.keyx',
          size: 4,
          readStream: Stream.value([1, 2, 3, 4]),
        ),
      );
      addTearDown(() => FilePicker.platform = original);
      await _open(tester, sessions);
      await tester.tap(_key('password-component'));
      await tester.pump();
      expect(_key('master-password'), findsNothing);
      await tester.tap(_key('key-file'));
      await tester.pumpAndSettle();
      expect(find.text('vault.keyx'), findsOneWidget);
      await tester.tap(_key('unlock'));
      await tester.pumpAndSettle();
      expect(sessions.receivedPasswords.single, isNull);
      expect(sessions.receivedKeyFiles.single, [1, 2, 3, 4]);
      expect(find.text('Private vault'), findsOneWidget);
      await tester.tap(_key('lock'));
      await tester.pumpAndSettle();
      expect(find.text('vault.keyx'), findsNothing);
    },
  );
}
