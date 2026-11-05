import 'package:flutter/widgets.dart';

/// Helper class for defining a paint mode's UI representation.
///
/// Contains the [icon] and [label] used in the editor's toolbars.
class PaintModeHelper {
  /// Creates a [PaintModeHelper] with the given [icon] and [label].
  const PaintModeHelper({required this.icon, required this.label});

  /// The icon that represents the paint mode.
  final IconData icon;

  /// The label text shown for the paint mode.
  final String label;
}
