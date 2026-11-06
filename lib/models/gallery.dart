import 'dart:convert';

import 'file_item.dart';

enum GalleryColor { none, red, orange, yellow, green, blue, purple }

enum GallerySort { name, extension, modified, size, rating }

/// CrispCloud catalog annotations. These do not modify embedded EXIF/XMP.
class GalleryRecord {
  const GalleryRecord({
    this.rating = 0,
    this.color = GalleryColor.none,
    this.favorite = false,
    this.tags = const [],
  });

  final int rating;
  final GalleryColor color;
  final bool favorite;
  final List<String> tags;

  bool get isEmpty =>
      rating == 0 && color == GalleryColor.none && !favorite && tags.isEmpty;

  GalleryRecord copyWith({
    int? rating,
    GalleryColor? color,
    bool? favorite,
    List<String>? tags,
  }) => GalleryRecord(
    rating: (rating ?? this.rating).clamp(0, 5),
    color: color ?? this.color,
    favorite: favorite ?? this.favorite,
    tags: List.unmodifiable(normalizeGalleryTags(tags ?? this.tags)),
  );

  Map<String, Object> toJson() => {
    'rating': rating,
    'color': color.name,
    'favorite': favorite,
    'tags': tags,
  };

  factory GalleryRecord.fromJson(Map<String, dynamic> json) => GalleryRecord(
    rating: json['rating'] is int ? (json['rating'] as int).clamp(0, 5) : 0,
    color: GalleryColor.values.firstWhere(
      (value) => value.name == json['color'],
      orElse: () => GalleryColor.none,
    ),
    favorite: json['favorite'] == true,
    tags: List.unmodifiable(
      normalizeGalleryTags(
        json['tags'] is List
            ? (json['tags'] as List).whereType<String>()
            : const <String>[],
      ),
    ),
  );
}

List<String> normalizeGalleryTags(Iterable<String> tags) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in tags) {
    final tag = raw.trim();
    if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
    result.add(tag.length > 100 ? tag.substring(0, 100) : tag);
    if (result.length == 50) break;
  }
  return result;
}

/// Includes recognizable photo formats even when the platform lacks a decoder.
/// Such files retain catalog/file actions and display an honest placeholder.
bool isGalleryImage(FileItem file) =>
    !file.isFolder &&
    const {
      'jpg',
      'jpeg',
      'jpe',
      'png',
      'apng',
      'gif',
      'webp',
      'bmp',
      'ico',
      'cur',
      'svg',
      'tif',
      'tiff',
      'tga',
      'psd',
      'psb',
      'exr',
      'hdr',
      'heic',
      'heif',
      'avif',
      'jxl',
      'jp2',
      'j2k',
      'ppm',
      'pgm',
      'pbm',
      'pcx',
      'raw',
      'dng',
      'cr2',
      'cr3',
      'nef',
      'nrw',
      'arw',
      'raf',
      'orf',
      'rw2',
      'pef',
      'srw',
    }.contains(file.extension);

