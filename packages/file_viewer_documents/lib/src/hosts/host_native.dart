// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models.dart';
import 'asset_server.dart';
import 'font_assets.dart';
import 'host.dart' show DocumentHostSender;
import 'host_linux.dart';
import 'host_policy.dart';

Widget buildDocumentHost({
  required String session,
  List<DocumentPreviewFont> fonts = const [],
  required void Function(DocumentHostSender sender) onConnected,
  required void Function(DocumentJson message) onMessage,
  required void Function(String message) onError,
}) => Platform.isLinux
    ? buildLinuxDocumentHost(
        session: session,
        fonts: fonts,
        onConnected: onConnected,
        onMessage: onMessage,
        onError: onError,
      )
    : _NativeHost(
        session: session,
        fonts: fonts,
        onConnected: onConnected,
        onMessage: onMessage,
        onError: onError,
      );

class _NativeHost extends StatefulWidget {
  const _NativeHost({
    required this.session,
    required this.fonts,
    required this.onConnected,
    required this.onMessage,
    required this.onError,
  });
  final String session;
  final List<DocumentPreviewFont> fonts;
  final void Function(DocumentHostSender) onConnected;
  final void Function(DocumentJson) onMessage;
  final void Function(String) onError;
  @override
  State<_NativeHost> createState() => _NativeHostState();
}

class _NativeHostState extends State<_NativeHost> {
  late final DocumentAssetServer _server;
  Uri? _url;
  String? _error;
  @override
  void initState() {
    super.initState();
    _server = DocumentAssetServer(widget.session, fonts: widget.fonts);
    unawaited(_start());
  }

  bool _isHostUrl(String value) =>
      _url != null && isDocumentHostUrl(_url!, value);

  void _receive(dynamic value) {
    if (!mounted) return;
    final message = decodeDocumentHostMessage(value, widget.session);
    if (message != null) widget.onMessage(message);
  }

  Future<void> _start() async {
    try {
      final url = await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      if (InAppWebViewPlatform.instance == null) {
        throw StateError(
          'The document browser platform plugin is unavailable.',
        );
      }
      _url = url;
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      await _server.close();
      if (!mounted) return;
      _error = documentHostError(
        'The document browser could not start: $error',
      );
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
        child: Text(
          'The document browser host is unavailable on this platform.',
        ),
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
        incognito: true,
        cacheEnabled: false,
        mediaPlaybackRequiresUserGesture: true,
        disableContextMenu: false,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'CrispDocumentMessage',
          callback: (args) {
            if (args.isNotEmpty) _receive(args.first);
            return null;
          },
        );
        widget.onConnected((message) async {
          if (!mounted || _error != null) {
            throw StateError('The document browser has closed.');
          }
          final outgoing = message['type'] == 'begin'
              ? documentHostMessageWithFonts(message, _server.fontDescriptors)
              : message;
          final encoded = encodeDocumentHostMessage(outgoing, widget.session);
          await controller
              .evaluateJavascript(
                source: 'void window.crispDocumentHost?.receive($encoded)',
              )
              .timeout(const Duration(seconds: 10));
        });
      },
      onLoadStop: (controller, url) async {
        if (url != null && _isHostUrl(url.toString())) {
          await controller.evaluateJavascript(
            source: 'void window.crispDocumentHost?.ready()',
          );
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        return _url != null &&
                allowsDocumentHostNavigation(
                  _url!,
                  action.request.url?.toString(),
                  isMainFrame: action.isForMainFrame,
                )
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (controller, action) async => false,
      onPermissionRequest: (controller, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onReceivedError: (controller, request, error) {
        if (mounted && (request.isForMainFrame ?? false)) {
          widget.onError(
            documentHostError('Document browser: ${error.description}'),
          );
        }
      },
      onReceivedHttpError: (controller, request, error) {
        if (mounted && (request.isForMainFrame ?? false)) {
          widget.onError(
            'Document browser assets returned HTTP ${error.statusCode}.',
          );
        }
      },
    );
  }
}
