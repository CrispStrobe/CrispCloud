import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// An instance-scoped loopback server. It exposes bundled viewer assets only;
/// it cannot open arbitrary files, proxy URLs, or access provider credentials.
class EbookAssetServer {
  EbookAssetServer(this.session);
  final String session;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  static const _prefix = 'packages/crisp_ebook_reader/assets/';
  static const _policy =
      "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline' blob:; img-src blob: data:; font-src blob: data:; media-src blob: data:; frame-src blob:; connect-src 'self' blob: data:; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
  Future<Uri> start() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest.listAssets().where((key) => key.startsWith(_prefix)).toSet();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _subscription = _server!.listen((request) async {
      final response = request.response;
      try {
        final segments = request.uri.pathSegments;
        if (!['GET', 'HEAD'].contains(request.method) ||
            segments.length < 2 ||
            segments.first != session) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        final relative = segments.skip(1).join('/');
        final key = '$_prefix$relative';
        if (relative.contains('..') ||
            !assets.contains(key) ||
            (!relative.endsWith('.js') &&
                !relative.endsWith('.html') &&
                !relative.endsWith('.css'))) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        response.headers.set(
          'Content-Type',
          relative.endsWith('.js')
              ? 'application/javascript; charset=utf-8'
              : relative.endsWith('.css')
                  ? 'text/css; charset=utf-8'
                  : 'text/html; charset=utf-8',
        );
        response.headers.set('X-Content-Type-Options', 'nosniff');
        response.headers.set('Content-Security-Policy', _policy);
        response.headers.set('Cache-Control', 'no-store');
        response.headers.set('Referrer-Policy', 'no-referrer');
        if (request.method == 'GET') {
          final bytes = await rootBundle.load(key);
          response.add(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
        }
      } catch (_) {
        response.statusCode = HttpStatus.internalServerError;
      }
      await response.close();
    });
    return Uri.parse(
      'http://127.0.0.1:${_server!.port}/$session/index.html#$session',
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
    _server = null;
  }
}
