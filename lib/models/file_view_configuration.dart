import 'file_item.dart';
import 'sort.dart';
import '../utils/formatters.dart';

enum FileViewDisplay { full, brief, tree, grid, column, tiles, gallery }

enum FileColumnKind {
  size,
  modified,
  extension,
  path,
  source,
  status,
  metadata,
}

class FileColumnDefinition {
  const FileColumnDefinition({
    required this.id,
    required this.label,
    required this.kind,
    this.metadataKey,
    this.localizeLabel = false,
  });
  final String id;
  final String label;
  final FileColumnKind kind;
  final String? metadataKey;

  /// Built-in labels follow the app locale; user-entered titles stay literal.
  final bool localizeLabel;

  static const defaults = [
    FileColumnDefinition(
      id: 'size',
      label: 'Size',
      kind: FileColumnKind.size,
      localizeLabel: true,
    ),
    FileColumnDefinition(
      id: 'date',
      label: 'Date',
      kind: FileColumnKind.modified,
      localizeLabel: true,
    ),
    FileColumnDefinition(
      id: 'ext',
      label: 'Ext',
      kind: FileColumnKind.extension,
      localizeLabel: true,
    ),
  ];

  SortBy? get builtInSort => switch (kind) {
    FileColumnKind.size => SortBy.size,
    FileColumnKind.modified => SortBy.date,
    FileColumnKind.extension => SortBy.extension,
    _ => null,
  };

  double get defaultWidth => switch (kind) {
    FileColumnKind.size => 62,
    FileColumnKind.modified => 78,
    FileColumnKind.extension => 40,
    FileColumnKind.path => 180,
    _ => 100,
  };

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(id) ||
        label.trim().isEmpty ||
        label.length > 80 ||
        label.contains('\u0000')) {
      throw const FormatException(
        'Each column needs a valid ID and a short title.',
      );
    }
    if (kind == FileColumnKind.metadata &&
        (metadataKey == null ||
            metadataKey!.isEmpty ||
            metadataKey!.length > 200 ||
            metadataKey!.contains('\u0000'))) {
      throw const FormatException('A metadata column requires a field name.');
    }
  }

  Object? value(FileItem file, {String? sourceLabel}) {
    if (file.name == '..') return null;
    return switch (kind) {
      FileColumnKind.size => file.displaySize,
      FileColumnKind.modified => file.updatedAt,
      FileColumnKind.extension => file.isFolder ? '' : file.extension,
      FileColumnKind.path => file.path,
      FileColumnKind.source =>
        sourceLabel ?? file.metadata?['collectionSource'],
      FileColumnKind.status => file.metadata?['collectionStatus'],
      FileColumnKind.metadata => _metadata(file.metadata, metadataKey!),
    };
  }

  String displayValue(FileItem file, {String? sourceLabel}) {
    final raw = value(file, sourceLabel: sourceLabel);
    if (kind == FileColumnKind.size &&
        file.isFolder &&
        file.calculatedSize == null) {
      return file.name == '..' ? '' : '<DIR>';
    }
    if (raw == null) return '';
    if (kind == FileColumnKind.size && raw is num) {
      return formatBytes(raw.toInt());
    }
    if (raw is DateTime) return formatDate(raw);
    if (raw is String || raw is num || raw is bool) return raw.toString();
    if (raw is List) {
      return raw
          .where((value) => value is String || value is num || value is bool)
          .take(32)
          .join(', ');
    }
    return '';
  }

  int compare(FileItem a, FileItem b) {
    final first = value(a);
    final second = value(b);
    if (first == null) return second == null ? 0 : -1;
    if (second == null) return 1;
    if (first is num && second is num) return first.compareTo(second);
    if (first is DateTime && second is DateTime) return first.compareTo(second);
    return first.toString().toLowerCase().compareTo(
      second.toString().toLowerCase(),
    );
  }

  static Object? _metadata(Map<String, dynamic>? metadata, String key) {
    if (metadata == null) return null;
    if (metadata.containsKey(key)) return metadata[key];
    Object? value = metadata;
    for (final part in key.split('.')) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'localizeLabel': localizeLabel,
    if (metadataKey != null) 'metadataKey': metadataKey,
  };

  factory FileColumnDefinition.fromJson(Map<String, dynamic> value) {
    final column = FileColumnDefinition(
      id: value['id'] as String,
      label: value['label'] as String,
      kind: FileColumnKind.values.byName(value['kind'] as String),
      metadataKey: value['metadataKey'] as String?,
      localizeLabel:
          value['localizeLabel'] as bool? ??
          defaults.any(
            (column) =>
                column.id == value['id'] &&
                column.label == value['label'] &&
                column.kind.name == value['kind'],
          ),
    );
    column.validate();
    return column;
  }
}

