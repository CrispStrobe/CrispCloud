import '/core/models/layers/layer_interaction.dart';
import '/shared/services/import_export/utils/key_minifier.dart';
import '../../constants/export_import_version.dart';

/// Handles the compatibility of layer interactions based on the provided
/// version.
///
/// This function updates the `layerMap` to ensure compatibility with different
/// versions of the export/import format. It converts the interaction-related keys
/// using the provided `minifier` and updates the `layerMap` accordingly.
///
/// If the `enableInteraction` key is present in the `layerMap`, it converts it
/// to the `interaction` key using the `LayerInteraction` class and the provided
/// `minifier`.
///
/// Parameters:
/// - `layerMap`: A map representing the layer data.
/// - `version`: The version of the export/import format.
/// - `minifier`: An instance of `EditorKeyMinifier` used to convert keys.
void historyCompatibilityLayerInteraction({
  required Map<String, dynamic> layerMap,
  required String version,
  required EditorKeyMinifier minifier,
}) {
  final importVersion = version.toVersionNumber();
  final latestIncompatibleVersion = ExportImportVersion.version_5_0_0
      .toVersionNumber();

  if (importVersion <= latestIncompatibleVersion) {
    var keyConverter = minifier.convertLayerKey;
    if (layerMap[keyConverter('enableInteraction')] != null) {
      var interactionMap = LayerInteraction.fromDefaultValue(
        layerMap[keyConverter('enableInteraction')] == true,
      ).toMap();
      layerMap[keyConverter('interaction')] = interactionMap.map(
        (itemKey, itemValue) =>
            MapEntry(minifier.convertLayerInteractionKey(itemKey), itemValue),
      );
    }
  }
}
