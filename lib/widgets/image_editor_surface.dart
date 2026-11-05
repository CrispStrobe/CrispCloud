import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:pro_image_editor/pro_image_editor.dart';

import '../l10n/image_editor_strings.dart';
import '../services/image_edit_session.dart';

/// The third-party surface is confined to its own theme/localization scope.
/// CrispCloud retains its normal Material widgets, menus, and save lifecycle.
class ImageEditorSurface extends StatelessWidget {
  const ImageEditorSurface({
    super.key,
    required this.bytes,
    required this.info,
    required this.editorKey,
    required this.callbacks,
    this.enableIsolateGeneration = true,
  });

  final Uint8List bytes;
  final ImageFileInfo info;
  final GlobalKey<ProImageEditorState> editorKey;
  final ProImageEditorCallbacks callbacks;
  final bool enableIsolateGeneration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorTheme = material.ThemeData(
      useMaterial3: true,
      brightness: theme.brightness,
      colorSchemeSeed: colors.primary,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
    );
    final longestSide = (info.width > info.height ? info.width : info.height)
        .toDouble();
    return Localizations.override(
      context: context,
      delegates: material.GlobalMaterialLocalizations.delegates,
      child: material.Theme(
        data: editorTheme,
        child: ProImageEditor.memory(
          bytes,
          key: editorKey,
          callbacks: callbacks,
          configs: ProImageEditorConfigs(
            theme: editorTheme,
            i18n: ImageEditorStrings.editorI18n(context),
            designMode: ImageEditorDesignMode.material,
            imageGeneration: ImageGenerationConfigs(
              outputFormat: info.format == ImageFileFormat.png
                  ? OutputFormat.png
                  : OutputFormat.jpg,
              cropToImageBounds: true,
              cropToDrawingBounds: false,
              // A square bound preserves portrait/landscape resolution after
              // rotation; the default 2000x2000 bound would shrink photographs.
              maxOutputSize: Size(longestSide, longestSide),
              captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
              enableUseOriginalBytes: true,
              enableBackgroundGeneration: false,
              enableIsolateGeneration: enableIsolateGeneration,
            ),
            mainEditor: MainEditorConfigs(
              hostOwnsNavigation: true,
              enableKeyboardShortcuts: false,
              enableEscapeButton: false,
              enableCloseButton: false,
              enableSubEditorPage: true,
              tools: const [
                SubEditorMode.paint,
                SubEditorMode.text,
                SubEditorMode.cropRotate,
                SubEditorMode.tune,
                SubEditorMode.filter,
                SubEditorMode.blur,
              ],
              widgets: MainEditorWidgets(
                appBar: (_, __) => null,
                bottomBar: (_, __, ___) => null,
              ),
              style: MainEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                bottomBarBackground: colors.surface,
                bottomBarColor: colors.onSurface,
              ),
            ),
            layerInteraction: LayerInteractionConfigs(
              widgets: LayerInteractionWidgets(
                contextMenuBuilder: (_, position, {
                  required bool canEdit,
                  required bool canRemove,
                }) => _showLayerMenu(context, position,
                    canEdit: canEdit, canRemove: canRemove),
              ),
            ),
            paintEditor: PaintEditorConfigs(
              style: PaintEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                bottomBarBackground: colors.surface,
                bottomBarActiveItemColor: colors.primary,
                bottomBarInactiveItemColor: colors.onSurfaceVariant,
                lineWidthBottomSheetBackground: colors.surface,
                opacityBottomSheetBackground: colors.surface,
                editSheetBackgroundColor: colors.surface,
                editSheetColor: colors.onSurface,
                editSheetPreviewAreaColor: colors.surfaceContainerHighest,
              ),
            ),
            textEditor: TextEditorConfigs(
              style: TextEditorStyle(
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                bottomBarBackground: colors.surface,
                inputHintColor: colors.onSurfaceVariant,
                inputCursorColor: colors.primary,
                fontScaleBottomSheetBackground: colors.surface,
              ),
            ),
            cropRotateEditor: CropRotateEditorConfigs(
              aspectRatios: [
                AspectRatioItem(text: context.imageTr('Free'), value: -1),
                AspectRatioItem(text: context.imageTr('Original'), value: 0),
                const AspectRatioItem(text: '1:1', value: 1),
                const AspectRatioItem(text: '4:3', value: 4 / 3),
                const AspectRatioItem(text: '3:4', value: 3 / 4),
                const AspectRatioItem(text: '16:9', value: 16 / 9),
                const AspectRatioItem(text: '9:16', value: 9 / 16),
              ],
              style: CropRotateEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                bottomBarBackground: colors.surface,
                bottomBarColor: colors.onSurface,
                cropCornerColor: colors.primary,
                aspectRatioSheetBackgroundColor: colors.surface,
                aspectRatioSheetForegroundColor: colors.onSurface,
              ),
            ),
            filterEditor: FilterEditorConfigs(
              style: FilterEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                previewTextColor: colors.onSurfaceVariant,
                previewSelectedTextColor: colors.primary,
              ),
            ),
            tuneEditor: TuneEditorConfigs(
              style: TuneEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackground: colors.surface,
                appBarColor: colors.onSurface,
                bottomBarBackground: colors.surface,
                bottomBarActiveItemColor: colors.primary,
                bottomBarInactiveItemColor: colors.onSurfaceVariant,
              ),
            ),
            blurEditor: BlurEditorConfigs(
              style: BlurEditorStyle(
                background: colors.surfaceContainerLowest,
                appBarBackgroundColor: colors.surface,
                appBarForegroundColor: colors.onSurface,
              ),
            ),
            // The tools whitelist excludes emoji and stickers. Do not preload
            // an unused emoji web font or request it over the network.
            emojiEditor: const EmojiEditorConfigs(enablePreloadWebFont: false),
          ),
        ),
      ),
    );
  }

  Future<LayerContextMenuAction?> _showLayerMenu(
    BuildContext context,
    Offset globalPosition, {
    required bool canEdit,
    required bool canRemove,
  }) {
    // Use CrispCloud's Flutter Material popup on the host navigator. A package
    // Material UI popup would lose its scoped localizations on that overlay.
    final overlay = Navigator.of(context, rootNavigator: true)
        .overlay!.context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    return showMenu<LayerContextMenuAction>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (canEdit) PopupMenuItem(
          value: LayerContextMenuAction.edit,
          child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.imageTr('Edit')),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        if (canRemove) PopupMenuItem(
          value: LayerContextMenuAction.remove,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.imageTr('Remove')),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }
}
