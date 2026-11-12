import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models.dart';
import 'asset_server.dart';
import 'host.dart' show EbookHostSender;
import 'host_linux.dart';

Widget buildEbookHost({
  required String session,
  required void Function(EbookHostSender sender) onConnected,
  required void Function(EbookJson message) onMessage,
  required void Function(String message) onError,
}) =>
    Platform.isLinux
        ? buildLinuxEbookHost(
            session: session,
            onConnected: onConnected,
            onMessage: onMessage,
            onError: onError,
          )
        : _NativeHost(
            session: session,
            onConnected: onConnected,
            onMessage: onMessage,
            onError: onError,
          );

class _NativeHost extends StatefulWidget {
  const _NativeHost({
    required this.session,
    required this.onConnected,
    required this.onMessage,
    required this.onError,
  });
  final String session;
  final void Function(EbookHostSender) onConnected;
  final void Function(EbookJson) onMessage;
  final void Function(String) onError;
  @override
  State<_NativeHost> createState() => _NativeHostState();
}

class _NativeHostState extends State<_NativeHost> {
  late final EbookAssetServer _server;
  Uri? _url;
  String? _error;
  @override
  void initState() {
    super.initState();
    _server = EbookAssetServer(widget.session);
    unawaited(_start());
  }

  bool _isHostUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        _url != null &&
        uri.scheme == _url!.scheme &&
        uri.host == _url!.host &&
        uri.port == _url!.port &&
        uri.path == _url!.path;
  }

  void _receive(dynamic value) {
    if (!mounted) return;
    try {
      final parsed = value is String ? jsonDecode(value) : value;
      if (parsed is Map) widget.onMessage(Map<String, dynamic>.from(parsed));
    } catch (_) {
      /* Drop malformed/unrelated JavaScript messages. */
    }
  }

  Future<void> _start() async {
    try {
      final url = await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      if (InAppWebViewPlatform.instance == null) {
        throw StateError('The ebook browser platform plugin is unavailable.');
      }
      _url = url;
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      _error = 'The ebook browser could not start: $error';
      widget.onError(_error!);
      setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_server.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    if (_url == null) return const Center(child: CircularProgressIndicator());
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        !Platform.isMacOS &&
        !Platform.isWindows) {
      return const Center(
        child: Text('The ebook browser host is unavailable on this platform.'),
      );
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_url!.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        allowFileAccess: false,
        allowContentAccess: false,
        transparentBackground: true,
        mediaPlaybackRequiresUserGesture: true,
        disableContextMenu: false,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'CrispEbookMessage',
          callback: (args) {
            if (args.isNotEmpty) _receive(args.first);
            return null;
          },
        );
        widget.onConnected((message) async {
          await controller.evaluateJavascript(
            source:
                'void window.crispEbookHost?.receive(${jsonEncode(message)})',
          );
        });
      },
      onLoadStop: (controller, url) async {
        if (url != null && _isHostUrl(url.toString())) {
          await controller.evaluateJavascript(
            source: 'void window.crispEbookHost?.ready()',
          );
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        if (action.isForMainFrame &&
            !_isHostUrl(action.request.url.toString())) {
          return NavigationActionPolicy.CANCEL;
        }
        final url = action.request.url?.toString() ?? '';
        if (!action.isForMainFrame && !url.startsWith('blob:')) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, action) async => false,
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          widget.onError('Ebook browser: ${error.description}');
        }
      },
    );
  }
}
