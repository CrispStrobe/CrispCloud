import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/azure_blob_adapter.dart';
import 'package:crisp_cloud/services/azure_config_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fuse_filesystem.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _CloudClient implements CloudStorageClient {
  final int fileSize;
  final Map<String, dynamic>? listing;
  final bool resolveFiles;
  int downloadCount = 0;
  _CloudClient({this.fileSize = 5, this.listing, this.resolveFiles = true});

  @override
  String get providerName => 'Test';

  // A legacy adapter may advertise streaming yet buffer its default stream.
  @override
  bool get supportsStreaming => true;

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      resolveFiles && path == '/remote/café.txt'
      ? {'name': 'café.txt', 'type': 'file', 'size': fileSize}
      : null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async =>
      listing ??
      {
        'items': [
          {'name': 'café.txt', 'type': 'file', 'size': fileSize},
        ],
      };

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloadCount++;
    return Uint8List.fromList(utf8.encode('hello'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedListingClient extends _CloudClient {
  final listingStarted = Completer<void>();
  final listingResult = Completer<Map<String, dynamic>>();
  final listedPaths = <String>[];

  @override
  Future<Map<String, dynamic>> listPath(String path) {
    listedPaths.add(path);
    if (!listingStarted.isCompleted) listingStarted.complete();
    return listingResult.future;
  }
}

class _RangeClient extends _CloudClient implements CloudStorageRangeReader {
  final calls = <(int, int)>[];
  _RangeClient() : super(fileSize: 1024 * 1024 * 1024 + 7);

  // Deliberately false: FUSE must use the explicit range capability.
  @override
  bool get supportsStreaming => false;

  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) async {
    calls.add((offset, length));
    final count = (fileSize - offset).clamp(0, length);
    return Uint8List.fromList(
      List.generate(count, (index) => (offset + index) % 251),
    );
  }
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
        return {
          'folders': [],
          'files': [
            {'name': 'café.txt', 'size': 5},
            {'name': 'cafe\u0301.txt', 'size': 5},
          ],
        };
      }
      return {
        'folders': [
          {'name': 'résumé'},
        ],
        'files': [],
      };
    }
    if (path == '/remote/résumé') {
      return {
        'folders': [],
        'files': [
          {'name': 'café.txt', 'size': 5},
        ],
      };
    }
    throw StateError('Unexpected provider path: $path');
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloadedPath = remotePath;
    return Uint8List.fromList(utf8.encode('hello'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ResponseReader {
  final Socket socket;
  final _bytes = <int>[];
  final closed = Completer<void>();
  Completer<void>? _updated;

  _ResponseReader(this.socket) {
    socket.listen((chunk) {
      _bytes.addAll(chunk);
      _updated?.complete();
      _updated = null;
    }, onDone: () => closed.complete());
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
      await take(response.getUint32(8, Endian.big)),
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
  test('Azure mounts large blobs through its bounded range capability', () async {
    final client = AzureBlobAdapter(
      config: AzureConfigService(secureStorage: InMemorySecureStorage()),
    );
    await client.loginWithKey(accountName: 'account', accountKey: 'a2V5');
    const fileSize = 1024 * 1024 * 1024;
    const offset = 128 * 1024 * 1024;
    const window = 256 * 1024;
    final requestedRanges = <String?>[];
    await http.runWithClient(
      () async {
        final fs = FuseFilesystem(client: client, remotePath: '/container');
        unawaited(fs.serveRequests());
        final socket = await Socket.connect(
          InternetAddress(await fs.ready, type: InternetAddressType.unix),
          0,
        );
        final reader = _ResponseReader(socket);
        try {
          final (openError, opened) = await reader.send(
            FuseOpcode.open,
            1,
            _path('/huge.bin', 0),
          );
          expect(openError, 0);
          final request = Uint8List(16);
          ByteData.sublistView(request)
            ..setUint32(
              0,
              ByteData.sublistView(opened).getUint32(0, Endian.big),
              Endian.big,
            )
            ..setUint64(4, offset, Endian.big)
            ..setUint32(12, 4, Endian.big);
          final (readError, bytes) = await reader.send(
            FuseOpcode.read,
            2,
            request,
          );
          expect(readError, 0);
          expect(bytes, [0, 1, 2, 3]);
          expect(requestedRanges, ['bytes=$offset-${offset + window - 1}']);
        } finally {
          socket.destroy();
          await fs.dispose();
        }
      },
      () => MockClient((request) async {
        if (request.url.queryParameters['comp'] == 'list') {
          return http.Response(
            '<EnumerationResults><Blobs><Blob><Name>huge.bin</Name>'
            '<Properties><Content-Length>$fileSize</Content-Length></Properties>'
            '</Blob></Blobs></EnumerationResults>',
            200,
          );
        }
        requestedRanges.add(request.headers['Range']);
        expect(request.url.path, '/container/huge.bin');
        expect(
          request.headers['Authorization'],
          startsWith('SharedKey account:'),
        );
        return http.Response.bytes(
          List.generate(window, (index) => index % 251),
          206,
          headers: {
            'content-range': 'bytes $offset-${offset + window - 1}/$fileSize',
          },
        );
      }),
    );
  });

  test(
    'disposing during listener startup never reports a ready mount',
    () async {
      final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
      // Subscribe before startup so the expected ready error is always handled.
      final readiness = expectLater(fs.ready, throwsA(anything));
      final serving = fs.serveRequests();
      final disposal = fs.dispose();
      // Concurrent disposal must share the same shutdown and resource cleanup.
      expect(identical(disposal, fs.dispose()), isTrue);
      await disposal.timeout(const Duration(seconds: 3));
      await serving.timeout(const Duration(seconds: 3));
      await readiness;
    },
  );

  test('a disposed filesystem cannot start a new listener', () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    await fs.dispose();
    final readiness = expectLater(fs.ready, throwsA(anything));
    await fs.serveRequests().timeout(const Duration(seconds: 3));
    await readiness;
  });

  test(
    'disposing the filesystem closes all accepted helper connections',
    () async {
      final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
      final serving = fs.serveRequests();
      final address = InternetAddress(
        await fs.ready,
        type: InternetAddressType.unix,
      );
      final sockets = <Socket>[];
      final readers = <_ResponseReader>[];
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await fs.dispose();
      });
      for (var i = 0; i < 2; i++) {
        final socket = await Socket.connect(address, 0);
        sockets.add(socket);
        final reader = _ResponseReader(socket);
        readers.add(reader);
        // A response confirms the server accepted this connection.
        expect((await reader.send(FuseOpcode.getattr, 1, _path('/'))).$1, 0);
      }
      await fs.dispose();
      await Future.wait(readers.map((reader) => reader.closed.future))
          .timeout(const Duration(seconds: 3));
      await serving.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'shutdown does not wait for a pending provider request or write its reply',
    () async {
      final client = _DelayedListingClient();
      final fs = FuseFilesystem(client: client, remotePath: '/remote');
      final serving = fs.serveRequests();
      final socket = await Socket.connect(
        InternetAddress(await fs.ready, type: InternetAddressType.unix),
        0,
      );
      final reader = _ResponseReader(socket);
      addTearDown(() async {
        socket.destroy();
        await fs.dispose();
      });
      final payload = _path('/folder/café.txt', 0);
      final header = ByteData(12)
        ..setUint32(0, FuseOpcode.open, Endian.big)
        ..setUint32(4, 9, Endian.big)
        ..setUint32(8, payload.length, Endian.big);
      socket.add([...header.buffer.asUint8List(), ...payload]);
      await client.listingStarted.future.timeout(const Duration(seconds: 3));
      await fs.dispose().timeout(const Duration(seconds: 3));
      await reader.closed.future.timeout(const Duration(seconds: 3));
      // The eventual provider completion must not write into a destroyed socket
      // or surface an unhandled asynchronous error after unmount.
      client.listingResult.complete({
        'items': [
          {'name': 'folder', 'type': 'folder'},
        ],
      });
      await pumpEventQueue();
      expect(client.listedPaths, ['/remote']);
      await serving;
    },
  );

  test('IPC rejects oversized frames from the header alone', () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
      InternetAddress(await fs.ready, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      socket.destroy();
      await fs.dispose();
    });
    final header = ByteData(12)
      ..setUint32(0, FuseOpcode.getattr, Endian.big)
      ..setUint32(4, 77, Endian.big)
      ..setUint32(8, FuseFilesystem.maxRequestPayloadBytes + 1, Endian.big);
    // No body follows: the server must reject without waiting for it.
    socket.add(header.buffer.asUint8List());
    final response = ByteData.sublistView(await reader.take(12));
    expect(response.getUint32(0, Endian.big), 77);
    expect(response.getUint32(4, Endian.big), 22);
    expect(response.getUint32(8, Endian.big), 0);
  });

  test('IPC rejects malformed path encodings and remains usable', () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
      InternetAddress(await fs.ready, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    final malformed = <Uint8List>[
      Uint8List(0),
      Uint8List.fromList([0, 0, 0, 5, 47]), // Truncated path.
      Uint8List.fromList([0, 0, 0, 1, 255]), // Invalid UTF-8.
      _path('/bad\x00name'),
    ];
    var id = 1;
    for (final payload in malformed) {
      expect((await reader.send(FuseOpcode.getattr, id++, payload)).$1, 22);
    }
    expect((await reader.send(FuseOpcode.getattr, id, _path('/'))).$1, 0);
  });

  test(
    'IPC resolves normalized nested paths using original provider names',
    () async {
      final client = _UnicodeClient();
      final fs = FuseFilesystem(client: client, remotePath: '/remote');
      unawaited(fs.serveRequests());
      final socket = await Socket.connect(
        InternetAddress(await fs.ready, type: InternetAddressType.unix),
        0,
      );
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
        ..setUint32(
          0,
          ByteData.sublistView(opened).getUint32(0, Endian.big),
          Endian.big,
        )
        ..setUint64(4, 0, Endian.big)
        ..setUint32(12, 5, Endian.big);
      final (readError, bytes) = await reader.send(3, 4, request);
      expect(readError, 0);
      expect(utf8.decode(bytes), 'hello');
      expect(client.downloadedPath, '/remote/résumé/café.txt');
    },
  );

  test('IPC refuses ambiguous canonical filename collisions', () async {
    final fs = FuseFilesystem(
      client: _UnicodeClient(collisions: true),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socket = await Socket.connect(
      InternetAddress(await fs.ready, type: InternetAddressType.unix),
      0,
    );
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
      InternetAddress(await fs.ready, type: InternetAddressType.unix),
      0,
    );
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
      client: _CloudClient(
        resolveFiles: false,
        listing: {
          'folders': [
            {'name': 'folder'},
          ],
          'files': [
            {'name': 'café.txt', 'size': 5},
          ],
        },
      ),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
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
      ..setUint32(
        0,
        ByteData.sublistView(opened).getUint32(0, Endian.big),
        Endian.big,
      )
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
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });

    final (openError, opened) = await reader.send(13, 1, _path('/café.txt', 0));
    expect(openError, 0);
    final readRequest = Uint8List(16);
    ByteData.sublistView(readRequest)
      ..setUint32(
        0,
        ByteData.sublistView(opened).getUint32(0, Endian.big),
        Endian.big,
      )
      ..setUint64(4, 3, Endian.big)
      ..setUint32(12, 10, Endian.big);
    for (var id = 2; id <= 3; id++) {
      final (error, bytes) = await reader.send(3, id, readRequest);
      expect(error, 0);
      expect(utf8.decode(bytes), 'lo');
    }
    expect(client.downloadCount, 1);
  });

  test(
    'IPC readdir preserves UTF-8 names and includes split folders',
    () async {
      final fs = FuseFilesystem(
        client: _CloudClient(
          listing: {
            'folders': [
              {'name': '旅行😀'},
            ],
            'files': [
              {'name': 'café.txt', 'size': 5},
            ],
          },
        ),
        remotePath: '/remote',
      );
      unawaited(fs.serveRequests());
      final socketPath = await fs.ready;
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
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
    },
  );

  test('IPC readdir rejects names longer than the wire format', () async {
    final fs = FuseFilesystem(
      client: _CloudClient(
        listing: {
          'items': [
            {'name': '😀' * 64},
          ],
        },
      ),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect(
      (await reader.send(2, 1, _path('/'))).$1,
      Platform.isMacOS ? 63 : 36,
    ); // ENAMETOOLONG
  });

  test(
    'IPC opens and reads a UTF-8 cloud file, then releases the handle',
    () async {
      final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
      unawaited(fs.serveRequests());
      final socketPath = await fs.ready;
      expect((await Directory(socketPath).parent.stat()).mode & 0x1ff, 0x1c0);
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      final reader = _ResponseReader(socket);
      addTearDown(() async {
        await socket.close();
        await fs.dispose();
      });

      final (attrError, attr) = await reader.send(1, 1, _path('/café.txt'));
      expect(attrError, 0);
      expect(ByteData.sublistView(attr).getUint64(4, Endian.big), 5);

      final (openError, opened) = await reader.send(
        13,
        2,
        _path('/café.txt', 0),
      );
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
    },
  );

  test('IPC returns ENOENT and EROFS instead of a generic I/O error', () async {
    final fs = FuseFilesystem(client: _CloudClient(), remotePath: '/remote');
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(1, 1, _path('/missing'))).$1, 2);
    expect((await reader.send(13, 2, _path('/café.txt', 1))).$1, 30);
    expect((await reader.send(7, 3, _path('/café.txt'))).$1, 30);
  });

  test('IPC ignores streaming flag and rejects large buffered files', () async {
    final fs = FuseFilesystem(
      client: _CloudClient(fileSize: FuseFilesystem.maxReadFileBytes + 1),
      remotePath: '/remote',
    );
    unawaited(fs.serveRequests());
    final socketPath = await fs.ready;
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final reader = _ResponseReader(socket);
    addTearDown(() async {
      await socket.close();
      await fs.dispose();
    });
    expect((await reader.send(13, 1, _path('/café.txt', 0))).$1, 27);
  });
  test(
    'IPC range reads large files with bounded random access and cached EOF',
    () async {
      final client = _RangeClient();
      final fs = FuseFilesystem(client: client, remotePath: '/remote');
      unawaited(fs.serveRequests());
      final socketPath = await fs.ready;
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      final reader = _ResponseReader(socket);
      addTearDown(() async {
        await socket.close();
        await fs.dispose();
      });
      final (openError, opened) = await reader.send(
        13,
        1,
        _path('/café.txt', 0),
      );
      expect(openError, 0);
      final handle = ByteData.sublistView(opened).getUint32(0, Endian.big);
      var id = 2;
      Future<Uint8List> read(int offset, int length) async {
        final request = Uint8List(16);
        ByteData.sublistView(request)
          ..setUint32(0, handle, Endian.big)
          ..setUint64(4, offset, Endian.big)
          ..setUint32(12, length, Endian.big);
        final (error, bytes) = await reader.send(3, id++, request);
        expect(error, 0);
        return bytes;
      }

      const offset = FuseFilesystem.maxReadFileBytes + 29;
      expect(
        await read(offset, 8),
        List.generate(8, (index) => (offset + index) % 251),
      );
      expect(
        await read(offset + 2, 3),
        List.generate(3, (index) => (offset + 2 + index) % 251),
      );
      expect(client.calls, [(offset, 256 * 1024)]);
      final end = client.fileSize - 3;
      expect(
        await read(end, 100),
        List.generate(3, (index) => (end + index) % 251),
      );
      // Even the maximum legal request may finish early at genuine EOF.
      expect(
        await read(end, FuseFilesystem.maxReadRequestBytes),
        List.generate(3, (index) => (end + index) % 251),
      );
      expect(await read(client.fileSize, 100), isEmpty);
      expect(client.calls.length, 2);
      // Seeking backward must fetch the requested bytes, even after cached EOF.
      expect(await read(0, 4), [0, 1, 2, 3]);
      expect(client.calls.last, (0, 256 * 1024));
      // Native FUSE may request more than 1 MiB. Assemble the full response
      // from bounded provider reads rather than returning a short non-EOF read.
      final across = await read(256 * 1024 - 2, 2 * 1024 * 1024 + 4);
      expect(across.length, 2 * 1024 * 1024 + 4);
      expect(
        across,
        List.generate(across.length, (index) => (256 * 1024 - 2 + index) % 251),
      );
      expect(client.calls.every((call) => call.$2 <= 256 * 1024), isTrue);
      expect(client.downloadCount, 0);
      final oversized = Uint8List(16);
      ByteData.sublistView(oversized)
        ..setUint32(0, handle, Endian.big)
        ..setUint64(4, 0, Endian.big)
        ..setUint32(12, FuseFilesystem.maxReadRequestBytes + 1, Endian.big);
      expect((await reader.send(3, id++, oversized)).$1, 22);
      expect((await reader.send(13, id++, _path('/café.txt', 1))).$1, 30);
    },
  );
}
