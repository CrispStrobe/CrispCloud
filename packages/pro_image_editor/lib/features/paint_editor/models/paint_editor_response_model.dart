import '/core/models/layers/layer.dart';

/// A response model for the Paint Editor feature, encapsulating the changes
/// made to layers during the editing process.
///
/// This model contains two lists:
/// - `newLayers`: A list of layers that were added or modified.
/// - `deletedLayers`: A list of layers that were removed.
class PaintEditorResponse {
  /// A response model for the Paint Editor feature, containing information
  /// about the updated state of layers after an editing operation.
  ///
  /// This model includes:
  /// - A list of newly added or modified layers.
  /// - A list of layers that were deleted during the editing process.
  ///
  /// Parameters:
  /// - `newLayers`: A list of layers that have been added or updated.
  /// - `deletedLayers`: A list of layers that have been removed.
  PaintEditorResponse({required this.layers, required this.removedLayers});

  /// A list of new layers that have been added or modified in the paint editor.
  /// Each layer represents a drawable element in the editor.
  final List<Layer> layers;

  /// A list of layers that have been removed during the paint editing process.
  final List<Layer> removedLayers;
}
