import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/finder_location_service.dart';
import 'package:crisp_cloud/services/fuse_filesystem.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client implements CloudStorageClient {
  _Client({this.user = 'me'});
  final String user;
  bool connected = true;
  final uploads = <String, List<int>>{};

  @override
  String get providerName => 'Test';
  @override
  String? get userId => user;
  @override
  String? get bucketId => null;
  @override
  bool get isAuthenticated => connected;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'items': [
      {'name': 'a.txt', 'type': 'file', 'size': 3},
    ],
  };

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    uploads[targetPath == '/' ? '/$fileName' : '$targetPath/$fileName'] =
        fileData;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal client for the IPC framing used by the File Provider extension.
class _Ipc {
  _Ipc(this.socket) {
    socket.listen(_buffer.addAll);
  }
  final Socket socket;
  final _buffer = <int>[];
  var _id = 1;

  static Uint8List u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v);
  static List<int> str(String s) => [
    ...u32(utf8.encode(s).length),
    ...utf8.encode(s),
  ];

  Future<(int, List<int>)> call(int opcode, List<int> payload) async {
    final id = _id++;
    socket.add([
      ...u32(opcode),
      ...u32(id),
      ...u32(payload.length),
      ...payload,
    ]);
    await socket.flush();
    while (true) {
      if (_buffer.length >= 12) {
        final header = ByteData.sublistView(
          Uint8List.fromList(_buffer.sublist(0, 12)),
        );
        final length = header.getUint32(8);
        if (_buffer.length >= 12 + length) {
          expect(header.getUint32(0), id);
          final body = _buffer.sublist(12, 12 + length);
          _buffer.removeRange(0, 12 + length);
          return (header.getUint32(4), body);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory container;
  late List<MethodCall> calls;
  const channel = MethodChannel(FinderLocationService.channelName);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Short base path: Unix socket paths are limited to 104 bytes.
    container = await Directory('/tmp').createTemp('fl');
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'groupContainer' ? container.path : null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await container.delete(recursive: true);
  });

  test('adds a domain and serves the account on the group socket', () async {
    final service = FinderLocationService();
    final client = _Client();
    final location = await service.add(client, label: 'Test – me');
    expect(service.isServing(location.id), isTrue);
    expect(calls.map((c) => c.method), ['groupContainer', 'addDomain']);
    expect(calls.last.arguments, {
      'id': location.id,
      'displayName': 'Test – me',
    });

    final socketPath = '${container.path}/fp/${location.id}';
    expect(
      FileSystemEntity.typeSync(socketPath, followLinks: false),
      FileSystemEntityType.unixDomainSock,
    );
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final ipc = _Ipc(socket);
    final (errno, body) = await ipc.call(FuseOpcode.readdir, _Ipc.str('/'));
    expect(errno, 0);
    expect(utf8.decode(body.sublist(5, 10)), 'a.txt');

    // A discarded upload never reaches the provider; a released one does.
    var (e1, handle) = await ipc.call(FuseOpcode.create, _Ipc.str('/x.bin'));
    expect(e1, 0);
    await ipc.call(FuseOpcode.write, [
      ...handle,
      ...Uint8List(8),
      ..._Ipc.u32(2),
      1,
      2,
    ]);
    expect((await ipc.call(FuseOpcode.discard, handle)).$1, 0);
    (e1, handle) = await ipc.call(FuseOpcode.create, _Ipc.str('/y.bin'));
    await ipc.call(FuseOpcode.write, [
      ...handle,
      ...Uint8List(8),
      ..._Ipc.u32(1),
      7,
    ]);
    expect((await ipc.call(FuseOpcode.release, handle)).$1, 0);
    expect(client.uploads, {
      '/y.bin': [7],
    });
    await socket.close();

    // Persisted, and served again by a later session for the same account.
    final later = FinderLocationService();
    await service.dispose();
    await later.load();
    expect(later.locations.single.id, location.id);
    await later.attach(_Client(user: 'someone else'));
    expect(later.isServing(location.id), isFalse);
    await later.attach(_Client());
    expect(later.isServing(location.id), isTrue);
    expect(calls.last.method, 'signal');

    await later.remove(location.id);
    expect(later.locations, isEmpty);
    expect(calls.last.method, 'removeDomain');
    expect(
      FileSystemEntity.typeSync(socketPath, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('stops serving when the account disconnects', () async {
    final service = FinderLocationService();
    final client = _Client();
    final location = await service.add(client, label: '');
    expect(location.label, 'Test');
    client.connected = false;
    await service.attach(null);
    expect(service.isServing(location.id), isFalse);
    await service.dispose();
  });

  test('refuses a stale non-socket file at the socket path', () async {
    final service = FinderLocationService(random: _FixedRandom());
    await Directory('${container.path}/fp').create();
    await File('${container.path}/fp/0000002a').writeAsString('not a socket');
    await expectLater(
      service.add(_Client(), label: 'x'),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.locations, isEmpty);
  });
}

class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 42;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
