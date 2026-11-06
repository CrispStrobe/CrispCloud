import 'package:material_ui/material_ui.dart';

import '../../core/models/editor_configs/pro_image_editor_configs.dart';
import '../../features/crop_rotate_editor/models/aspect_ratio_item.dart';

/// Keeps already-open tools in the host locale without replacing editor state.
class EditorLocalizationScope extends InheritedWidget {
  /// Provides current host labels to tools that captured older configs.
  const EditorLocalizationScope({
    super.key,
    required this.i18n,
    required this.aspectRatios,
    required super.child,
  });

  /// Current labels for the embedded tools.
  final I18n i18n;

  /// Localized aspect ratio labels; numeric values remain unchanged.
  final List<AspectRatioItem> aspectRatios;

  /// Reads the host scope, optionally registering a rebuild dependency.
  static EditorLocalizationScope? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) => listen
      ? context.dependOnInheritedWidgetOfExactType<EditorLocalizationScope>()
      : context.getInheritedWidgetOfExactType<EditorLocalizationScope>();

  /// Replaces only locale-owned configuration while retaining tool settings.
  ProImageEditorConfigs localize(ProImageEditorConfigs configs) =>
      configs.copyWith(
        i18n: i18n,
        cropRotateEditor: configs.cropRotateEditor.copyWith(
          aspectRatios: aspectRatios,
        ),
      );

  @override
  bool updateShouldNotify(EditorLocalizationScope oldWidget) =>
      !identical(i18n, oldWidget.i18n) ||
      !identical(aspectRatios, oldWidget.aspectRatios);
}
