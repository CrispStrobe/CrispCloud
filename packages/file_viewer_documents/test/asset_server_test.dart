// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_viewer_documents/src/hosts/asset_server.dart';
import 'package:file_viewer_documents/src/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = '0123456789abcdef0123456789abcdef';
const _prefix = 'packages/file_viewer_documents/assets/';

class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle(this.assets, {this.manifestReady});
  final Map<String, List<int>> assets;
  final Future<void>? manifestReady;
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    if (key == 'AssetManifest.bin') {
      await manifestReady;
      return const StandardMessageCodec().encodeMessage({
        for (final path in assets.keys)
          path: [
            {'asset': path},
          ],
      })!;
    }
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing fixture asset');
    // Exercise non-zero ByteData offsets as real AssetBundles may return views.
    final padded = Uint8List(bytes.length + 4)
      ..setRange(2, bytes.length + 2, bytes);
    return ByteData.sublistView(padded, 2, bytes.length + 2);
  }
}

class _RealHttp extends HttpOverrides {}

Future<({int status, List<int> bytes, HttpHeaders headers})> _request(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const {},
}) => HttpOverrides.runWithHttpOverrides(() async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.openUrl(method, uri.removeFragment());
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      [],
      (out, next) => out..addAll(next),
    );
    return (
      status: response.statusCode,
      bytes: bytes,
      headers: response.headers,
    );
  } finally {
    client.close(force: true);
  }
}, _RealHttp());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _MemoryBundle bundle() => _MemoryBundle({
    '${_prefix}index.html': utf8.encode('<html>local viewer</html>'),
    '${_prefix}runtime/engine.js': utf8.encode('export const ready=true;'),
    '${_prefix}runtime/engine.wasm': [0, 97, 115, 109, 1, 0, 0, 0],
    '${_prefix}licenses/notice.txt': utf8.encode('fixture notice'),
    'private-provider-file.txt': utf8.encode('must not be served'),
  });

  test(
    'serves only bundled assets with worker/WASM MIME and restrictive headers',
    () async {
      final assets = bundle();
      final server = DocumentAssetServer(_session, bundle: assets);
      addTearDown(server.close);
      final uri = await server.start();
      expect(uri.host, '127.0.0.1');
      expect(uri.fragment, _session);
      final index = await _request(uri);
      expect(index.status, HttpStatus.ok);
      expect(utf8.decode(index.bytes), '<html>local viewer</html>');
      expect(index.headers.value('cache-control'), 'no-store');
      expect(index.headers.value('x-content-type-options'), 'nosniff');
      expect(
        index.headers.value('content-security-policy'),
        contains("frame-src blob:"),
      );
      expect(
        index.headers.value('content-security-policy'),
        contains("object-src 'none'"),
      );
      expect(index.headers.value('permissions-policy'), contains('camera=()'));
      final wasm = await _request(uri.resolve('runtime/engine.wasm'));
      expect(wasm.status, HttpStatus.ok);
      expect(wasm.bytes, [0, 97, 115, 109, 1, 0, 0, 0]);
      expect(wasm.headers.contentType!.mimeType, 'application/wasm');
      final script = await _request(
        uri.resolve('runtime/engine.js'),
        method: 'HEAD',
      );
      expect(script.status, HttpStatus.ok);
      expect(script.bytes, isEmpty);
      expect(script.headers.contentType!.mimeType, 'application/javascript');
      expect(
        assets.loads.where((key) => key == '${_prefix}runtime/engine.js'),
        isEmpty,
      );
    },
  );

  test(
    'rejects other sessions, origins, hosts, methods and unlisted paths',
    () async {
      final assets = bundle();
      final server = DocumentAssetServer(_session, bundle: assets);
      addTearDown(server.close);
      final uri = await server.start();
      final cases = [
        uri.replace(path: '/other/index.html'),
        uri.resolve('private-provider-file.txt'),
        uri.resolve('runtime/missing.js'),
        uri.replace(path: '/$_session/runtime%2fengine.js'),
        uri.replace(query: 'cache=other'),
      ];
      for (final candidate in cases) {
        expect(
          (await _request(candidate)).status,
          HttpStatus.notFound,
          reason: candidate.toString(),
        );
      }
      for (final headers in [
        {'Origin': 'https://remote.invalid'},
        {'Host': 'remote.invalid'},
        {'Sec-Fetch-Site': 'cross-site'},
      ]) {
        expect(
          (await _request(uri, headers: headers)).status,
          HttpStatus.notFound,
        );
      }
      expect((await _request(uri, method: 'POST')).status, HttpStatus.notFound);
      expect(assets.loads.where((key) => key != 'AssetManifest.bin'), isEmpty);
    },
  );

  test('shares one startup and cannot restart a disposed server', () async {
    final server = DocumentAssetServer(_session, bundle: bundle());
    final first = server.start();
    final second = server.start();
    expect(identical(first, second), isTrue);
    expect(await first, await second);
    await server.close();
    await server.close();
    await expectLater(server.start(), throwsStateError);
  });

  test(
    'font routes expose only exact configured manifest keys and correct MIME',
    () async {
      final assets = _MemoryBundle({
        '${_prefix}index.html': [1],
        'packages/office/fonts/Regular.ttf': [0, 1, 2, 3],
        'assets/fonts/Bold.otf': [4, 5, 6],
        'assets/fonts/Web.woff2': [7, 8],
        'assets/fonts/Unlisted.ttf': [90, 91],
        'assets/private.txt': [92],
      });
      final server = DocumentAssetServer(
        _session,
        bundle: assets,
        fonts: const [
          DocumentPreviewFont(
            asset: 'packages/office/fonts/Regular.ttf',
            family: 'Regular',
            aliases: ['Arial'],
          ),
          DocumentPreviewFont(
            asset: 'assets/fonts/Bold.otf',
            family: 'Bold',
            weight: 700,
          ),
          DocumentPreviewFont(asset: 'assets/fonts/Web.woff2', family: 'Web'),
          DocumentPreviewFont(
            asset: 'assets/fonts/Missing.ttf',
            family: 'Missing',
          ),
        ],
      );
      addTearDown(server.close);
      expect(() => server.fontDescriptors, throwsStateError);
      final location = await server.start();
      final descriptors = server.fontDescriptors;
      expect(descriptors, hasLength(3));
      expect(descriptors.first['aliases'], ['Arial']);
      expect(descriptors[1]['weight'], 700);
      expect(assets.loads, ['AssetManifest.bin']);
      for (final (index, extension, mime, bytes) in [
        (0, 'ttf', 'font/ttf', [0, 1, 2, 3]),
        (1, 'otf', 'font/otf', [4, 5, 6]),
        (2, 'woff2', 'font/woff2', [7, 8]),
      ]) {
        final uri = Uri.parse(descriptors[index]['url'] as String);
        expect(uri, location.resolve('fonts/$index.$extension'));
        final head = await _request(uri, method: 'HEAD');
        expect(head.status, HttpStatus.ok);
        expect(head.bytes, isEmpty);
        final response = await _request(uri);
        expect(response.status, HttpStatus.ok);
        expect(response.bytes, bytes);
        expect(response.headers.contentType!.mimeType, mime);
        expect(response.headers.value('x-content-type-options'), 'nosniff');
        expect(response.headers.value('access-control-allow-origin'), isNull);
      }
      for (final candidate in [
        location.resolve('fonts/3.ttf'),
        location.resolve('fonts/0.otf'),
        location.resolve('fonts/Regular.ttf'),
        location.resolve('assets/fonts/Unlisted.ttf'),
        location.resolve('packages/office/fonts/Regular.ttf'),
        location.resolve('fonts/../assets/private.txt'),
        location.replace(path: '/$_session/fonts%2f0.ttf'),
        location.replace(path: '/$_session/fonts/%2e%2e/0.ttf'),
        location.resolve('fonts/0.ttf?query=1'),
        location.replace(path: '/another-session/fonts/0.ttf'),
      ]) {
        expect(
          (await _request(candidate)).status,
          HttpStatus.notFound,
          reason: candidate.toString(),
        );
      }
      for (final headers in [
        {'Origin': 'https://remote.invalid'},
        {'Host': 'remote.invalid'},
        {'Sec-Fetch-Site': 'cross-site'},
      ]) {
        expect(
          (await _request(
            location.resolve('fonts/0.ttf'),
            headers: headers,
          )).status,
          HttpStatus.notFound,
        );
      }
      expect(assets.loads, isNot(contains('assets/fonts/Unlisted.ttf')));
      expect(assets.loads, isNot(contains('assets/private.txt')));
      await server.close();
      expect(() => server.fontDescriptors, throwsStateError);
    },
  );

  test(
    'closing during asset loading prevents a later listener from opening',
    () async {
      final ready = Completer<void>();
      final assets = _MemoryBundle({
        '${_prefix}index.html': [1],
      }, manifestReady: ready.future);
      final server = DocumentAssetServer(_session, bundle: assets);
      final opening = server.start();
      final rejected = expectLater(opening, throwsStateError);
      await server.close();
      ready.complete();
      await rejected;
    },
  );

  test(
    'fails immediately when runtime assets or session identity are absent',
    () async {
      expect(() => DocumentAssetServer('invalid'), throwsArgumentError);
      final server = DocumentAssetServer(_session, bundle: _MemoryBundle({}));
      addTearDown(server.close);
      await expectLater(
        server.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('assets are missing'),
          ),
        ),
      );
    },
  );
}
