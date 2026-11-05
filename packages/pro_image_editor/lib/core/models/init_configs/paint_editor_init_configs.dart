// Project imports:
import 'package:flutter/widgets.dart';

import 'editor_init_configs.dart';

/// Configuration class for initializing the paint editor.
///
/// This class extends [EditorInitConfigs] and adds specific parameters related
/// to paint functionality.
class PaintEditorInitConfigs extends EditorInitConfigs {
  /// Creates a new instance of [PaintEditorInitConfigs].
  ///
  /// The [theme] parameter specifies the theme data for the editor.
  /// The [imageSize] parameter specifies the size of the image.
  /// The [paddingHelper] parameter specifies additional padding for the editor.
  /// The other parameters are inherited from [EditorInitConfigs].
  const PaintEditorInitConfigs({
    super.configs,
    super.callbacks,
    super.transformConfigs,
    super.layers,
    super.mainImageSize,
    super.mainBodySize,
    super.appliedFilters,
    super.appliedTuneAdjustments,
    super.appliedBlurFactor,
    super.convertToUint8List,
    this.enableFakeHero = false,
    this.initialZoomMatrix,
    required super.theme,
  });

  /// Determines whether we draw a "fake" hero widget or not.
  final bool enableFakeHero;

  /// The initial zoom matrix.
  final Matrix4? initialZoomMatrix;
}