/// A complete tab/view snapshot. Metadata columns reference supplied metadata;
/// opening a view never executes a plugin or downloads file contents.
class FileViewConfiguration {
  FileViewConfiguration({
    this.display = FileViewDisplay.full,
    List<FileColumnDefinition> columns = FileColumnDefinition.defaults,
    Map<String, double> widths = const {'size': 62, 'date': 78, 'ext': 40},
    this.sortBy = SortBy.name,
    this.sortOrder = SortOrder.ascending,
    this.secondarySortBy,
    this.secondarySortOrder = SortOrder.ascending,
    this.sortColumnId,
    this.secondarySortColumnId,
    this.showHidden = false,
    this.filter = '',
  }) : columns = List.unmodifiable(columns),
       widths = Map.unmodifiable(widths) {
    validate();
  }
  final FileViewDisplay display;
  final List<FileColumnDefinition> columns;
  final Map<String, double> widths;
  final SortBy sortBy;
  final SortOrder sortOrder;
  final SortBy? secondarySortBy;
  final SortOrder secondarySortOrder;
  final String? sortColumnId;
  final String? secondarySortColumnId;
  final bool showHidden;
  final String filter;

  double widthFor(FileColumnDefinition column) =>
      widths[column.id] ?? column.defaultWidth;

  /// The name remains readable at narrow widths. Both headers and rows use
  /// this same calculation; widening the pane reveals the remaining columns.
  List<FileColumnDefinition> columnsFitting(double availableWidth) {
    var budget = availableWidth - 140;
    final visible = <FileColumnDefinition>[];
    for (final column in columns) {
      final width = widthFor(column);
      if (width <= 0) continue;
      if (width + 6 > budget) continue;
      visible.add(column);
      budget -= width + 6;
    }
    return visible;
  }

  void validate() {
    if (columns.length > 24 ||
        columns.map((column) => column.id).toSet().length != columns.length) {
      throw const FormatException('A view supports up to 24 distinct columns.');
    }
    for (final column in columns) {
      column.validate();
    }
    for (final width in widths.values) {
      if (!width.isFinite || width.abs() < 24 || width.abs() > 600) {
        throw const FormatException(
          'Column widths must be between 24 and 600 pixels.',
        );
      }
    }
    for (final id in [sortColumnId, secondarySortColumnId]) {
      if (id != null && !columns.any((column) => column.id == id)) {
        throw const FormatException(
          'The selected sort column is missing from the view.',
        );
      }
    }
    if (filter.length > 4096 || filter.contains('\u0000')) {
      throw const FormatException('The saved view filter is invalid.');
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'display': display.name,
    'columns': columns.map((column) => column.toJson()).toList(),
    'widths': widths,
    'sortBy': sortBy.name,
    'sortOrder': sortOrder.name,
    if (secondarySortBy != null) 'secondarySortBy': secondarySortBy!.name,
    'secondarySortOrder': secondarySortOrder.name,
    if (sortColumnId != null) 'sortColumnId': sortColumnId,
    if (secondarySortColumnId != null)
      'secondarySortColumnId': secondarySortColumnId,
    'showHidden': showHidden,
    'filter': filter,
  };

  factory FileViewConfiguration.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1) {
      throw const FormatException('Unsupported view version.');
    }
    return FileViewConfiguration(
      display: FileViewDisplay.values.byName(
        value['display'] as String? ?? 'full',
      ),
      columns: (value['columns'] as List)
          .map(
            (column) => FileColumnDefinition.fromJson(
              Map<String, dynamic>.from(column as Map),
            ),
          )
          .toList(),
      widths: (value['widths'] as Map).map(
        (key, width) => MapEntry(key as String, (width as num).toDouble()),
      ),
      sortBy: SortBy.values.byName(value['sortBy'] as String? ?? 'name'),
      sortOrder: SortOrder.values.byName(
        value['sortOrder'] as String? ?? 'ascending',
      ),
      secondarySortBy: value['secondarySortBy'] == null
          ? null
          : SortBy.values.byName(value['secondarySortBy'] as String),
      secondarySortOrder: SortOrder.values.byName(
        value['secondarySortOrder'] as String? ?? 'ascending',
      ),
      sortColumnId: value['sortColumnId'] as String?,
      secondarySortColumnId: value['secondarySortColumnId'] as String?,
      showHidden: value['showHidden'] == true,
      filter: value['filter'] as String? ?? '',
    );
  }
}
