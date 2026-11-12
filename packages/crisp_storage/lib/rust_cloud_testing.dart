// Test double for [RustCloudApi]; shared by package and app tests.
import 'dart:async';
import 'dart:convert';

import 'src/cloud_engine.dart';

/// Scriptable in-memory [RustCloudApi] used by package and app tests.
class FakeRustCloudApi implements RustCloudApi {
  bool available = true;
  int initializeCalls = 0;
  final calls = <String>[];
  final progressValues = <int, List<int>>{};
  final cancelled = <int>{};
  final released = <int>{};
  final closed = <int>{};
  int revisionValue = 1;
  RustCloudException? loginError;
  RustCloudException? nextError;
  Completer<int>? downloadGate;

  /// Optional hooks so IO tests can materialize/inspect transfer files.
  FutureOr<void> Function(String localPath)? onUploadFile;
  FutureOr<void> Function(String localPath)? onDownloadFile;
  int _next = 0;

  static String envelope(String provider, {String account = 'a@b.c'}) =>
      jsonEncode({
        'format': 'crisp-cloud-rust-session',
        'version': 1,
        'provider': provider,
        'account': account,
        'session': {'secret': 'x'},
      });

  void _maybeFail() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (!available) throw const RustCloudUnavailable();
  }

  @override
  Future<String> login(
    RustCloudProvider provider,
    String email,
    String password,
    String? twoFactorCode,
  ) async {
    calls.add('login:${provider.name}:$email:${twoFactorCode ?? ''}');
    if (loginError != null) throw loginError!;
    return envelope(provider.name, account: email);
  }

  @override
  Future<int> open(RustCloudProvider provider, String envelope) async {
    calls.add('open:${provider.name}');
    _maybeFail();
    return ++_next;
  }

  @override
  Map<String, dynamic> info(int session) => {
    'provider': 'filen',
    'account': 'a@b.c',
    'root': 'root-uuid',
    'revision': revisionValue,
  };

  @override
  int revision(int session) => revisionValue;

  @override
  Future<String> export(int session) async {
    calls.add('export');
    return envelope('filen', account: 'renewed@b.c');
  }

  @override
  Future<String> list(int session, String path, bool fresh) async {
    calls.add('list:$path:$fresh');
    _maybeFail();
    return jsonEncode([
      {'uuid': 'd1', 'name': 'Docs', 'directory': true, 'size': 0},
      {
        'uuid': 'f1',
        'name': 'a.txt',
        'directory': false,
        'size': 3,
        'modified': 1700000000000,
        'mime': 'text/plain',
      },
    ]);
  }

  @override
  Future<String> stat(int session, String path) async {
    calls.add('stat:$path');
    _maybeFail();
    return jsonEncode({
      'uuid': 'f1',
      'name': path.split('/').last,
      'directory': false,
      'size': 3,
    });
  }

  @override
  Future<String> mkdir(int session, String path) async {
    calls.add('mkdir:$path');
    _maybeFail();
    return jsonEncode({
      'uuid': 'new',
      'name': path.split('/').last,
      'directory': true,
      'size': 0,
    });
  }

  @override
  Future<void> rename(int session, String path, String newName) async {
    calls.add('rename:$path:$newName');
    _maybeFail();
  }

  @override
  Future<void> move(int session, String path, String targetFolder) async {
    calls.add('move:$path:$targetFolder');
    _maybeFail();
  }

  @override
  Future<void> trash(int session, String path) async {
    calls.add('trash:$path');
    _maybeFail();
  }

  @override
  Future<int> upload(
    int session,
    int transfer,
    String localPath,
    String targetFolder,
    String name,
  ) async {
    calls.add('upload:$targetFolder:$name');
    _maybeFail();
    await onUploadFile?.call(localPath);
    progressValues[transfer] = [10, 10];
    return 10;
  }

  @override
  Future<int> download(
    int session,
    int transfer,
    String remotePath,
    String localPath,
  ) async {
    calls.add('download:$remotePath');
    progressValues[transfer] = [5, 10];
    final gate = downloadGate;
    if (gate != null) {
      await gate.future;
      if (cancelled.contains(transfer)) {
        throw const RustCloudException(RustCloudErrorCode.cancelled);
      }
    }
    _maybeFail();
    await onDownloadFile?.call(localPath);
    progressValues[transfer] = [10, 10];
    return 10;
  }

  @override
  int newTransfer() => ++_next;

  @override
  List<int> progress(int transfer) => progressValues[transfer] ?? [0, 0];

  @override
  void cancel(int transfer) => cancelled.add(transfer);

  @override
  void release(int transfer) => released.add(transfer);

  @override
  void close(int session) => closed.add(session);
}
