import 'package:flutter/widgets.dart';

/// An abstract base class for editor layer configuration objects.
///
/// Provides a common interface and shared properties for configuring
/// layers within the editor. Subclasses should extend this class to
/// define specific configuration options for different types of layers.
///
/// [layerFractionalOffset] specifies the initial position of the layer
/// as a fractional offset within the editor's coordinate space.
/// Defaults to [Offset(-0.5, -0.5)].
abstract class BaseEditorLayerConfigs {
  /// Creates a [BaseEditorLayerConfigs] instance.
  const BaseEditorLayerConfigs({
    this.layerFractionalOffset = const Offset(-0.5, -0.5),
  });

  /// {@template layerFractionalOffset}
  /// The layer fractional offset to apply to the layer's child widget.
  ///
  /// This offset is relative to the child's size, where (0, 0) represents
  /// no translation, and values are scaled based on the child’s width and
  /// height.
  ///
  /// For example, an [Offset] of (0.25, 0.0) translates the child 25% of its
  /// width to the right, while (-0.5, -0.5) centers the child if its
  /// alignment is top-left.
  ///
  /// By default, this value is [Offset(-0.5, -0.5)] to center the layer.
  /// {@endtemplate}
  final Offset layerFractionalOffset;
}
