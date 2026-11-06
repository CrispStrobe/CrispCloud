import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_process_native.dart' as proc;
import 'package:crisp_cloud/widgets/terminal_shell.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<bool> beginStreamAccess(String path) async => true;
  @override
  Future<void> endStreamAccess() async {}
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async =>
      Uint8List(0);
  @override
  Future<void> saveFile(String path, Uint8List data) async {}
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> deleteEntry(String path, bool isFolder) async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, dynamic> getWebMetadata(String path) => {};
  @override
  Object? getWebFileRef(String path) => null;
  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) async => const <FileItem>[];
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  bool get isAuthenticated => false;
  @override
  String get providerName => 'Test';
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final CloudStorageClient client = _Cloud();
  @override
  bool get isConnected => false;
  @override
  String? get userEmail => null;
  @override
  String get providerName => 'Test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShell implements TerminalShell {
  final _controller = StreamController<String>.broadcast();
  final commands = <String>[];

  @override
  Stream<String> get outputStream => _controller.stream;
  @override
  void writeln(String command) => commands.add(command);
  void emit(String text) => _controller.add(text);

  @override
  void kill() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'built-in shell executes file commands inside its working directory',
    () async {
      final dir = Directory.systemTemp.createTempSync('builtin_terminal_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/hello.txt').writeAsStringSync('hello');
      final shell = await proc.startBuiltInShell(dir.path);
      expect(shell, isNotNull);
      final output = <String>[];
      final subscription = shell!.outputStream.listen(output.add);

      shell.writeln('pwd');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(output.join(), contains(dir.path));

      output.clear();
      shell.writeln('ls');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(output.join(), contains('hello.txt'));

      output.clear();
      shell.writeln('cat hello.txt');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(output.join(), contains('hello'));

      shell.kill();
      await subscription.cancel();
    },
  );

  test('real PTY shell accepts a command on desktop', () async {
    final shell = await proc.startShell(Directory.systemTemp.path);
    expect(shell, isNotNull);
    final output = <String>[];
    final subscription = shell!.outputStream.listen(output.add);
    shell.writeln('echo crisp-terminal-test');
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (output.join().contains('crisp-terminal-test')) break;
    }
    expect(output.join(), contains('crisp-terminal-test'));
    shell.kill();
    await subscription.cancel();
  }, skip: !Platform.isMacOS);

  testWidgets('terminal sends exactly the typed command', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeShell();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileServiceProvider.overrideWithValue(_Local()),
          authProvider.overrideWith((_) => _Auth()),
        ],
        child: MaterialApp(
          home: Scaffold(body: TerminalPanel(shellStarter: (_) async => fake)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    fake.emit('% ');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'ls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(fake.commands, ['ls']);
  });
}
