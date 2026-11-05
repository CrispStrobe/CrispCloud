import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fuse_filesystem.dart';
import 'package:flutter_test/flutter_test.dart';

class _CloudClient implements CloudStorageClient {
  final int fileSize;
  final Map<String, dynamic>? listing;
  final bool resolveFiles;
  int downloadCount = 0;
  _CloudClient({this.fileSize = 5, this.listing, this.resolveFiles = true});

  @override
  String get providerName => 'Test';

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      resolveFiles && path == '/remote/café.txt'
          ? {'name': 'café.txt', 'type': 'file', 'size': fileSize}
          : null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => listing ?? {
        'items': [
          {'name': 'café.txt', 'type': 'file', 'size': fileSize}
        ]
      };

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    downloadCount++;
    return Uint8List.fromList(utf8.encode('hello'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnicodeClient implements CloudStorageClient {
  final bool collisions;
  String? downloadedPath;
  _UnicodeClient({this.collisions = false});

  @override
  String get providerName => 'Unicode fixture';
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (path == '/remote') {
      if (collisions) {
        return {'folders': [], 'files': [
          {'name': 'café.txt', 'size': 5},
          {'name': 'cafe\u0301.txt', 'size': 5},
        ]};
      }
      return {'folders': [{'name': 'résumé'}], 'files': []};
    }
    if (path == '/remote/résumé') {
      return {'folders': [], 'files': [{'name': 'café.txt', 'size': 5}]};
    }
    throw StateError('Unexpected provider path: $path');
  }
  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    downloadedPath = remotePath;
    return Uint8List.fromList(utf8.encode('hello'));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ResponseReader {
  final Socket socket;
  final _bytes = <int>[];
  Completer<void>? _updated;

  _ResponseReader(this.socket) {
    socket.listen((chunk) {
      _bytes.addAll(chunk);
      _updated?.complete();
      _updated = null;
    });
  }

  Future<Uint8List> take(int count) async {
    while (_bytes.length < count) {
      _updated = Completer<void>();
      await _updated!.future.timeout(const Duration(seconds: 3));
    }
    final result = Uint8List.fromList(_bytes.sublist(0, count));
    _bytes.removeRange(0, count);
    return result;
  }

  Future<(int, Uint8List)> send(int opcode, int id, Uint8List payload) async {
    final header = ByteData(12)
      ..setUint32(0, opcode, Endian.big)
      ..setUint32(4, id, Endian.big)
      ..setUint32(8, payload.length, Endian.big);
    socket.add([...header.buffer.asUint8List(), ...payload]);
    final response = ByteData.sublistView(await take(12));
    expect(response.getUint32(0, Endian.big), id);
    return (
      response.getUint32(4, Endian.big),
      await take(response.getUint32(8, Endian.big))
    );
  }
}

Uint8List _path(String path, [int? flags]) {
  final bytes = utf8.encode(path);
  final result = Uint8List(4 + bytes.length + (flags == null ? 0 : 4));
  ByteData.sublistView(result).setUint32(0, bytes.length, Endian.big);
  result.setAll(4, bytes);
  if (flags != null) {
    ByteData.sublistView(result).setUint32(4 + bytes.length, flags, Endian.big);
  }
  return result;
}

void main() {
  test('IPC resolves normalized nested paths using original provider names', () async {
    final client = _UnicodeClient();
    final fs = FuseFilesystem(client: client, remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
        InternetAddress(await fs.ready, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(2, 1, _path('/re\u0301sume\u0301'))).$1, 0);
    const requested = '/re\u0301sume\u0301/cafe\u0301.txt';
    final (attrError, attr) = await reader.send(1, 2, _path(requested));
    expect(attrError, 0);
    expect(ByteData.sublistView(attr).getUint64(4, Endian.big), 5);
    final (openError, opened) = await reader.send(13, 3, _path(requested, 0));
    expect(openError, 0);
    final request = Uint8List(16);
    ByteData.sublistView(request)
      ..setUint32(0, ByteData.sublistView(opened).getUint32(0, Endian.big), Endian.big)
      ..setUint64(4, 0, Endian.big)
      ..setUint32(12, 5, Endian.big);
    final (readError, bytes) = await reader.send(3, 4, request);
    expect(readError, 0);
    expect(utf8.decode(bytes), 'hello');
    expect(client.downloadedPath, '/remote/résumé/café.txt');
  });

  test('IPC refuses ambiguous canonical filename collisions', () async {
    final fs = FuseFilesystem(client: _UnicodeClient(collisions: true), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
        InternetAddress(await fs.ready, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(2, 1, _path('/'))).$1, 17); // EEXIST
    expect((await reader.send(1, 2, _path('/café.txt'))).$1, 17);
    expect((await reader.send(13, 3, _path('/cafe\u0301.txt', 0))).$1, 17);
  });

  test('IPC rejects traversal outside the mounted remote root', () async {
    final fs = FuseFilesystem(client: _UnicodeClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
        InternetAddress(await fs.ready, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(1, 1, _path('/../outside'))).$1, 13); // EACCES
    expect((await reader.send(13, 2, _path('/../outside', 0))).$1, 13);
  });

  test('IPC gets metadata and opens files from provider listings', () async {
    final fs = FuseFilesystem(
      client: _CloudClient(resolveFiles: false, listing: {
        'folders': [{'name': 'folder'}],
        'files': [{'name': 'café.txt', 'size': 5}],
      }),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    final (error, attr) = await reader.send(1, 1, _path('/café.txt'));
    expect(error, 0);
    expect(ByteData.sublistView(attr).getUint64(4, Endian.big), 5);
    final (openError, opened) = await reader.send(13, 2, _path('/café.txt', 0));
    expect(openError, 0);
    final request = Uint8List(16);
    ByteData.sublistView(request)
      ..setUint32(0, ByteData.sublistView(opened).getUint32(0, Endian.big), Endian.big)
      ..setUint64(4, 0, Endian.big)
      ..setUint32(12, 5, Endian.big);
    final (readError, data) = await reader.send(3, 4, request);
    expect(readError, 0);
    expect(utf8.decode(data), 'hello');
    expect((await reader.send(13, 3, _path('/folder', 0))).$1, 21);
  });

  test('IPC repeated reads across EOF reuse the cached file', () async {
    final client = _CloudClient();
    final fs = FuseFilesystem(client: client, remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });

    final (openError, opened) = await reader.send(13, 1, _path('/café.txt', 0));
    expect(openError, 0);
    final readRequest = Uint8List(16);
    ByteData.sublistView(readRequest)
      ..setUint32(0, ByteData.sublistView(opened).getUint32(0, Endian.big), Endian.big)
      ..setUint64(4, 3, Endian.big)
      ..setUint32(12, 10, Endian.big);
    for (var id = 2; id <= 3; id++) {
      final (error, bytes) = await reader.send(3, id, readRequest);
      expect(error, 0);
      expect(utf8.decode(bytes), 'lo');
    }
    expect(client.downloadCount, 1);
  });

  test('IPC readdir preserves UTF-8 names and includes split folders', () async {
    final fs = FuseFilesystem(
      client: _CloudClient(listing: {
        'folders': [
          {'name': '旅行😀'},
        ],
        'files': [
          {'name': 'café.txt', 'size': 5},
        ],
      }),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });

    final (error, payload) = await reader.send(2, 1, _path('/'));
    expect(error, 0);
    final data = ByteData.sublistView(payload);
    expect(data.getUint32(0, Endian.big), 2);
    var offset = 4;
    final names = <String, int>{};
    for (var i = 0; i < 2; i++) {
      final length = payload[offset++];
      final name = utf8.decode(payload.sublist(offset, offset + length));
      offset += length;
      names[name] = data.getUint32(offset, Endian.big);
      offset += 24;
    }
    expect(offset, payload.length);
    expect(names['旅行😀']! & 0xf000, 0x4000);
    expect(names['café.txt']! & 0xf000, 0x8000);
  });

  test('IPC readdir rejects names longer than the wire format', () async {
    final fs = FuseFilesystem(
      client: _CloudClient(listing: {
        'items': [
          {'name': '😀' * 64},
        ],
      }),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(2, 1, _path('/'))).$1,
        Platform.isMacOS ? 63 : 36); // ENAMETOOLONG
  });

  test('IPC opens and reads a UTF-8 cloud file, then releases the handle',
      () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    expect((await Directory(socketPath).parent.stat()).mode & 0x1ff, 0x1c0);
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });

    final (attrError, attr) = await reader.send(1, 1, _path('/café.txt'));
    expect(attrError, 0);
    expect(ByteData.sublistView(attr).getUint64(4, Endian.big), 5);

    final (openError, opened) = await reader.send(13, 2, _path('/café.txt', 0));
    expect(openError, 0);
    final handle = ByteData.sublistView(opened).getUint32(0, Endian.big);

    final readRequest = Uint8List(16);
    final readView = ByteData.sublistView(readRequest)
      ..setUint32(0, handle, Endian.big)
      ..setUint64(4, 1, Endian.big)
      ..setUint32(12, 3, Endian.big);
    expect(readView.getUint32(12, Endian.big), 3);
    final (readError, readBytes) = await reader.send(3, 3, readRequest);
    expect(readError, 0);
    expect(utf8.decode(readBytes), 'ell');

    final release = Uint8List(4);
    ByteData.sublistView(release).setUint32(0, handle, Endian.big);
    expect((await reader.send(10, 4, release)).$1, 0);
    expect((await reader.send(3, 5, readRequest)).$1, 9); // EBADF
  });

  test('IPC returns ENOENT and EROFS instead of a generic I/O error', () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(1, 1, _path('/missing'))).$1, 2);
    expect((await reader.send(13, 2, _path('/café.txt', 1))).$1, 30);
    expect((await reader.send(7, 3, _path('/café.txt'))).$1, 30);
  });

  test('IPC rejects a file over the in-memory read limit before download',
      () async {
    final fs = FuseFilesystem(
        client: _CloudClient(fileSize: FuseFilesystem.maxReadFileBytes + 1),
        remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(13, 1, _path('/café.txt', 0))).$1, 27);
  });
}
