import 'dart:async';
import 'dart:io';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Files implements LocalFileService {
  @override
  String currentPath;
  Files(this.currentPath);
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<void> refresh() async {}
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client extends CloudStorageClient {
  int produced = 0;
  bool fail = false;
  final closed = Completer<void>();
  @override
  String get providerName => 'Fixture';
  @override
  bool get isAuthenticated => true;
  @override
  Stream<List<int>> downloadStream(String path,
      {Function(int, int)? onProgress}) async* {
    if (fail && path.endsWith('bad.mp3')) {
      throw const RemoteException('Access denied');
    }
    try {
      for (var i = 0; i < 10; i++) {
        produced++;
        yield List.filled(32768, i);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    } finally {
      if (!closed.isCompleted) closed.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Auth extends AuthNotifier {
  final Client fixture;
  Auth(super.ref, this.fixture)
      : super(
            initialProvider: CloudProvider.filen,
            config: FilenConfigService(
                configPath: '', secureStorage: InMemorySecureStorage()),
            configPath: '',
            secureStorage: InMemorySecureStorage());
  @override
  CloudStorageClient get client => fixture;
  @override
  Future<void> ensureAuthenticated() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ProviderContainer container;
  late Client client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('crisp_transfer_');
    client = Client();
    container = ProviderContainer(overrides: [
      localFileServiceProvider.overrideWithValue(Files(root.path)),
      secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      configPathProvider.overrideWithValue(root.path),
      authProvider.overrideWith((ref) => Auth(ref, client)),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });
  Future<void> until(bool Function() ready) async {
    final limit = DateTime.now().add(const Duration(seconds: 5));
    while (!ready()) {
      if (DateTime.now().isAfter(limit)) throw StateError('Transfer timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  FileItem file(String name) =>
      FileItem(name: name, path: '/$name', isFolder: false, size: 327680);
  test('pause applies backpressure to the download and resume completes it',
      () async {
    final transfers = container.read(transferProvider);
    var paused = false;
    transfers.addListener(() {
      if (transfers.operations.isNotEmpty &&
          transfers.operations.single.currentBytes > 0 &&
          !paused) {
        paused = true;
        transfers.pauseOperation(transfers.operations.single.id);
      }
    });
    await transfers.downloadFiles([file('book.mp3')], localPath: root.path);
    await until(() => paused);
    final op = transfers.operations.single;
    final before = op.currentBytes;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(op.currentBytes, before);
    expect(client.produced, lessThanOrEqualTo(2));
    transfers.resumeOperation(op.id);
    await until(() => op.isComplete);
    expect(op.status, OperationStatus.completed);
    expect(await File('${root.path}/book.mp3').length(), 327680);
  });
  test('cancel stops the stream before remaining chunks are written', () async {
    final transfers = container.read(transferProvider);
    var cancelled = false;
    transfers.addListener(() {
      if (transfers.operations.isNotEmpty &&
          transfers.operations.single.currentBytes > 0 &&
          !cancelled) {
        cancelled = true;
        transfers.cancelOperation(transfers.operations.single.id);
      }
    });
    await transfers.downloadFiles([file('book.mp3')], localPath: root.path);
    await client.closed.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(transfers.operations.single.isCancelled, isTrue);
    expect(client.produced, lessThan(10));
    expect(await File('${root.path}/book.mp3').length(), lessThan(327680));
  });
  test('one failed file finishes a mixed batch with a visible error', () async {
    client.fail = true;
    final transfers = container.read(transferProvider);
    await transfers.downloadFiles([file('good.mp3'), file('bad.mp3')],
        localPath: root.path);
    await until(() => transfers.operations.single.isComplete);
    final op = transfers.operations.single;
    expect(op.status, OperationStatus.failed);
    expect(op.errorMessage, '1 of 2 files failed');
    expect(op.files!.where((f) => f.error != null), hasLength(1));
  });
}
