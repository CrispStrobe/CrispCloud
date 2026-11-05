// ignore_for_file: unintended_html_in_doc_comment

import 'package:flutter/widgets.dart';

/// {@template widgetLoader}
/// This function allows you to import widget layers using your own logic.
/// Add an `exportConfig` with an ID to your `WidgetLayer`. After that,
/// this function will be triggered to import the layer using the specified ID.
///
/// Parameters:
/// - `id` (String): The export ID of the widget to be loaded.
/// - `meta` (Map<String, dynamic>?): Additional information about the widget.
///
/// Returns:
/// - `Widget`: The widget corresponding to the given export ID.
///
/// **Example:**
///
/// Add to the editor:
/// ```dart
/// editor.addLayer(
///   WidgetLayer(
///     exportConfigs: const WidgetLayerExportConfigs(
///       id: 'my-special-container',
///     ),
///     widget: Container(
///       width: 100,
///       height: 100,
///       color: Colors.amber,
///     ),
///   ),
/// );
/// ```
///
/// Import:
/// ```dart
/// editor.importStateHistory(
///   ImportStateHistory.fromJson(
///     savedHistory,
///     configs: ImportEditorConfigs(
///         widgetLoader: (
///           String id, {
///           Map<String, dynamic>? meta,
///         }) {
///         switch (id) {
///           case 'my-special-container':
///             return Container(
///               width: 100,
///               height: 100,
///               color: Colors.amber,
///             );
///
///           /// ... other widgets
///         }
///         throw ArgumentError(
///           'No widget found for the given id: $id',
///         );
///       },
///     ),
///   ),
/// );
/// ```
///
/// {@endtemplate}
typedef WidgetLoader = Widget Function(String id, {Map<String, dynamic>? meta});
