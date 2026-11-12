import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models.dart';
import 'host.dart' show EbookHostSender;

Widget buildEbookHost({
  required String session,
  required void Function(EbookHostSender sender) onConnected,
  required void Function(EbookJson message) onMessage,
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
  final void Function(EbookHostSender) onConnected;
  final void Function(EbookJson) onMessage;
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
        .resolve('assets/packages/crisp_ebook_reader/assets/index.html');
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
        final value = event.data.dartify();
        final decoded = value is String ? jsonDecode(value) : value;
        if (decoded is Map) {
          widget.onMessage(Map<String, dynamic>.from(decoded));
        }
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
    frame.title = 'Ebook content';
    frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    frame.setAttribute('referrerpolicy', 'no-referrer');
    frame.style.setProperty('border', '0');
    frame.style.setProperty('width', '100%');
    frame.style.setProperty('height', '100%');
    widget.onConnected((message) async {
      if (mounted) {
        frame.contentWindow?.postMessage(jsonEncode(message).toJS, _origin.toJS);
      }
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
