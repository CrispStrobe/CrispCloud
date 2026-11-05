import 'package:flutter/widgets.dart';

/// Configuration interface for zoom behavior in an editor or viewer.
///
/// Provides control over zoom enablement, scale limits, double-tap behavior,
/// and boundary constraints.
abstract class ZoomConfigs {
  /// Creates a set of zoom configuration options.
  const ZoomConfigs({
    this.enableZoom = false,
    this.editorMinScale = 1,
    this.editorMaxScale = 5,
    this.boundaryMargin = EdgeInsets.zero,
    this.enableDoubleTapZoom = true,
    this.doubleTapZoomFactor = 2,
    this.doubleTapZoomDuration = const Duration(milliseconds: 180),
    this.doubleTapZoomCurve = Curves.easeInOut,
    this.invertTrackpadDirection = false,
  });

  /// {@template enableZoom}
  /// Indicates whether the editor supports zoom functionality.
  ///
  /// When set to `true`, the editor allows users to zoom in and out, providing
  /// enhanced accessibility and usability, especially on smaller screens or for
  /// users with visual impairments. If set to `false`, the zoom functionality
  /// is disabled, and the editor's content remains at a fixed scale.
  ///
  /// Default value is `false`.
  /// {@endtemplate}
  final bool enableZoom;

  /// The minimum scale factor for the editor.
  ///
  /// This value determines the lowest level of zoom that can be applied to the
  /// editor content. It only has an effect when [enableZoom] is set to
  /// `true`.
  /// If [enableZoom] is `false`, this value is ignored.
  ///
  /// Default value is 1.0.
  final double editorMinScale;

  /// The maximum scale factor for the editor.
  ///
  /// This value determines the highest level of zoom that can be applied to the
  /// editor content. It only has an effect when [enableZoom] is set to
  /// `true`.
  /// If [enableZoom] is `false`, this value is ignored.
  ///
  /// Default value is 5.0.
  final double editorMaxScale;

  /// Zoom boundary
  ///
  /// A margin for the visible boundaries of the child.
  ///
  /// Any transformation that results in the viewport being able to view
  /// outside of the boundaries will be stopped at the boundary.
  /// The boundaries do not rotate with the rest of the scene, so they are
  /// always aligned with the viewport.
  ///
  /// To produce no boundaries at all, pass infinite [EdgeInsets], such as
  /// EdgeInsets.all(double.infinity).
  ///
  /// No edge can be NaN.
  ///
  /// Defaults to [EdgeInsets.zero], which results in boundaries that are the
  /// exact same size and position as the [child].
  final EdgeInsets boundaryMargin;

  /// Whether double-tap to zoom is enabled.
  ///
  /// If `true`, users can double-tap to zoom in or out based on the current
  /// zoom level. If `false`, double-tap gestures are ignored.
  final bool enableDoubleTapZoom;

  /// The zoom scale factor applied on double-tap.
  ///
  /// This determines how much to zoom in or out when the user double-taps.
  /// For example, a value of 2.0 doubles the current scale.
  final double doubleTapZoomFactor;

  /// The duration of the zoom animation on double-tap.
  ///
  /// Controls how long the zoom animation takes to complete when a
  /// double-tap gesture is detected.
  final Duration doubleTapZoomDuration;

  /// The animation curve used for double-tap zooming.
  ///
  /// Defines the easing curve of the zoom animation triggered by
  /// double-tapping.
  final Curve doubleTapZoomCurve;

  /// Determines if the trackpad scroll direction should be inverted for
  /// panning gestures.
  ///
  /// When set to `true`, trackpad panning will use natural scrolling
  /// (pan left moves content left, pan up moves content up).
  /// When set to `false`, trackpad panning will use traditional scrolling
  /// (pan left moves content right, pan up moves content down).
  ///
  /// This setting only affects trackpad panning on desktop platforms and
  /// has no effect on touch gestures, mouse wheel, or other input methods.
  ///
  /// Defaults to `false` (traditional scrolling behavior).
  final bool invertTrackpadDirection;
}
