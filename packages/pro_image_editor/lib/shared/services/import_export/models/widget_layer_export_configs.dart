/// A class that represents the export configurations for a widget layer.
class WidgetLayerExportConfigs {
  /// Creates a [WidgetLayerExportConfigs] instance with the provided
  /// configuration values.
  ///
  /// Only one parameter except `meta` can be non-null.
  /// If more than one parameter is provided, an assertion error will be thrown.
  ///
  /// {@template widgetLoaderIdWarning}
  /// If you use the ID parameter, it is important to set up a `widgetLoader`
  /// inside the `ImportEditorConfigs`when importing the state history.
  /// Refer to the [import-example](https://github.com/hm21/pro_image_editor/blob/stable/example/lib/features/import_export_example.dart)
  /// for details on how this works.
  /// {@endtemplate}
  const WidgetLayerExportConfigs({
    this.id,
    this.networkUrl,
    this.assetPath,
    this.fileUrl,
    this.meta,
  }) : assert(
         (id != null ? 1 : 0) +
                 (networkUrl != null ? 1 : 0) +
                 (assetPath != null ? 1 : 0) +
                 (fileUrl != null ? 1 : 0) <=
             1,
         'Only one parameter can be non-null',
       );

  /// Creates a [WidgetLayerExportConfigs] instance from a [Map].
  ///
  /// If the [map] is `null`, an empty map is used.
  factory WidgetLayerExportConfigs.fromMap(Map<String, dynamic>? map) {
    map ??= {};
    return WidgetLayerExportConfigs(
      id: map['id'],
      networkUrl: map['networkUrl'],
      assetPath: map['assetPath'],
      fileUrl: map['fileUrl'],
      meta: map['meta'],
    );
  }

  /// The id from the widget to restore it.
  ///
  /// {@macro widgetLoaderIdWarning}
  final String? id;

  /// The network url to the widget to restore it. That can only restore images.
  final String? networkUrl;

  /// The asset path to the widget to restore it. That can only restore images.
  final String? assetPath;

  /// The file url to the widget to restore it. That can only restore images.
  final String? fileUrl;

  /// A map containing metadata associated with the widget layer.
  /// The keys are strings representing the metadata field names, and the values
  /// are dynamic, allowing for various types of metadata values.
  ///
  /// This can be used to store additional information about the widget layer
  /// that may be needed for import/export operations.
  final Map<String, dynamic>? meta;

  /// Checks if the widget layer has any of the parameters set.
  ///
  /// Returns `true` if any of the following parameters are not null:
  /// - [id]
  /// - [networkUrl]
  /// - [assetPath]
  /// - [fileUrl]
  /// - [fileUrl]
  /// Otherwise, returns `false`.
  bool get hasParameter =>
      id != null ||
      networkUrl != null ||
      assetPath != null ||
      fileUrl != null ||
      (meta != null && meta!.isNotEmpty);

  /// Converts the [WidgetLayerExportConfigs] instance into a [Map].
  ///
  /// Only non-null fields are included in the map.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (networkUrl != null) 'networkUrl': networkUrl,
      if (assetPath != null) 'assetPath': assetPath,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (meta != null) 'meta': meta,
    };
  }

  /// Creates a copy of the current [WidgetLayerExportConfigs] with optional
  /// updated fields.
  ///
  /// If a field is not provided, the value from the current instance is used.
  WidgetLayerExportConfigs copyWith({
    String? id,
    String? networkUrl,
    String? assetPath,
    String? fileUrl,
    Map<String, dynamic>? meta,
  }) {
    return WidgetLayerExportConfigs(
      id: id ?? this.id,
      networkUrl: networkUrl ?? this.networkUrl,
      assetPath: assetPath ?? this.assetPath,
      fileUrl: fileUrl ?? this.fileUrl,
      meta: meta ?? this.meta,
    );
  }
}
