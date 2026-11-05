import 'package:flutter/widgets.dart';

/// A singleton class to manage gesture propagation in the app.
///
/// Use [GestureManager.instance] to access the singleton.
class GestureManager {
  GestureManager._();

  /// The single instance of [GestureManager].
  static final GestureManager instance = GestureManager._();

  bool _isBlocked = false;

  /// Returns `true` if gesture propagation is currently blocked.
  bool get isBlocked => _isBlocked;

  /// Temporarily blocks pointer events from reaching widgets below in the
  /// image editor.
  ///
  /// Resets automatically in the next frame.
  void stopPropagation() {
    _isBlocked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isBlocked = false;
    });
  }
}
