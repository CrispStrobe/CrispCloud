/// A class that defines callback functions for handling different types of
/// helper line hits.
class HelperLinesCallbacks {
  /// Creates an instance of [HelperLinesCallbacks] with optional callback
  /// functions.
  ///
  /// - [onLineHit]: Called when any helper line is hit.
  /// - [onHitVerticalLine]: Called specifically when a vertical line is hit.
  /// - [onHitHorizontalLine]: Called specifically when a horizontal line
  ///   is hit.
  /// - [onHitRotateLine]: Called specifically when a rotate line is hit.
  const HelperLinesCallbacks({
    this.onLineHit,
    this.onHitVerticalLine,
    this.onHitHorizontalLine,
    this.onHitRotateLine,
    this.onHitLayerAlignLine,
  });

  /// A callback that is triggered when any helper line is hit.
  final Function()? onLineHit;

  /// A callback that is triggered when a vertical line is hit.
  final Function()? onHitVerticalLine;

  /// A callback that is triggered when a horizontal line is hit.
  final Function()? onHitHorizontalLine;

  /// A callback that is triggered when a rotate line is hit.
  final Function()? onHitRotateLine;

  /// Called when the active layer aligns with another layer (within tolerance).
  final Function()? onHitLayerAlignLine;

  /// Handles the event when a vertical line is hit.
  ///
  /// Calls [onLineHit] if set, followed by [onHitVerticalLine].
  void handleVerticalLineHit() {
    onLineHit?.call();
    onHitVerticalLine?.call();
  }

  /// Handles the event when a horizontal line is hit.
  ///
  /// Calls [onLineHit] if set, followed by [onHitHorizontalLine].
  void handleHorizontalLineHit() {
    onLineHit?.call();
    onHitHorizontalLine?.call();
  }

  /// Handles the event when a rotate line is hit.
  ///
  /// Calls [onLineHit] if set, followed by [onHitRotateLine].
  void handleRotateLineHit() {
    onLineHit?.call();
    onHitRotateLine?.call();
  }

  /// Handles the event when a rotate line is hit.
  ///
  /// Calls [onLineHit] if set, followed by [onHitLayerAlignLine].
  void handleLayerAlignLineHit() {
    onLineHit?.call();
    onHitLayerAlignLine?.call();
  }

  /// Creates a copy with modified editor callbacks.
  HelperLinesCallbacks copyWith({
    Function()? onLineHit,
    Function()? onHitVerticalLine,
    Function()? onHitHorizontalLine,
    Function()? onHitRotateLine,
    Function()? onHitLayerAlignLine,
  }) {
    return HelperLinesCallbacks(
      onLineHit: onLineHit ?? this.onLineHit,
      onHitVerticalLine: onHitVerticalLine ?? this.onHitVerticalLine,
      onHitHorizontalLine: onHitHorizontalLine ?? this.onHitHorizontalLine,
      onHitRotateLine: onHitRotateLine ?? this.onHitRotateLine,
      onHitLayerAlignLine: onHitLayerAlignLine ?? this.onHitLayerAlignLine,
    );
  }
}
