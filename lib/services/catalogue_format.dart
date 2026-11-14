import 'dart:typed_data';

enum CatalogueFormat { native, caf }

/// Do not steal Apple's Core Audio CAF files or arbitrary SQLite databases.
CatalogueFormat? catalogueFormat(String name, List<int> prefix) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.crispindex') &&
      prefix.length >= 16 &&
      String.fromCharCodes(prefix.take(16)) == 'SQLite format 3\u0000') {
    return CatalogueFormat.native;
  }
  if (!lower.endsWith('.caf') || prefix.length < 4) return null;
  final data = ByteData.sublistView(
    Uint8List.fromList(prefix.take(6).toList()),
  );
  final magic = data.getUint32(0, Endian.little);
  if (magic == 0 || magic % 1000000000 != 500410407) return null;
  var version = magic ~/ 1000000000;
  if (version > 2) {
    if (prefix.length < 6) return null;
    version = data.getInt16(4, Endian.little);
  }
  return version >= 1 && version <= 8 ? CatalogueFormat.caf : null;
}