/// Numeric filename ordering without parsing arbitrarily large integers.
int compareGalleryNames(String left, String right) {
  final a = RegExp(r'\d+|\D+').allMatches(left.toLowerCase()).toList();
  final b = RegExp(r'\d+|\D+').allMatches(right.toLowerCase()).toList();
  for (var index = 0; index < a.length && index < b.length; index++) {
    final x = a[index].group(0)!;
    final y = b[index].group(0)!;
    var result = 0;
    if (RegExp(r'^\d').hasMatch(x) && RegExp(r'^\d').hasMatch(y)) {
      final nx = x.replaceFirst(RegExp(r'^0+'), '');
      final ny = y.replaceFirst(RegExp(r'^0+'), '');
      result = nx.length.compareTo(ny.length);
      if (result == 0) result = nx.compareTo(ny);
      if (result == 0) result = x.length.compareTo(y.length);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  final count = a.length.compareTo(b.length);
  return count != 0 ? count : left.compareTo(right);
}

class GalleryQuery {
  const GalleryQuery({
    this.text = '',
    this.extension = '',
    this.minimumRating = 0,
    this.color,
    this.favoritesOnly = false,
    this.after,
    this.before,
    this.sort = GallerySort.name,
    this.descending = false,
  });

  final String text;
  final String extension;
  final int minimumRating;
  final GalleryColor? color;
  final bool favoritesOnly;
  final DateTime? after;
  final DateTime? before;
  final GallerySort sort;
  final bool descending;

  bool get hasFilters =>
      text.trim().isNotEmpty ||
      extension.isNotEmpty ||
      minimumRating > 0 ||
      color != null ||
      favoritesOnly ||
      after != null ||
      before != null;

  GalleryQuery copyWith({
    String? text,
    String? extension,
    int? minimumRating,
    GalleryColor? color,
    bool clearColor = false,
    bool? favoritesOnly,
    DateTime? after,
    DateTime? before,
    bool clearDates = false,
    GallerySort? sort,
    bool? descending,
  }) => GalleryQuery(
    text: text ?? this.text,
    extension: extension ?? this.extension,
    minimumRating: minimumRating ?? this.minimumRating,
    color: clearColor ? null : color ?? this.color,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    after: clearDates ? null : after ?? this.after,
    before: clearDates ? null : before ?? this.before,
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
  );

  bool get needsCatalogRecords =>
      minimumRating > 0 ||
      color != null ||
      favoritesOnly ||
      text.trim().isNotEmpty ||
      sort == GallerySort.rating;

  /// Compile once for either an ordinary listing or streamed collection pages.
  /// Callers supply annotations using the row's captured source identity.
  bool Function(FileItem, GalleryRecord) matcher({bool imagesOnly = false}) {
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));
    final end = before == null
        ? null
        : DateTime(before!.year, before!.month, before!.day + 1);
    final start = after == null
        ? null
        : DateTime(after!.year, after!.month, after!.day);
    return (file, record) {
      // Keep navigation available while filtering photographs.
      if (file.isFolder) return true;
      if (imagesOnly && !isGalleryImage(file)) return false;
      if (extension.isNotEmpty && file.extension != extension) return false;
      if (record.rating < minimumRating) return false;
      if (color != null && record.color != color) return false;
      if (favoritesOnly && !record.favorite) return false;
      if (start != null &&
          (file.updatedAt == null || file.updatedAt!.isBefore(start))) {
        return false;
      }
      if (end != null &&
          (file.updatedAt == null || !file.updatedAt!.isBefore(end))) {
        return false;
      }
      final haystack = '${file.name} ${record.tags.join(' ')}'.toLowerCase();
      return words.every(haystack.contains);
    };
  }

  int compareFiles(
    FileItem a,
    FileItem b, {
    GalleryRecord aRecord = const GalleryRecord(),
    GalleryRecord bRecord = const GalleryRecord(),
  }) {
    if (a.name == '..') return b.name == '..' ? 0 : -1;
    if (b.name == '..') return 1;
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    final comparison = switch (sort) {
      GallerySort.name => compareGalleryNames(a.name, b.name),
      GallerySort.extension => a.extension.compareTo(b.extension),
      GallerySort.modified =>
        (a.updatedAt?.millisecondsSinceEpoch ?? -1).compareTo(
          b.updatedAt?.millisecondsSinceEpoch ?? -1,
        ),
      GallerySort.size => (a.size ?? -1).compareTo(b.size ?? -1),
      GallerySort.rating => aRecord.rating.compareTo(bRecord.rating),
    };
    final stable = comparison != 0
        ? comparison
        : compareGalleryNames(a.name, b.name);
    return descending ? -stable : stable;
  }

  List<FileItem> apply(
    Iterable<FileItem> files,
    GalleryRecord Function(FileItem) recordFor, {
    bool imagesOnly = false,
  }) {
    final matches = matcher(imagesOnly: imagesOnly);
    final result = files
        .where(
          (file) => matches(
            file,
            needsCatalogRecords && !file.isFolder
                ? recordFor(file)
                : const GalleryRecord(),
          ),
        )
        .toList();
    result.sort(
      (a, b) => compareFiles(
        a,
        b,
        aRecord: sort == GallerySort.rating
            ? recordFor(a)
            : const GalleryRecord(),
        bRecord: sort == GallerySort.rating
            ? recordFor(b)
            : const GalleryRecord(),
      ),
    );
    return result;
  }
}

class GalleryPreferences {
  const GalleryPreferences({
    this.thumbnailSize = 200,
    this.fill = false,
    this.showNames = true,
    this.showDetails = true,
  });
  final double thumbnailSize;
  final bool fill;
  final bool showNames;
  final bool showDetails;

  GalleryPreferences copyWith({
    double? thumbnailSize,
    bool? fill,
    bool? showNames,
    bool? showDetails,
  }) => GalleryPreferences(
    thumbnailSize: (thumbnailSize ?? this.thumbnailSize).clamp(120, 360),
    fill: fill ?? this.fill,
    showNames: showNames ?? this.showNames,
    showDetails: showDetails ?? this.showDetails,
  );

  String encode() => jsonEncode({
    'size': thumbnailSize,
    'fill': fill,
    'names': showNames,
    'details': showDetails,
  });

  factory GalleryPreferences.decode(String raw) {
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final size = value['size'];
      return GalleryPreferences(
        thumbnailSize: size is num && size.isFinite
            ? size.toDouble().clamp(120, 360)
            : 200,
        fill: value['fill'] == true,
        showNames: value['names'] != false,
        showDetails: value['details'] != false,
      );
    } catch (_) {
      return const GalleryPreferences();
    }
  }
}
