// models/file_item.dart

import 'package:cross_file/cross_file.dart'; // Add this import

class FileItem {
  final String name;
  final String? path;
  final String? uuid;
  final bool isFolder;
  final int? size;
  final DateTime? updatedAt;
  final XFile? xFile;

  /// Extra provider-specific metadata not covered by the standard fields.
  final Map<String, dynamic>? metadata;

  /// Whether this item is a symbolic link (detected on local filesystem).
  final bool? isSymlink;

  /// The target path of a symbolic link.
  final String? symlinkTarget;

  /// Pre-calculated folder size (populated on demand, not by default listing).
  final int? calculatedSize;

  FileItem({
    required this.name,
    this.path,
    this.uuid,
    required this.isFolder,
    this.size,
    this.updatedAt,
    this.xFile,
    this.metadata,
    this.isSymlink,
    this.symlinkTarget,
    this.calculatedSize,
  });

  /// File extension (lowercase), or empty string for folders / files without extension.
  String get extension =>
      isFolder ? '' : (name.contains('.') ? name.split('.').last.toLowerCase() : '');

  /// Display size: uses [calculatedSize] if available, else [size].
  int? get displaySize => calculatedSize ?? size;

  String get sizeFormatted {
    final s = displaySize;
    if (s == null) return '';
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    if (s < 1024 * 1024 * 1024) {
      return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(s / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Create a copy with selectively overridden fields.
  FileItem copyWith({
    String? name,
    String? path,
    String? uuid,
    bool? isFolder,
    int? size,
    DateTime? updatedAt,
    XFile? xFile,
    Map<String, dynamic>? metadata,
    bool? isSymlink,
    String? symlinkTarget,
    int? calculatedSize,
  }) {
    return FileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      uuid: uuid ?? this.uuid,
      isFolder: isFolder ?? this.isFolder,
      size: size ?? this.size,
      updatedAt: updatedAt ?? this.updatedAt,
      xFile: xFile ?? this.xFile,
      metadata: metadata ?? this.metadata,
      isSymlink: isSymlink ?? this.isSymlink,
      symlinkTarget: symlinkTarget ?? this.symlinkTarget,
      calculatedSize: calculatedSize ?? this.calculatedSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileItem &&
          runtimeType == other.runtimeType &&
          (uuid != null ? uuid == other.uuid : path == other.path);

  @override
  int get hashCode => uuid?.hashCode ?? path.hashCode;
}
