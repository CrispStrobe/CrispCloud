import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'hosts/font_assets.dart';
import 'hosts/host.dart';
import 'models.dart';

/// A local rendering surface. The host receives only these supplied bytes;
/// provider clients, paths, credentials and arbitrary URLs never enter it.
class DocumentPreview extends StatefulWidget {
  const DocumentPreview({
    super.key,
    required this.bytes,
    required this.filename,
    required this.kind,
    this.locale = 'en',
    this.dark = false,
    this.fontScale = 1,
    this.fonts = const [],
    this.onReady,
    this.onError,
    this.onShowSource,
  });

  final Uint8List bytes;
  final String filename;
  final DocumentPreviewKind kind;
  final String locale;
  final bool dark;
  final double fontScale;
  final List<DocumentPreviewFont> fonts;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;
  final VoidCallback? onShowSource;

  @override
  State<DocumentPreview> createState() => _DocumentPreviewState();
}

class _DocumentPreviewState extends State<DocumentPreview> {
  late String _session;
  DocumentHostSender? _send;
  Timer? _deadline;
  bool _opening = false;
  bool _ready = false;
  bool _closed = false;
  String? _error;
  double _progress = 0;
  List<DocumentPreviewFont> _fonts = const [];

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  void _startSession() {
    _deadline?.cancel();
    _send = null;
    _opening = false;
    _ready = false;
    _error = null;
    _progress = 0;
    final random = Random.secure();
    _session = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    if (widget.bytes.length > documentPreviewByteLimit(widget.kind)) {
      _error = 'This file exceeds the document preview limit.';
    } else {
      try {
        _fonts = documentPreviewUsesSharedFonts(widget.kind)
            ? snapshotDocumentPreviewFonts(widget.fonts)
            : const [];
      } on ArgumentError {
        _error = 'The document font configuration is invalid.';
        return;
      }
      _deadline = Timer(const Duration(seconds: 30), () {
        _fail('The document browser did not finish starting.');
      });
    }
  }

  @override
  void didUpdateWidget(covariant DocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.filename != widget.filename ||
        oldWidget.kind != widget.kind ||
        !listEquals(oldWidget.fonts, widget.fonts)) {
      _startSession();
    } else if (_send != null &&
        (oldWidget.locale != widget.locale ||
            oldWidget.dark != widget.dark ||
            oldWidget.fontScale != widget.fontScale)) {
      unawaited(
        _send!(
          _message('appearance', {
            'locale': widget.locale,
            'dark': widget.dark,
            'fontScale': widget.fontScale.clamp(0.5, 3),
          }),
        ).catchError((Object error) {
          if (_active) _fail('The document view could not update: $error');
        }),
      );
    }
  }

  bool get _active => mounted && !_closed && _error == null;

  DocumentJson _message(String type, [DocumentJson? value]) => {
    'channel': documentPreviewChannel,
    'session': _session,
    'type': type,
    ...?value,
  };

  void _receive(DocumentJson message) {
    if (!_active ||
        message['channel'] != documentPreviewChannel ||
        message['session'] != _session) {
      return;
    }
    switch (message['type']) {
      case 'ready':
        if (_send != null && !_opening) unawaited(_open());
      case 'loaded':
        if (!_opening || _ready) return;
        _deadline?.cancel();
        setState(() => _ready = true);
        widget.onReady?.call();
      case 'error':
        final value = message['message'];
        _fail(
          value is String
              ? value.substring(0, min(value.length, 2048))
              : 'The document could not be rendered.',
        );
    }
  }

  Future<void> _open() async {
    if (!_active || _opening || _send == null) return;
    final session = _session;
    final bytes = widget.bytes;
    final send = _send!;
    bool current() => _active && session == _session;
    DocumentJson message(String type, [DocumentJson? value]) => {
      'channel': documentPreviewChannel,
      'session': session,
      'type': type,
      ...?value,
    };
    _opening = true;
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 90), () {
      _fail('The document exceeded its rendering time limit.');
    });
    try {
      await send(
        message('begin', {
          'filename': widget.filename,
          'kind': widget.kind.name,
          'length': bytes.length,
          'locale': widget.locale,
          'dark': widget.dark,
          'fontScale': widget.fontScale.clamp(0.5, 3),
        }),
      );
      for (var offset = 0; offset < bytes.length;) {
        if (!current()) return;
        final end = min(offset + documentPreviewChunkBytes, bytes.length);
        await send(
          message('chunk', {
            'offset': offset,
            'data': base64Encode(Uint8List.sublistView(bytes, offset, end)),
          }),
        );
        offset = end;
        if (current()) setState(() => _progress = offset / bytes.length);
        await Future<void>.delayed(Duration.zero);
      }
      if (current()) await send(message('open'));
    } catch (error) {
      if (current()) {
        _fail('The document browser could not receive the file: $error');
      }
    }
  }

  void _fail(String message) {
    if (!_active) return;
    _deadline?.cancel();
    setState(() => _error = message);
    widget.onError?.call(message);
  }

  @override
  void dispose() {
    _closed = true;
    _deadline?.cancel();
    _send = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_error case final error?) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined),
              const SizedBox(height: 12),
              SelectableText(error, textAlign: TextAlign.center),
              if (widget.onShowSource != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onShowSource,
                  child: const Text('Source'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: ValueKey(_session),
            child: createDocumentHost(
              session: _session,
              fonts: _fonts,
              onConnected: (sender) {
                if (_active && session == _session) _send = sender;
              },
              onMessage: _receive,
              onError: (message) {
                if (session == _session) _fail(message);
              },
            ),
          ),
        ),
        if (!_ready)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              value: _opening && _progress < 1 ? _progress : null,
            ),
          ),
      ],
    );
  }
}
