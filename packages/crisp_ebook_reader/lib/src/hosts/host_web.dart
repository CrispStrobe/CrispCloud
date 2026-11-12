import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

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
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;
  late final String _viewType;
  late final String _origin;
  @override
  void initState() {
    super.initState();
    _viewType = 'crisp-ebook-${widget.session}';
    final uri = Uri.parse(web.document.baseURI)
        .resolve('assets/packages/crisp_ebook_reader/assets/index.html');
    _origin = uri.origin;
    _frame = web.HTMLIFrameElement()
      ..src = uri.replace(fragment: widget.session).toString()
      ..title = 'Ebook content';
    _frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    _frame.setAttribute('referrerpolicy', 'no-referrer');
    _frame.style.setProperty('border', '0');
    _frame.style.setProperty('width', '100%');
    _frame.style.setProperty('height', '100%');
    _listener = ((web.MessageEvent event) {
      if (!mounted ||
          event.source != _frame.contentWindow ||
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
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    widget.onConnected((message) async {
      if (mounted) {
        _frame.contentWindow?.postMessage(jsonEncode(message).toJS, _origin.toJS);
      }
    });
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame.src = 'about:blank';
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
