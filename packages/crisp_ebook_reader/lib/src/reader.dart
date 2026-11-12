import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'hosts/host.dart';

/// Embedded offline reader. The host app owns persistence, editor sessions,
/// cloud writes and external links. This widget never performs those actions.
class CrispEbookReader extends StatefulWidget {
  const CrispEbookReader({
    super.key,
    required this.bytes,
    required this.filename,
    required this.controller,
    this.initialLocation,
    this.onReady,
    this.onLocationChanged,
    this.onHistoryChanged,
    this.onSelection,
    this.onError,
    this.onExternalLink,
    this.appearance = const EbookAppearance(),
  });
  final Uint8List bytes;
  final String filename;
  final CrispEbookController controller;
  final String? initialLocation;
  final EbookAppearance appearance;
  final void Function(EbookBookInfo)? onReady;
  final void Function(EbookLocation)? onLocationChanged;
  final void Function(EbookNavigationHistory)? onHistoryChanged;
  final void Function(EbookSelection)? onSelection;
  final void Function(String)? onError;
  final void Function(String)? onExternalLink;
  @override
  State<CrispEbookReader> createState() => _CrispEbookReaderState();
}

class _CrispEbookReaderState extends State<CrispEbookReader> {
  String _session = _newSession();
  EbookHostSender? _send;
  int _requestId = 0;
  final _pending = <int, Completer<dynamic>>{};
  bool _opening = false;
  String? _error;
  Timer? _startupTimer;
  static String _newSession() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    widget.controller.attach(_command);
    _startupTimer = Timer(const Duration(seconds: 35), () {
      if (mounted && !widget.controller.isReady) {
        _fail(
          'The ebook browser did not finish opening. Check this platform’s WebView runtime.',
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant CrispEbookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach(sender: _command);
      widget.controller.attach(_command);
    }
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.filename != widget.filename) {
      _cancelRequests('The publication changed');
      widget.controller.detach(sender: _command);
      _startupTimer?.cancel();
      _session = _newSession();
      _opening = false;
      _send = null;
      _error = null;
      _prepare();
    } else if (widget.controller.isReady &&
        jsonEncode(oldWidget.appearance.toJson()) !=
            jsonEncode(widget.appearance.toJson())) {
      unawaited(_updateAppearance());
    }
  }

  Future<void> _updateAppearance() async {
    try {
      await _command('appearance', widget.appearance.toJson());
    } catch (error) {
      // A failed preference update must not obscure an already opened book.
      if (mounted) widget.onError?.call(error.toString());
    }
  }

  Future<dynamic> _command(String method, EbookJson args) async {
    final sender = _send;
    if (sender == null) throw StateError('Ebook browser is not ready');
    final id = ++_requestId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    try {
      // Listen to the reply immediately, including while evaluateJavascript is
      // completing. Disposal or a fast native reply must not produce an
      // unhandled asynchronous error between sending and awaiting the reply.
      unawaited(Future<void>.sync(() => sender({
            'id': id,
            'channel': 'crisp-ebook-v1',
            'session': _session,
            'method': method,
            'args': args,
          })).catchError((Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }));
      return await completer.future.timeout(
        Duration(
          seconds: method == 'exportPublication'
              ? 180
              : method == 'open'
                  ? 90
                  : 45,
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _cancelRequests(String message) {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(StateError(message));
    }
    _pending.clear();
  }

  Future<void> _open() async {
    if (_opening || _send == null) return;
    // The host has started. Parsing now uses the open command's 90-second
    // deadline; the shorter WebView-startup timer must not hide a slow book
    // permanently before that command has had its documented time to finish.
    _startupTimer?.cancel();
    final session = _session;
    _opening = true;
    final appearance = widget.appearance.toJson();
    try {
      if (widget.bytes.length > EbookReaderCapabilities.maximumInputBytes) {
        throw const FormatException(
          'Book exceeds the 128 MiB reader input limit',
        );
      }
      await _command('open', {
        'data': base64Encode(widget.bytes),
        'filename': widget.filename,
        'initialLocation': widget.initialLocation,
        'appearance': appearance,
      });
      if (mounted &&
          _session == session &&
          jsonEncode(appearance) != jsonEncode(widget.appearance.toJson())) {
        await _updateAppearance();
      }
    } catch (error) {
      if (mounted && _session == session) _fail(error.toString());
    }
  }

  void _message(EbookJson message) {
    if (!mounted ||
        message['session'] != _session ||
        message['channel'] != 'crisp-ebook-v1') {
      return;
    }
    final id = message['id'];
    if (id is num) {
      final pending = _pending[id.toInt()];
      if (pending != null && !pending.isCompleted) {
        if (message['error'] != null) {
          pending.completeError(StateError('${message['error']}'));
        } else {
          pending.complete(message['result']);
        }
      }
      return;
    }
    final data = message['data'];
    switch (message['event']) {
      case 'hostReady':
        unawaited(_open());
      case 'ready':
        final info = EbookBookInfo.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _startupTimer?.cancel();
        widget.controller.updateBookInfo(info);
        widget.onReady?.call(info);
      case 'location':
        final location = EbookLocation.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        widget.controller.updateLocation(location);
        widget.onLocationChanged?.call(location);
      case 'selection':
        final selection = EbookSelection.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        widget.controller.updateSelection(selection);
        widget.onSelection?.call(selection);
      case 'history':
        final history = EbookNavigationHistory.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        widget.controller.updateHistory(history);
        widget.onHistoryChanged?.call(history);
      case 'externalLink':
        widget.onExternalLink?.call('$data');
      case 'error':
        _fail('$data');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    _startupTimer?.cancel();
    widget.onError?.call(message);
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _cancelRequests('Ebook reader closed');
    widget.controller.detach(sender: _command);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey(_session),
              child: createEbookHost(
                session: _session,
                onConnected: (sender) => _send = sender,
                onMessage: _message,
                onError: _fail,
              ),
            ),
          ),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
        ],
      );
}
