import 'package:flutter/gestures.dart';

/// Two-finger zoom for the report surfaces: a trackpad pinch
/// ([PointerPanZoomUpdateEvent.scale]) or two fingers on a touch screen.
///
/// A surface feeds every pointer event to [handle] first and skips its own
/// handling when [handle] returns true.
class ReportPinchZoom {
  /// ReportPinchZoom API.
  ReportPinchZoom({
    required this.zoom,
    required this.onZoom,
    required this.onPinchStart,
  });

  /// Current zoom of the surface.
  final double Function() zoom;

  /// Applies [zoom] around [focal] (local coordinates) and pans the content
  /// by [pan].
  final void Function(double zoom, Offset focal, Offset pan) onZoom;

  /// A second finger landed: end the one-finger gesture it interrupts.
  final void Function() onPinchStart;

  final Map<int, Offset> _touches = <int, Offset>{};
  double _startZoom = 1;
  double _startDistance = 0;
  Offset _focal = Offset.zero;

  /// Whether two fingers are on a touch screen.
  bool get pinching => _touches.length >= 2;

  /// Handles [event]; true when it belongs to a pinch.
  bool handle(PointerEvent event) {
    if (event is PointerPanZoomStartEvent) {
      _startZoom = zoom();
      return true;
    }
    if (event is PointerPanZoomUpdateEvent) {
      onZoom(
        _startZoom * event.scale,
        event.localPosition,
        event.localPanDelta,
      );
      return true;
    }
    if (event is PointerPanZoomEndEvent) {
      return true;
    }
    if (event.kind != PointerDeviceKind.touch) {
      return false;
    }
    if (event is PointerDownEvent) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length == 2) {
        onPinchStart();
        _start();
      }
      return _touches.length >= 2;
    }
    if (event is PointerMoveEvent) {
      if (!_touches.containsKey(event.pointer)) {
        return false;
      }
      _touches[event.pointer] = event.localPosition;
      if (!pinching) {
        return false;
      }
      final (Offset a, Offset b) = _pair;
      final Offset focal = (a + b) / 2;
      if (_startDistance > 1) {
        onZoom(
          _startZoom * (a - b).distance / _startDistance,
          focal,
          focal - _focal,
        );
      }
      _focal = focal;
      return true;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      final bool was = pinching;
      _touches.remove(event.pointer);
      if (pinching) {
        _start();
      }
      return was;
    }
    return false;
  }

  (Offset, Offset) get _pair {
    final Iterator<Offset> it = _touches.values.iterator..moveNext();
    final Offset a = it.current;
    it.moveNext();
    return (a, it.current);
  }

  void _start() {
    final (Offset a, Offset b) = _pair;
    _startDistance = (a - b).distance;
    _startZoom = zoom();
    _focal = (a + b) / 2;
  }
}
