import 'package:flutter/widgets.dart';

import '/core/services/gesture_manager.dart';

/// A widget that intercepts pointer events to stop their propagation
/// within the image editor context.
///
/// This is useful for preventing events from reaching widgets underneath,
/// such as when using floating toolbars or overlays.
class GestureInterceptor extends StatelessWidget {
  /// Creates a [GestureInterceptor].
  const GestureInterceptor({
    super.key,
    required this.child,
    this.interceptPointerDown = true,
    this.interceptPointerUp = true,
    this.interceptPointerPanZoomStart = true,
    this.interceptPointerPanZoomUpdate = true,
    this.interceptPointerPanZoomEnd = true,
    this.behavior = HitTestBehavior.deferToChild,
  });

  /// The widget below this interceptor in the widget tree.
  final Widget child;

  /// Whether to intercept `PointerDownEvent`.
  final bool interceptPointerDown;

  /// Whether to intercept `PointerUpEvent`.
  final bool interceptPointerUp;

  /// Whether to intercept `PointerPanZoomStartEvent`.
  final bool interceptPointerPanZoomStart;

  /// Whether to intercept `PointerPanZoomUpdateEvent`.
  final bool interceptPointerPanZoomUpdate;

  /// Whether to intercept `PointerPanZoomEndEvent`.
  final bool interceptPointerPanZoomEnd;

  /// How to behave during hit testing.
  final HitTestBehavior behavior;

  /// Calls [GestureManager.stopPropagation] to prevent gesture propagation.
  void _intercept() {
    GestureManager.instance.stopPropagation();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: behavior,
      onPointerDown: interceptPointerDown ? (_) => _intercept() : null,
      onPointerUp: interceptPointerUp ? (_) => _intercept() : null,
      onPointerPanZoomStart: interceptPointerPanZoomStart
          ? (_) => _intercept()
          : null,
      onPointerPanZoomUpdate: interceptPointerPanZoomUpdate
          ? (_) => _intercept()
          : null,
      onPointerPanZoomEnd: interceptPointerPanZoomEnd
          ? (_) => _intercept()
          : null,
      child: child,
    );
  }
}
