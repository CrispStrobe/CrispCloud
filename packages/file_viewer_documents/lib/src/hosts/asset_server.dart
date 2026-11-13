// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for bounded document assets, request validation and startup/disposal races.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'host_policy.dart';

/// An instance-scoped loopback server. Only allowlisted bundled assets are read;
/// provider files, arbitrary URLs and credentials never enter this server.
class DocumentAssetServer {
  DocumentAssetServer(this.session, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle {
    if (!isDocumentHostSession(session)) {
      throw ArgumentError.value(
        session,
        'session',
        'Invalid document session.',
      );
    }
  }

  final String session;
  final AssetBundle _bundle;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Future<Uri>? _starting;
  bool _closed = false;
  static const _prefix = 'packages/file_viewer_documents/assets/';
  static const _policy =
      "default-src 'none'; script-src 'self' 'wasm-unsafe-eval' blob:; style-src 'self' 'unsafe-inline' blob:; img-src 'self' blob: data:; font-src 'self' blob: data:; media-src blob: data:; frame-src blob:; connect-src 'self' blob: data:; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; form-action 'none'";

  Future<Uri> start() {
    if (_closed) {
      return Future.error(StateError('The document asset server has closed.'));
    }
    return _starting ??= _start();
  }

  Future<Uri> _start() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    final assets = manifest
        .listAssets()
        .where((key) => key.startsWith(_prefix))
        .toSet();
    if (!assets.contains('${_prefix}index.html')) {
      throw StateError(
        'Bundled document browser assets are missing. Build the document runtime before packaging the app.',
      );
    }
    if (_closed) throw StateError('The document asset server has closed.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('The document asset server has closed.');
    }
    _server = server;
    _subscription = server.listen(
      (request) => unawaited(_serve(request, assets, server.port)),
    );
    return Uri.parse(
      'http://127.0.0.1:${server.port}/$session/index.html#$session',
    );
  }

  Future<void> _serve(HttpRequest request, Set<String> assets, int port) async {
    final response = request.response;
    try {
      final uri = request.uri;
      final origin = 'http://127.0.0.1:$port';
      final requestOrigin = request.headers.value('origin');
      final segments = uri.pathSegments;
      final relative = segments.length >= 2 ? segments.skip(1).join('/') : '';
      final key = '$_prefix$relative';
      final contentType = _contentType(relative);
      if (_closed ||
          !const {'GET', 'HEAD'}.contains(request.method) ||
          request.headers.value(HttpHeaders.hostHeader) != '127.0.0.1:$port' ||
          (requestOrigin != null && requestOrigin != origin) ||
          request.headers.value('sec-fetch-site') == 'cross-site' ||
          uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasQuery ||
          uri.hasFragment ||
          segments.length < 2 ||
          segments.first != session ||
          segments.any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.contains('/') ||
                part.contains('\\') ||
                part.contains('%') ||
                part.codeUnits.any((code) => code < 32 || code == 127),
          ) ||
          !assets.contains(key) ||
          contentType == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Content-Security-Policy', _policy);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('Referrer-Policy', 'no-referrer');
      response.headers.set(
        'Permissions-Policy',
        'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
      );
      if (request.method == 'GET') {
        final bytes = await _bundle.load(key);
        if (_closed) return;
        response.add(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        /* Client disconnected. */
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Closing a preview may cancel an in-flight read. */
      }
    }
  }

  static String? _contentType(String relative) {
    if (relative.endsWith('.wasm')) return 'application/wasm';
    if (relative.endsWith('.json')) return 'application/json; charset=utf-8';
    if (relative.endsWith('.txt') || relative.endsWith('.md')) {
      return 'text/plain; charset=utf-8';
    }
    if (relative.endsWith('.js') || relative.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (relative.endsWith('.css')) return 'text/css; charset=utf-8';
    if (relative.endsWith('.html')) return 'text/html; charset=utf-8';
    return null;
  }

  Future<void> close() async {
    _closed = true;
    final server = _server;
    final subscription = _subscription;
    _server = null;
    _subscription = null;
    await server?.close(force: true);
    await subscription?.cancel();
  }
}
