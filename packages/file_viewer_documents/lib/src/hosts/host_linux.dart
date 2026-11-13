// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'asset_server.dart';
import 'host.dart' show DocumentHostSender;
import 'linux_host_probe.dart';
import 'host_policy.dart';

/// A native WebKitGTK view composited as a Flutter texture. The native widget is
/// offscreen; Flutter continues to own dialogs, layout, focus and hit testing.
Widget buildLinuxDocumentHost({
  required String session,
  required void Function(DocumentHostSender sender) onConnected,
  required void Function(DocumentJson message) onMessage,
  required void Function(String message) onError,
}) => _LinuxHost(
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
  final void Function(DocumentHostSender) onConnected;
  final void Function(DocumentJson) onMessage;
  final void Function(String) onError;

  @override
  State<_LinuxHost> createState() => _LinuxHostState();
}

class _LinuxHostState extends State<_LinuxHost> {
  static final _receivers = <int, void Function(Map<dynamic, dynamic>)>{};
  static bool _eventsInstalled = false;

  late final DocumentAssetServer _server = DocumentAssetServer(widget.session);
  final _focus = FocusNode(debugLabel: 'document-linux-content');
  final _pointerButtons = <int, int>{};
  final _pressedCharacters = <PhysicalKeyboardKey, int>{};
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
      documentLinuxHostChannel.setMethodCallHandler((call) async {
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
      final status = await probeDocumentLinuxHost();
      if (!mounted) return;
      if (!status.available) {
        throw StateError(status.reason ?? 'The Linux browser is unavailable.');
      }
      final url = await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      final result = await documentLinuxHostChannel
          .invokeMapMethod<String, dynamic>('create')
          .timeout(const Duration(seconds: 10));
      createdId = result?['id'] as int?;
      final texture = result?['textureId'] as int?;
      if (createdId == null ||
          createdId <= 0 ||
          texture == null ||
          texture < 0) {
        throw StateError(
          'The Linux browser did not create a rendering surface.',
        );
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
          throw StateError('The Linux document browser has closed.');
        }
        await documentLinuxHostChannel
            .invokeMethod<void>('send', {
              'id': createdId,
              'message': encodeDocumentHostMessage(message, widget.session),
            })
            .timeout(const Duration(seconds: 10));
      });
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _resize();
      if (!mounted || _id != createdId) return;
      await documentLinuxHostChannel
          .invokeMethod<void>('start', {
            'id': createdId,
            'url': url.toString(),
            'session': widget.session,
          })
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      if (createdId != null && _id == null) await _release(createdId);
      _fail('The Linux document browser could not start: $error');
    }
  }

  static Future<void> _release(int id) async {
    _receivers.remove(id);
    try {
      await documentLinuxHostChannel
          .invokeMethod<void>('dispose', {'id': id})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Engine teardown can precede widget disposal. The native plugin also
      // closes every remaining view when its registrar is destroyed.
    }
  }

  void _event(Map<dynamic, dynamic> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'message':
        final value = decodeDocumentHostMessage(event['data'], widget.session);
        if (value != null) widget.onMessage(value);
      case 'error':
        _fail(
          event['data'] is String
              ? event['data'] as String
              : 'The Linux document browser failed.',
        );
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
    final bounded = documentHostError(message);
    setState(() => _error = bounded);
    widget.onError(bounded);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    final id = _id;
    if (!mounted || id == null || _error != null) return;
    try {
      await documentLinuxHostChannel
          .invokeMethod<void>(method, {'id': id, ...?arguments})
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      if (mounted && _id == id) _fail('Linux document browser: $error');
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
    unawaited(
      _invoke('pointer', {
        'type': type,
        'x': event.localPosition.dx,
        'y': event.localPosition.dy,
        'buttons': buttons,
        'pointer': event.pointer,
        'touch': event.kind == PointerDeviceKind.touch,
        'modifiers': _modifiers,
        'time': event.timeStamp.inMilliseconds,
      }),
    );
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
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.backspace: 'BackSpace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.insert: 'Insert',
    };
    final modifier = _modifiers;
    final control = (modifier & (2 | 8)) != 0;
    final editingShortcut = {
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.keyY,
    }.contains(event.logicalKey);
    // Tab follows links and controls inside the document. Ctrl+Tab leaves the
    // browser surface, including documents without a usable focus boundary;
    // Ctrl+Shift+Tab goes back to the previous Flutter control. Repeats do not
    // cycle through controls after the initial keydown has moved focus.
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        (modifier & 2) != 0 &&
        (modifier & (4 | 8)) == 0) {
      if (event is KeyDownEvent) {
        (modifier & 1) != 0 ? node.previousFocus() : node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    // Flutter retains other app shortcuts and Escape. Search fields inside
    // the trusted document renderer receive ordinary keyboard text and editing.
    if ((modifier & 4) != 0) return KeyEventResult.ignored;
    if (control && !editingShortcut) return KeyEventResult.ignored;
    final name =
        event.logicalKey == LogicalKeyboardKey.tab && (modifier & 1) != 0
        ? 'ISO_Left_Tab'
        : names[event.logicalKey] ??
              (control && editingShortcut
                  ? event.logicalKey.keyLabel.toLowerCase()
                  : null);
    int? character;
    if (!control && name == null) {
      if (event is KeyUpEvent) {
        character = _pressedCharacters.remove(event.physicalKey);
      } else {
        final text = event.character;
        final runes = text?.runes.toList();
        if (runes != null &&
            runes.length == 1 &&
            runes.single >= 32 &&
            runes.single != 127) {
          character = runes.single;
          _pressedCharacters[event.physicalKey] = character;
        }
      }
    }
    if (name == null && character == null) return KeyEventResult.ignored;
    unawaited(
      _invoke('key', {
        'name': name ?? '',
        if (character != null) 'character': character,
        'pressed': event is! KeyUpEvent,
        'modifiers': modifier,
      }),
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isFinite && !size.isEmpty) {
          _scheduleResize(size, View.of(context).devicePixelRatio);
        }
        return Semantics(
          label: 'Document content',
          hint:
              'Tab follows document links. Control Tab returns to app controls. '
              'Control Shift Tab returns to the previous control.',
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _key,
            onFocusChange: (focused) {
              if (!focused) _pressedCharacters.clear();
              unawaited(_invoke('focus', {'focused': focused}));
            },
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
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) {
                        unawaited(
                          _invoke('scroll', {
                            'x': event.localPosition.dx,
                            'y': event.localPosition.dy,
                            'dx': event.scrollDelta.dx,
                            'dy': event.scrollDelta.dy,
                            'modifiers': _modifiers,
                          }),
                        );
                      },
                    );
                  }
                },
                onPointerPanZoomUpdate: (event) => unawaited(
                  _invoke('scroll', {
                    'x': event.localPosition.dx,
                    'y': event.localPosition.dy,
                    'dx': -event.panDelta.dx,
                    'dy': -event.panDelta.dy,
                    'modifiers': _modifiers,
                  }),
                ),
                child: Texture(textureId: texture),
              ),
            ),
          ),
        );
      },
    );
  }
}
