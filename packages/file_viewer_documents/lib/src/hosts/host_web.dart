// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models.dart';
import 'host.dart' show DocumentHostSender;
import 'host_policy.dart';

Widget buildDocumentHost({
  required String session,
  required void Function(DocumentHostSender sender) onConnected,
  required void Function(DocumentJson message) onMessage,
  required void Function(String message) onError,
}) => _WebHost(
  session: session,
  onConnected: onConnected,
  onMessage: onMessage,
  onError: onError,
);

class _WebHost extends StatefulWidget {
  const _WebHost({
    required this.session,
    required this.onConnected,
    required this.onMessage,
    required this.onError,
  });
  final String session;
  final void Function(DocumentHostSender) onConnected;
  final void Function(DocumentJson) onMessage;
  final void Function(String) onError;
  @override
  State<_WebHost> createState() => _WebHostState();
}

class _WebHostState extends State<_WebHost> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;
  late final Uri _uri;
  late final String _origin;
  @override
  void initState() {
    super.initState();
    _uri = Uri.parse(web.document.baseURI)
        .resolve('assets/packages/file_viewer_documents/assets/index.html');
    _origin = _uri.origin;
    _listener = ((web.MessageEvent event) {
      final frame = _frame;
      if (!mounted ||
          frame == null ||
          event.source != frame.contentWindow ||
          event.origin != _origin) {
        return;
      }
      try {
        final value = event.data;
        if (value == null || !value.isA<JSString>()) return;
        final decoded = decodeDocumentHostMessage(
          (value as JSString).toDart,
          widget.session,
        );
        if (decoded != null) widget.onMessage(decoded);
      } catch (_) {
        /* Ignore unrelated or malformed window messages. */
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  void _createElement(Object element) {
    final frame = element as web.HTMLIFrameElement;
    if (!mounted) {
      frame.remove();
      return;
    }
    _frame = frame;
    frame.title = 'Document content';
    frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    frame.setAttribute('referrerpolicy', 'no-referrer');
    frame.style.setProperty('border', '0');
    frame.style.setProperty('width', '100%');
    frame.style.setProperty('height', '100%');
    widget.onConnected((message) async {
      if (!mounted || _frame != frame) {
        throw StateError('The document browser has closed.');
      }
      final encoded = encodeDocumentHostMessage(message, widget.session);
      frame.contentWindow?.postMessage(encoded.toJS, _origin.toJS);
    });
    frame.src = _uri.replace(fragment: widget.session).toString();
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame?.src = 'about:blank';
    _frame?.remove();
    _frame = null;
    super.dispose();
  }

  @override
  // Flutter's shared tag factory is disposed with the view. Registering a
  // session-specific global factory here would retain closed reader states
  // and their book buffers for the rest of the browser application's lifetime.
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: _createElement,
  );
}
