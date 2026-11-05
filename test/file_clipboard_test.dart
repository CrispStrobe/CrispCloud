import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_clipboard_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_operations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  @override
  String get providerName => 'Clipboard test';
  @override
  String? get userId => 'account-a';
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  bool isAuthenticated = true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      {'name': 'file.txt', 'size': 3, 'uuid': '$path/file-id'},
    ],
  };
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? get userEmail => 'test@example.invalid';
  @override
  String get providerName => client.providerName;
  void disconnect() {
    isConnected = false;
    client.isAuthenticated = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  _Local(this.directory) : currentPath = directory.path;
  final Directory directory;
  @override
  String currentPath;
  @override
  String? get grantedBasePath => directory.path;
  @override
  Future<String> getInitialPath() async => directory.path;
  @override
  Future<String> getSafeFallbackDirectory() async => directory.path;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      directory.list().toList();
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Auth auth;
  late Directory directory;
  String? clipboardText;
  Map<String, Object?>? nativeClipboard;
  const nativeChannel = MethodChannel('test/clipboard');
  const native = NativeFileOperations(channel: nativeChannel);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('clipboard-');
    await File('${directory.path}/local.txt').writeAsString('abc');
    auth = _Auth(_Cloud());
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local(directory)),
      ],
    );
    clipboardText = null;
    nativeClipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'writeClipboard') {
            nativeClipboard = Map<String, Object?>.from(call.arguments as Map);
          }
          if (call.method == 'readClipboard') return nativeClipboard;
          return null;
        });
  });
  tearDown(() async {
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    await directory.delete(recursive: true);
  });

  test(
    'clipboard retains original account and path after navigating away',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final file = panel.files!.single;
      final clipboard = FileClipboardNotifier();
      await clipboard.capture(panel, [file], native, cut: false);
      await panel.navigateToPath('/other');
      expect(clipboard.selection!.files.single.path, '/file.txt');
      expect(clipboard.selection!.origin.source.currentPath, '/');
      expect(clipboard.selection!.origin.isCurrent, isTrue);
      expect(await clipboard.stillOwnsClipboard(native), isTrue);
      expect(clipboardText, startsWith('crispcloud://file-selection/'));
      expect(clipboardText, isNot(contains('account-a')));
    },
  );

  test('external text replaces the app selection and disconnect invalidates the source', () async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final clipboard = FileClipboardNotifier();
    await clipboard.capture(panel, panel.files!, native, cut: true);
    expect(clipboard.selection!.cut, isTrue);
    clipboardText = 'different application';
    expect(await clipboard.stillOwnsClipboard(native), isFalse);
    auth.disconnect();
    expect(clipboard.selection!.origin.isCurrent, isFalse);
  });

  test(
    'desktop clipboard uses full native paths and preserves cut intent',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final panel = container.read(panelProvider(PanelSide.local));
      await panel.refresh();
      final files = panel.files!.where((file) => file.name != '..').toList();
      final clipboard = FileClipboardNotifier();
      await clipboard.capture(panel, files, native, cut: true);
      expect(nativeClipboard, {
        'paths': ['${directory.path}/local.txt'],
        'cut': true,
      });
      expect(clipboardText, isNull);
      expect(await clipboard.stillOwnsClipboard(native), isTrue);
      nativeClipboard = {
        'paths': ['/elsewhere/file'],
        'cut': true,
      };
      expect(await clipboard.stillOwnsClipboard(native), isFalse);
    },
  );
  test('mixed collections keep every captured source and reject a disconnected account', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final remote = container.read(panelProvider(PanelSide.remote));
    final local = container.read(panelProvider(PanelSide.local));
    await remote.refresh();
    await local.refresh();
    final cloudFile = remote.files!.single;
    final localFile = local.files!.singleWhere((file) => file.name != '..');
    final cloudOrigin = remote.captureOperationOrigin([cloudFile]);
    final localOrigin = local.captureOperationOrigin([localFile]);
    remote.showSearchResults(
      [cloudFile, localFile],
      originForFile: (file) =>
          identical(file, cloudFile) ? cloudOrigin : localOrigin,
    );
    final clipboard = FileClipboardNotifier();
    await clipboard.capture(remote, remote.files!, native, cut: true);
    final captured = clipboard.selection!;
    expect(captured.groups.length, 2);
    expect(captured.native, isFalse);
    expect(nativeClipboard, isNull);
    expect(captured.isCurrent, isTrue);
    expect(await clipboard.stillOwnsClipboard(native), isTrue);
    expect(() => captured.groups.clear(), throwsUnsupportedError);
    expect(() => captured.groups.values.first.clear(), throwsUnsupportedError);
    await remote.navigateToPath('/other');
    expect(captured.files.map((file) => file.path).toSet(), {
      '/file.txt',
      '${directory.path}/local.txt',
    });
    auth.disconnect();
    expect(captured.isCurrent, isFalse);
    expect(localOrigin.isCurrent, isTrue);
  });
}
