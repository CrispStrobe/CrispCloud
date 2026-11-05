import 'package:material_ui/material_ui.dart';

import '/core/models/custom_widgets/layer_interaction_widgets.dart';
import '/core/models/i18n/i18n_layer_interaction.dart';
import '/core/models/icons/layer_interaction_icons.dart';

/// Represents a context menu for interacting with a layer widget.
class LayerWidgetContextMenu {
  /// Creates a [LayerWidgetContextMenu] with the required callbacks and
  /// interaction configurations.
  LayerWidgetContextMenu({
    required this.onRemoveTap,
    required this.onEditTap,
    required this.onContextMenuToggled,
    required this.i18nLayerInteraction,
    required this.layerInteractionIcons,
    this.contextMenuBuilder,
  });

  /// Callback triggered when the layer is removed.
  final Function()? onRemoveTap;

  /// Callback triggered when the layer is edited.
  final Function()? onEditTap;

  /// Callback triggered when the context menu is opened or closed.
  final Function(bool isOpen)? onContextMenuToggled;

  /// Provides localized strings for layer interactions.
  final I18nLayerInteraction i18nLayerInteraction;

  /// Provides icons for layer interaction actions.
  final LayerInteractionIcons layerInteractionIcons;

  /// Optional host-rendered menu, using the host's own theme and localizations.
  final LayerContextMenuBuilder? contextMenuBuilder;

  bool _isOpen = false;

  /// Opens the context menu at the specified position.
  ///
  /// The menu allows users to edit or remove a layer based on the provided
  /// permissions.
  Future<void> open({
    required BuildContext context,
    required TapUpDetails details,
    required bool enableEditButton,
    required bool enableRemoveButton,
  }) async {
    if (_isOpen || (!enableEditButton && !enableRemoveButton)) return;
    _isOpen = true;
    final clickPosition = details.globalPosition;
    const spacing = 14.0;
    try {
      onContextMenuToggled?.call(true);
      final builder = contextMenuBuilder;
      final selectedValue = builder != null
          ? await builder(
              context,
              clickPosition,
              canEdit: enableEditButton,
              canRemove: enableRemoveButton,
            )
          : await showMenu<LayerContextMenuAction>(
              context: context,
              useRootNavigator: true,
              position: RelativeRect.fromLTRB(
                clickPosition.dx,
                clickPosition.dy,
                clickPosition.dx + 1.0,
                clickPosition.dy + 1.0,
              ),
              items: <PopupMenuEntry<LayerContextMenuAction>>[
                if (enableEditButton)
                  PopupMenuItem<LayerContextMenuAction>(
                    value: LayerContextMenuAction.edit,
                    child: Row(
                      spacing: spacing,
                      children: [
                        Icon(layerInteractionIcons.edit),
                        Text(i18nLayerInteraction.edit),
                      ],
                    ),
                  ),
                if (enableRemoveButton)
                  PopupMenuItem<LayerContextMenuAction>(
                    value: LayerContextMenuAction.remove,
                    child: Row(
                      spacing: spacing,
                      children: [
                        Icon(layerInteractionIcons.remove),
                        Text(i18nLayerInteraction.remove),
                      ],
                    ),
                  ),
              ],
            );
      if (!context.mounted) return;
      switch (selectedValue) {
        case LayerContextMenuAction.edit when enableEditButton:
          onEditTap?.call();
        case LayerContextMenuAction.remove when enableRemoveButton:
          onRemoveTap?.call();
        default:
          break;
      }
    } finally {
      _isOpen = false;
      onContextMenuToggled?.call(false);
    }
  }
}
