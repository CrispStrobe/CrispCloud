import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Allows custom widgets for FloatSelect UI
class FloatSelectWidgets {
  /// Creates a set of optional custom widgets
  const FloatSelectWidgets({
    this.overlayToolbar,
    this.toolbar,
    this.toolbarChildren,
  });

  /// Widget shown as a floating toolbar overlay
  final Widget? overlayToolbar;

  /// Widget used as the default toolbar
  final Widget? toolbar;

  /// Children of the toolbar if no widget is provided
  final List<Widget>? toolbarChildren;

  /// Returns a copy with overridden widget values
  FloatSelectWidgets copyWith({
    Widget? overlayToolbar,
    Widget? toolbar,
    List<Widget>? toolbarChildren,
  }) {
    return FloatSelectWidgets(
      overlayToolbar: overlayToolbar ?? this.overlayToolbar,
      toolbar: toolbar ?? this.toolbar,
      toolbarChildren: toolbarChildren ?? this.toolbarChildren,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FloatSelectWidgets &&
        other.overlayToolbar == overlayToolbar &&
        other.toolbar == toolbar &&
        listEquals(other.toolbarChildren, toolbarChildren);
  }

  @override
  int get hashCode =>
      overlayToolbar.hashCode ^ toolbar.hashCode ^ toolbarChildren.hashCode;
}
