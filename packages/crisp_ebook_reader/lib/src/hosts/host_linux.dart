import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'asset_server.dart';
import 'host.dart' show EbookHostSender;
import 'linux_host_probe.dart';

/// A native WebKitGTK view composited as a Flutter texture. The native widget is
/// offscreen; Flutter continues to own dialogs, layout, focus and hit testing.
Widget buildLinuxEbookHost({
  required String session,
  required void Function(EbookHostSender sender) onConnected,
  required void Function(EbookJson message) onMessage,
  required void Function(String message) onError,
}) =>
    _LinuxHost(
      session: session,
      onConnected: onConnected,
      onMessage: onMessage,
      onError: onError,
    );

class _LinuxHost extends StatefulWidget {
  const _LinuxHost({
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
  State<_LinuxHost> createState() => _LinuxHostState();
}

class _LinuxHostState extends State<_LinuxHost> {
  static final _receivers = <int, void Function(Map<dynamic, dynamic>)>{};
  static bool _eventsInstalled = false;

  late final EbookAssetServer _server = EbookAssetServer(widget.session);
  final _focus = FocusNode(debugLabel: 'ebook-linux-content');
  final _pointerButtons = <int, int>{};
  int? _id;
  int? _texture;
  String? _error;
  Size _size = const Size(1, 1);
  double _scale = 1;
  bool _resizeScheduled = false;
  MouseCursor _cursor = SystemMouseCursors.basic;

  @override
  void initState() {
    super.initState();
    if (!_eventsInstalled) {
      _eventsInstalled = true;
      ebookLinuxHostChannel.setMethodCallHandler((call) async {
        if (call.method == 'event' && call.arguments is Map) {
          final event = call.arguments as Map;
          final id = event['id'];
          if (id is int) _receivers[id]?.call(event);
        }
      });
    }
    unawaited(_start());
  }

  Future<void> _start() async {
    int? createdId;
    try {
      final status = await probeEbookLinuxHost();
      if (!mounted) return;
      if (!status.available) {
        throw StateError(status.reason ?? 'The Linux browser is unavailable.');
      }
      final url = await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      final result = await ebookLinuxHostChannel
          .invokeMapMethod<String, dynamic>('create');
      createdId = result?['id'] as int?;
      final texture = result?['textureId'] as int?;
      if (createdId == null || texture == null) {
        throw StateError(
            'The Linux browser did not create a rendering surface.');
      }
      if (!mounted) {
        await _release(createdId);
        return;
      }
      _id = createdId;
      _texture = texture;
      _receivers[createdId] = _event;
      widget.onConnected((message) async {
        if (!mounted || _id != createdId) {
          throw StateError('The Linux ebook browser has closed.');
        }
        await ebookLinuxHostChannel.invokeMethod<void>('send', {
          'id': createdId,
          'message': jsonEncode(message),
        });
      });
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _resize();
      if (!mounted || _id != createdId) return;
      await ebookLinuxHostChannel.invokeMethod<void>('start', {
        'id': createdId,
        'url': url.toString(),
        'session': widget.session,
      });
    } catch (error) {
      if (createdId != null && _id == null) await _release(createdId);
      _fail('The Linux ebook browser could not start: $error');
    }
  }

  static Future<void> _release(int id) async {
    _receivers.remove(id);
    try {
      await ebookLinuxHostChannel.invokeMethod<void>(
          'dispose', {'id': id}).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Engine teardown can precede widget disposal. The native plugin also
      // closes every remaining view when its registrar is destroyed.
    }
  }

  void _event(Map<dynamic, dynamic> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'message':
        try {
          final value = jsonDecode(event['data'] as String);
          if (value is Map &&
              value['channel'] == 'crisp-ebook-v1' &&
              value['session'] == widget.session) {
            widget.onMessage(Map<String, dynamic>.from(value));
          }
        } catch (_) {
          // A malformed page message does not change the native trust boundary.
        }
      case 'error':
        _fail('${event['data']}');
      case 'cursor':
        final cursor = event['data'] == 'pointer'
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic;
        if (_cursor != cursor) setState(() => _cursor = cursor);
    }
  }

  void _fail(String message) {
    if (!mounted || _error != null) return;
    final id = _id;
    _id = null;
    if (id != null) unawaited(_release(id));
    unawaited(_server.close());
    setState(() => _error = message);
    widget.onError(message);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    final id = _id;
    if (!mounted || id == null || _error != null) return;
    try {
      await ebookLinuxHostChannel.invokeMethod<void>(method, {
        'id': id,
        ...?arguments,
      });
    } catch (error) {
      if (mounted && _id == id) _fail('Linux ebook browser: $error');
    }
  }

  Future<void> _resize() => _invoke('resize', {
        'width': _size.width,
        'height': _size.height,
        'scale': _scale,
      });

  void _scheduleResize(Size size, double scale) {
    if (_size == size && _scale == scale) return;
    _size = size;
    _scale = scale;
    if (_resizeScheduled) return;
    _resizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeScheduled = false;
      if (mounted) unawaited(_resize());
    });
  }

  int get _modifiers {
    final keyboard = HardwareKeyboard.instance;
    return (keyboard.isShiftPressed ? 1 : 0) |
        (keyboard.isControlPressed ? 2 : 0) |
        (keyboard.isAltPressed ? 4 : 0) |
        (keyboard.isMetaPressed ? 8 : 0);
  }

  void _pointer(String type, PointerEvent event) {
    if (type == 'down') {
      _focus.requestFocus();
      _pointerButtons[event.pointer] = event.buttons;
    }
    final buttons = type == 'up' || type == 'cancel'
        ? _pointerButtons.remove(event.pointer) ?? event.buttons
        : event.buttons;
    unawaited(_invoke('pointer', {
      'type': type,
      'x': event.localPosition.dx,
      'y': event.localPosition.dy,
      'buttons': buttons,
      'pointer': event.pointer,
      'touch': event.kind == PointerDeviceKind.touch,
      'modifiers': _modifiers,
      'time': event.timeStamp.inMilliseconds,
    }));
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final names = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowLeft: 'Left',
      LogicalKeyboardKey.arrowRight: 'Right',
      LogicalKeyboardKey.arrowUp: 'Up',
      LogicalKeyboardKey.arrowDown: 'Down',
      LogicalKeyboardKey.pageUp: 'Page_Up',
      LogicalKeyboardKey.pageDown: 'Page_Down',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.enter: 'Return',
      LogicalKeyboardKey.space: 'space',
    };
    final modifier = _modifiers;
    final control = (modifier & (2 | 8)) != 0;
    final copyOrSelectAll = event.logicalKey == LogicalKeyboardKey.keyC ||
        event.logicalKey == LogicalKeyboardKey.keyA;
    // Flutter retains app shortcuts, Escape and Tab traversal. This is a
    // read-only browser surface: search and note text fields live in Flutter.
    if (control && !copyOrSelectAll) return KeyEventResult.ignored;
    final name = names[event.logicalKey] ??
        (control && copyOrSelectAll
            ? event.logicalKey.keyLabel.toLowerCase()
            : null);
    if (name == null) return KeyEventResult.ignored;
    unawaited(_invoke('key', {
      'name': name,
      'pressed': event is! KeyUpEvent,
      'modifiers': modifier,
    }));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    final id = _id;
    _id = null;
    if (id != null) unawaited(_release(id));
    unawaited(_server.close());
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final texture = _texture;
    if (texture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size.isFinite && !size.isEmpty) {
        _scheduleResize(size, View.of(context).devicePixelRatio);
      }
      return Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        onFocusChange: (focused) =>
            unawaited(_invoke('focus', {'focused': focused})),
        child: MouseRegion(
          cursor: _cursor,
          onHover: (event) => _pointer('move', event),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _pointer('down', event),
            onPointerMove: (event) => _pointer('move', event),
            onPointerUp: (event) => _pointer('up', event),
            onPointerCancel: (event) => _pointer('cancel', event),
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(event,
                    (_) {
                  unawaited(_invoke('scroll', {
                    'x': event.localPosition.dx,
                    'y': event.localPosition.dy,
                    'dx': event.scrollDelta.dx,
                    'dy': event.scrollDelta.dy,
                    'modifiers': _modifiers,
                  }));
                });
              }
            },
            onPointerPanZoomUpdate: (event) => unawaited(_invoke('scroll', {
              'x': event.localPosition.dx,
              'y': event.localPosition.dy,
              'dx': -event.panDelta.dx,
              'dy': -event.panDelta.dy,
              'modifiers': _modifiers,
            })),
            child: Texture(textureId: texture),
          ),
        ),
      );
    });
  }
}
