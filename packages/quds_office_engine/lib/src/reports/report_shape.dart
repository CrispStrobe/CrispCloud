/// Region outlines for a shape map: a bundled world atlas, an imported
/// shapefile or GeoJSON, and the compact form saved in a `.qrep`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'report_data.dart';
import 'world_countries.dart';

/// Thrown when shape bytes are not a shapefile, GeoJSON, or a shape layer.
class ReportShapeException implements Exception {
  /// ReportShapeException API.
  const ReportShapeException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ReportShapeException: $message';
}

/// One closed ring. A [hole] is drawn in the ocean color.
class ReportShapeRing {
  /// ReportShapeRing API.
  ReportShapeRing({required this.hole, required this.lonLat});

  /// Interior ring.
  final bool hole;

  /// Interleaved longitude, latitude in degrees.
  final Float64List lonLat;

  /// Vertices.
  int get length => lonLat.length ~/ 2;

  /// Signed area in square degrees (positive is counter-clockwise).
  double get signedArea {
    if (length < 3) {
      return 0;
    }
    var sum = 0.0;
    for (int i = 0; i < length; i++) {
      final int j = (i + 1) % length;
      sum += lonLat[i * 2] * lonLat[j * 2 + 1];
      sum -= lonLat[j * 2] * lonLat[i * 2 + 1];
    }
    return sum / 2;
  }
}

/// One named region (a country, a district, a custom polygon).
class ReportShapeFeature {
  /// ReportShapeFeature API.
  ReportShapeFeature({
    required this.key,
    required this.label,
    List<String>? aliases,
    List<ReportShapeRing>? rings,
    Map<String, String>? values,
  }) : aliases = aliases ?? <String>[],
       rings = rings ?? <ReportShapeRing>[],
       values = Map<String, String>.unmodifiable(values ?? const <String, String>{});

  /// Value the report data matches (`LY`, `LBY`, a district code).
  final String key;

  /// Name drawn on a wide region when no label field is chosen.
  final String label;

  /// Other spellings that match this region (`Libya`, `ليبيا`).
  final List<String> aliases;

  /// Outer rings and holes.
  final List<ReportShapeRing> rings;

  /// Attribute columns from the shapefile or GeoJSON, keyed by field name.
  final Map<String, String> values;

  /// The attribute [field], or empty when this feature has no such column.
  String valueOf(String? field) {
    final String want = (field ?? '').trim().toLowerCase();
    if (want.isEmpty) {
      return '';
    }
    for (final MapEntry<String, String> entry in values.entries) {
      if (entry.key.toLowerCase() == want) {
        return entry.value.trim();
      }
    }
    return '';
  }
}

/// A shape file read for a report: the layer to embed, and the attribute
/// whose values are the region keys (null for a `.qmap`, which already
/// stores them).
class ReportShapeFile {
  /// ReportShapeFile API.
  const ReportShapeFile({required this.layer, this.keyField, this.nameField});

  /// Regions to store under `shapes/` in the `.qrep`.
  final ReportShapeLayer layer;

  /// Shapefile or GeoJSON attribute that supplied [ReportShapeFeature.key].
  final String? keyField;

  /// Attribute best suited to be drawn as the region name.
  final String? nameField;
}

/// A set of regions drawn as one map.
class ReportShapeLayer {
  /// ReportShapeLayer API.
  ReportShapeLayer(List<ReportShapeFeature> features, {List<String>? fields})
    : features = List<ReportShapeFeature>.unmodifiable(features),
      fields = List<String>.unmodifiable(fields ?? const <String>[]);

  /// features API.
  final List<ReportShapeFeature> features;

  /// Attribute columns stored with an imported file, in file order.
  /// Empty for the bundled world atlas and for layers saved before
  /// columns were kept.
  final List<String> fields;

  Map<String, int>? _index;

  /// Feature whose key or alias equals [raw] (case and surrounding space
  /// ignored), or null.
  ReportShapeFeature? find(String raw) {
    final int? i = indexOf(raw);
    return i == null ? null : features[i];
  }

  /// Index of [find], or null.
  int? indexOf(String raw) {
    final Map<String, int> index = _index ??= _build();
    return index[_norm(raw)];
  }

  Map<String, int> _build() {
    final Map<String, int> out = <String, int>{};
    for (int i = 0; i < features.length; i++) {
      final ReportShapeFeature f = features[i];
      out.putIfAbsent(_norm(f.key), () => i);
      out.putIfAbsent(_norm(f.label), () => i);
      for (final String a in f.aliases) {
        out.putIfAbsent(_norm(a), () => i);
      }
    }
    return out;
  }

  static String _norm(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Compact bytes (`QMAP`) stored under `shapes/` in a `.qrep`.
  ///
  /// Version 2 stores each coordinate as microdegrees, so a district
  /// boundary stays smooth when the map fills the page. Version 3 also
  /// stores every attribute column, so a label can use a field other
  /// than the key. Version 1 (the bundled world atlas) is still read.
  Uint8List encode() {
    final BytesBuilder b = BytesBuilder();
    final bool rich = fields.isNotEmpty;
    b.add(<int>[0x51, 0x4D, 0x41, 0x50, rich ? 3 : 2]);
    _u16(b, features.length);
    final List<String> columns = rich
        ? fields.take(255).toList(growable: false)
        : const <String>[];
    if (rich) {
      b.addByte(columns.length);
      for (final String name in columns) {
        _str(b, name);
      }
    }
    for (final ReportShapeFeature f in features) {
      _str(b, f.key);
      _str(b, f.label);
      final List<String> aliases = <String>[
        for (final String a in f.aliases)
          if (a.trim().isNotEmpty) a.trim(),
      ];
      b.addByte(math.min(aliases.length, 255));
      for (int i = 0; i < aliases.length && i < 255; i++) {
        _str(b, aliases[i]);
      }
      for (final String name in columns) {
        _str(b, f.valueOf(name));
      }
      _u16(b, f.rings.length);
      for (final ReportShapeRing ring in f.rings) {
        _u16(b, ring.length);
        b.addByte(ring.hole ? 1 : 0);
        for (int i = 0; i < ring.length; i++) {
          _i32(b, _micro(ring.lonLat[i * 2], 180));
          _i32(b, _micro(ring.lonLat[i * 2 + 1], 90));
        }
      }
    }
    return b.takeBytes();
  }

  /// Reads [encode].
  static ReportShapeLayer decode(Uint8List bytes) {
    if (bytes.length < 7 ||
        bytes[0] != 0x51 ||
        bytes[1] != 0x4D ||
        bytes[2] != 0x41 ||
        bytes[3] != 0x50) {
      throw const ReportShapeException('Not a shape layer');
    }
    final int version = bytes[4];
    if (version != 1 && version != 2 && version != 3) {
      throw ReportShapeException('Unknown shape layer version $version');
    }
    final ByteData data = ByteData.sublistView(bytes);
    var o = 5;
    final int count = _readU16(data, o);
    o += 2;
    final List<String> columns = <String>[];
    if (version == 3) {
      if (o >= bytes.length) {
        throw const ReportShapeException('Truncated shape layer');
      }
      final int fieldCount = bytes[o];
      o++;
      for (int i = 0; i < fieldCount; i++) {
        final (String name, int n) = _readStr(bytes, o);
        o = n;
        columns.add(name);
      }
    }
    final List<ReportShapeFeature> features = <ReportShapeFeature>[];
    for (int i = 0; i < count; i++) {
      final (String key, int k) = _readStr(bytes, o);
      o = k;
      final (String label, int l) = _readStr(bytes, o);
      o = l;
      if (o >= bytes.length) {
        throw const ReportShapeException('Truncated shape layer');
      }
      final int aliases = bytes[o];
      o++;
      final List<String> names = <String>[];
      for (int a = 0; a < aliases; a++) {
        final (String name, int n) = _readStr(bytes, o);
        o = n;
        names.add(name);
      }
      final Map<String, String> values = <String, String>{};
      for (final String name in columns) {
        final (String value, int n) = _readStr(bytes, o);
        o = n;
        values[name] = value;
      }
      final int rings = _readU16(data, o);
      o += 2;
      final List<ReportShapeRing> parts = <ReportShapeRing>[];
      for (int r = 0; r < rings; r++) {
        final int n = _readU16(data, o);
        o += 2;
        if (o >= bytes.length) {
          throw const ReportShapeException('Truncated shape layer');
        }
        final bool hole = bytes[o] == 1;
        o++;
        final Float64List lonLat = Float64List(n * 2);
        for (int p = 0; p < n; p++) {
          if (version == 1) {
            lonLat[p * 2] = _readI16(data, o) / 100;
            o += 2;
            lonLat[p * 2 + 1] = _readI16(data, o) / 100;
            o += 2;
          } else {
            lonLat[p * 2] = _readI32(data, o) / 1000000;
            o += 4;
            lonLat[p * 2 + 1] = _readI32(data, o) / 1000000;
            o += 4;
          }
        }
        if (n >= 3) {
          parts.add(ReportShapeRing(hole: hole, lonLat: lonLat));
        }
      }
      features.add(
        ReportShapeFeature(
          key: key,
          label: label.isEmpty ? key : label,
          aliases: names,
          rings: parts,
          values: values,
        ),
      );
    }
    return ReportShapeLayer(features, fields: columns);
  }

  /// Shapefile (`.shp`), GeoJSON, or [encode] bytes. [attributes] is the
  /// `.dbf` beside a shapefile. [keyField] names the attribute used as
  /// [ReportShapeFeature.key]; without it a code or name column is chosen.
  static ReportShapeLayer parse(
    Uint8List bytes, {
    Uint8List? attributes,
    String? keyField,
    String? nameField,
  }) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x51 &&
        bytes[1] == 0x4D &&
        bytes[2] == 0x41 &&
        bytes[3] == 0x50) {
      return decode(bytes);
    }
    if (bytes.length >= 4 &&
        ByteData.sublistView(bytes).getInt32(0, Endian.big) == 9994) {
      return parseShapefile(
        bytes,
        attributes: attributes,
        keyField: keyField,
        nameField: nameField,
      );
    }
    return parseGeoJson(
      utf8.decode(bytes, allowMalformed: true),
      keyField: keyField,
      nameField: nameField,
    );
  }

  /// Reads a shape file and names the attribute that became each region's key.
  ///
  /// A `.qmap` already has its keys, so [ReportShapeFile.keyField] is null.
  static ReportShapeFile read(
    Uint8List bytes, {
    Uint8List? attributes,
    String? keyField,
    String? nameField,
  }) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x51 &&
        bytes[1] == 0x4D &&
        bytes[2] == 0x41 &&
        bytes[3] == 0x50) {
      return ReportShapeFile(layer: decode(bytes));
    }
    if (bytes.length >= 4 &&
        ByteData.sublistView(bytes).getInt32(0, Endian.big) == 9994) {
      final ReportShapeLayer layer = parseShapefile(
        bytes,
        attributes: attributes,
        keyField: keyField,
        nameField: nameField,
      );
      _requireGeographic(layer);
      return ReportShapeFile(
        layer: layer,
        keyField: _dbfKeyName(attributes, keyField),
        nameField: _dbfLabelName(attributes, nameField),
      );
    }
    final String text = utf8.decode(bytes, allowMalformed: true);
    final ReportShapeLayer layer = parseGeoJson(
      text,
      keyField: keyField,
      nameField: nameField,
    );
    _requireGeographic(layer);
    return ReportShapeFile(
      layer: layer,
      keyField: _geoKeyName(text, keyField),
      nameField: _geoLabelName(text, nameField),
    );
  }

  /// Refuses a projected shapefile (metres) instead of clamping it into
  /// a blob at the edge of the degree range.
  static void _requireGeographic(ReportShapeLayer layer) {
    for (final ReportShapeFeature feature in layer.features) {
      for (final ReportShapeRing ring in feature.rings) {
        for (int i = 0; i < ring.length; i++) {
          final double lon = ring.lonLat[i * 2];
          final double lat = ring.lonLat[i * 2 + 1];
          if (lon.abs() > 180.0001 || lat.abs() > 90.0001) {
            throw const ReportShapeException(
              'This file is not longitude and latitude. '
              'Reproject it to WGS84 (EPSG:4326) and import it again.',
            );
          }
        }
      }
    }
  }

  /// ESRI polygon shapefile. [attributes] supplies the region key.
  static ReportShapeLayer parseShapefile(
    Uint8List shp, {
    Uint8List? attributes,
    String? keyField,
    String? nameField,
  }) {
    if (shp.length < 100 ||
        ByteData.sublistView(shp).getInt32(0, Endian.big) != 9994) {
      throw const ReportShapeException('Not a shapefile');
    }
    final _Dbf? dbf = attributes == null ? null : _Dbf.parse(attributes);
    final int namedKey = dbf?.column(keyField) ?? -1;
    final int keyCol = namedKey >= 0 ? namedKey : (dbf?.preferredKey() ?? -1);
    final int nameCol = dbf?.column(nameField) ?? -1;
    final ByteData data = ByteData.sublistView(shp);
    final List<ReportShapeFeature> features = <ReportShapeFeature>[];
    var offset = 100;
    var row = 0;
    while (offset + 8 <= shp.length) {
      final int words = data.getInt32(offset + 4, Endian.big);
      final int content = words * 2;
      if (content < 4 || offset + 8 + content > shp.length) {
        break;
      }
      final int type = data.getInt32(offset + 8, Endian.little);
      final List<String> record = dbf == null || row >= dbf.rows.length
          ? const <String>[]
          : dbf.rows[row];
      row++;
      if (type == 5 || type == 15 || type == 25) {
        final List<ReportShapeRing> rings = _shpRings(
          data,
          offset + 12,
          offset + 8 + content,
        );
        if (rings.isNotEmpty) {
          final String key = keyCol >= 0 && keyCol < record.length
              ? record[keyCol].trim()
              : '$row';
          final String named = nameCol >= 0 && nameCol < record.length
              ? record[nameCol].trim()
              : '';
          features.add(
            ReportShapeFeature(
              key: key.isEmpty ? '$row' : key,
              label: named.isEmpty ? (key.isEmpty ? '$row' : key) : named,
              aliases: named.isEmpty || named == key
                  ? const <String>[]
                  : <String>[named],
              rings: rings,
              values: _rowValues(dbf, record),
            ),
          );
        }
      }
      offset += 8 + content;
    }
    if (features.isEmpty) {
      throw const ReportShapeException('The shapefile has no polygons');
    }
    return ReportShapeLayer(features, fields: dbf?.fields ?? const <String>[]);
  }

  static Map<String, String> _rowValues(_Dbf? dbf, List<String> record) {
    if (dbf == null) {
      return const <String, String>{};
    }
    final Map<String, String> values = <String, String>{};
    for (int c = 0; c < dbf.fields.length && c < record.length; c++) {
      values[dbf.fields[c]] = record[c].trim();
    }
    return values;
  }

  /// GeoJSON `FeatureCollection`, `Feature`, or `Polygon`.
  static ReportShapeLayer parseGeoJson(
    String text, {
    String? keyField,
    String? nameField,
  }) {
    final Object? decoded;
    try {
      decoded = ReportData.fromJsonValue(jsonDecode(text));
    } on FormatException catch (e) {
      throw ReportShapeException('Invalid GeoJSON: $e');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ReportShapeException('GeoJSON must be an object');
    }
    final List<Map<String, Object?>> features = <Map<String, Object?>>[];
    final String? type = decoded['type'] as String?;
    if (type == 'FeatureCollection') {
      final Object? list = decoded['features'];
      if (list is List<Object?>) {
        for (final Object? item in list) {
          if (item is Map<String, Object?>) {
            features.add(item);
          }
        }
      }
    } else if (type == 'Feature') {
      features.add(decoded);
    } else if (type == 'Polygon' || type == 'MultiPolygon') {
      features.add(<String, Object?>{
        'type': 'Feature',
        'geometry': decoded,
        'properties': <String, Object?>{},
      });
    }
    final List<ReportShapeFeature> out = <ReportShapeFeature>[];
    final List<String> fields = <String>[];
    for (int i = 0; i < features.length; i++) {
      final Map<String, Object?> feature = features[i];
      final Object? geometry = feature['geometry'];
      if (geometry is! Map<String, Object?>) {
        continue;
      }
      final List<ReportShapeRing> rings = _geoRings(geometry);
      if (rings.isEmpty) {
        continue;
      }
      final Map<String, Object?> props =
          feature['properties'] is Map<String, Object?>
          ? feature['properties']! as Map<String, Object?>
          : const <String, Object?>{};
      final String key =
          _prop(props, keyField) ?? _autoKey(props) ?? '${i + 1}';
      final String label =
          _prop(props, nameField) ??
          _prop(props, 'NAME') ??
          _prop(props, 'name') ??
          key;
      out.add(
        ReportShapeFeature(
          key: key,
          label: label,
          aliases: _aliases(props, key, label),
          rings: rings,
          values: _propValues(props, fields),
        ),
      );
    }
    if (out.isEmpty) {
      throw const ReportShapeException('The GeoJSON has no polygons');
    }
    return ReportShapeLayer(out, fields: fields);
  }

  static Map<String, String> _propValues(
    Map<String, Object?> props,
    List<String> fields,
  ) {
    final Map<String, String> values = <String, String>{};
    for (final MapEntry<String, Object?> entry in props.entries) {
      final String name = entry.key.trim();
      if (name.isEmpty) {
        continue;
      }
      if (!fields.any((String f) => f.toLowerCase() == name.toLowerCase())) {
        fields.add(name);
      }
      final Object? raw = entry.value;
      values[name] = raw == null ? '' : '$raw'.trim();
    }
    return values;
  }

  static List<ReportShapeRing> _shpRings(ByteData data, int start, int end) {
    if (start + 40 > end) {
      return const <ReportShapeRing>[];
    }
    final int parts = data.getInt32(start + 32, Endian.little);
    final int points = data.getInt32(start + 36, Endian.little);
    if (parts <= 0 || points < 3) {
      return const <ReportShapeRing>[];
    }
    final int partsAt = start + 40;
    final int pointsAt = partsAt + parts * 4;
    if (pointsAt + points * 16 > end + 1) {
      return const <ReportShapeRing>[];
    }
    final List<int> index = <int>[
      for (int i = 0; i < parts; i++)
        data.getInt32(partsAt + i * 4, Endian.little),
    ];
    final List<ReportShapeRing> rings = <ReportShapeRing>[];
    for (int p = 0; p < parts; p++) {
      final int from = index[p];
      final int to = p + 1 < parts ? index[p + 1] : points;
      if (to - from < 3) {
        continue;
      }
      final Float64List lonLat = Float64List((to - from) * 2);
      var n = 0;
      for (int i = from; i < to; i++) {
        final double lon = data.getFloat64(pointsAt + i * 16, Endian.little);
        final double lat = data.getFloat64(
          pointsAt + i * 16 + 8,
          Endian.little,
        );
        if (n > 0 &&
            lonLat[(n - 1) * 2] == lon &&
            lonLat[(n - 1) * 2 + 1] == lat) {
          continue;
        }
        lonLat[n * 2] = lon;
        lonLat[n * 2 + 1] = lat;
        n++;
      }
      if (n >= 2 &&
          lonLat[0] == lonLat[(n - 1) * 2] &&
          lonLat[1] == lonLat[(n - 1) * 2 + 1]) {
        n--;
      }
      if (n >= 3) {
        rings.add(ReportShapeRing(hole: false, lonLat: _copy(lonLat, n)));
      }
    }
    if (rings.length > 1) {
      var main = 0;
      var biggest = 0.0;
      final List<double> areas = <double>[
        for (final ReportShapeRing r in rings) r.signedArea,
      ];
      for (int i = 0; i < areas.length; i++) {
        final double a = areas[i].abs();
        if (a > biggest) {
          biggest = a;
          main = i;
        }
      }
      final double sign = areas[main];
      return <ReportShapeRing>[
        for (int i = 0; i < rings.length; i++)
          ReportShapeRing(
            hole: i != main && areas[i] * sign < 0,
            lonLat: rings[i].lonLat,
          ),
      ];
    }
    return rings;
  }

  static List<ReportShapeRing> _geoRings(Map<String, Object?> geometry) {
    final String? type = geometry['type'] as String?;
    final Object? coords = geometry['coordinates'];
    if (type == 'Polygon') {
      return _polygon(coords);
    }
    if (type == 'MultiPolygon' && coords is List<Object?>) {
      return <ReportShapeRing>[
        for (final Object? polygon in coords) ..._polygon(polygon),
      ];
    }
    if (type == 'GeometryCollection') {
      final Object? list = geometry['geometries'];
      if (list is List<Object?>) {
        return <ReportShapeRing>[
          for (final Object? g in list)
            if (g is Map<String, Object?>) ..._geoRings(g),
        ];
      }
    }
    return const <ReportShapeRing>[];
  }

  static List<ReportShapeRing> _polygon(Object? coords) {
    if (coords is! List<Object?>) {
      return const <ReportShapeRing>[];
    }
    final List<ReportShapeRing> rings = <ReportShapeRing>[];
    for (int i = 0; i < coords.length; i++) {
      final Float64List? lonLat = _positions(coords[i]);
      if (lonLat != null) {
        rings.add(ReportShapeRing(hole: i > 0, lonLat: lonLat));
      }
    }
    return rings;
  }

  static Float64List? _positions(Object? ring) {
    if (ring is! List<Object?>) {
      return null;
    }
    final Float64List lonLat = Float64List(ring.length * 2);
    var n = 0;
    for (final Object? point in ring) {
      if (point is! List<Object?> || point.length < 2) {
        continue;
      }
      final Object? lon = point[0];
      final Object? lat = point[1];
      if (lon is! num || lat is! num) {
        continue;
      }
      if (n > 0 &&
          lonLat[(n - 1) * 2] == lon.toDouble() &&
          lonLat[(n - 1) * 2 + 1] == lat.toDouble()) {
        continue;
      }
      lonLat[n * 2] = lon.toDouble();
      lonLat[n * 2 + 1] = lat.toDouble();
      n++;
    }
    if (n >= 2 &&
        lonLat[0] == lonLat[(n - 1) * 2] &&
        lonLat[1] == lonLat[(n - 1) * 2 + 1]) {
      n--;
    }
    if (n < 3) {
      return null;
    }
    return _copy(lonLat, n);
  }

  static Float64List _copy(Float64List source, int vertices) {
    if (source.length == vertices * 2) {
      return source;
    }
    final Float64List out = Float64List(vertices * 2);
    out.setRange(0, vertices * 2, source);
    return out;
  }

  static String? _prop(Map<String, Object?> props, String? name) {
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    final String want = name.trim().toLowerCase();
    for (final MapEntry<String, Object?> e in props.entries) {
      if (e.key.toLowerCase() == want && e.value != null) {
        final String text = '${e.value}'.trim();
        if (text.isNotEmpty && text != '-99' && text != 'None') {
          return text;
        }
      }
    }
    return null;
  }

  static String? _dbfLabelName(Uint8List? attributes, String? requested) {
    if (attributes == null) {
      return null;
    }
    final _Dbf dbf = _Dbf.parse(attributes);
    return _namedColumn(dbf.fields, dbf.column(requested), const <String>[
      'name',
      'name_en',
      'name_ar',
      'label',
      'title',
    ]);
  }

  static String? _geoLabelName(String text, String? requested) {
    final List<String> fields = _geoFields(text);
    if (fields.isEmpty) {
      return null;
    }
    if (requested != null && requested.trim().isNotEmpty) {
      for (final String name in fields) {
        if (name.toLowerCase() == requested.trim().toLowerCase()) {
          return name;
        }
      }
    }
    return _namedColumn(fields, -1, const <String>[
      'name',
      'name_en',
      'name_ar',
      'label',
      'title',
    ]);
  }

  static List<String> _geoFields(String text) {
    final Object? decoded;
    try {
      decoded = ReportData.fromJsonValue(jsonDecode(text));
    } on FormatException {
      return const <String>[];
    }
    if (decoded is! Map<String, Object?>) {
      return const <String>[];
    }
    final Object? list = decoded['features'];
    if (list is! List<Object?> || list.isEmpty) {
      return const <String>[];
    }
    final Object? first = list.first;
    if (first is! Map<String, Object?>) {
      return const <String>[];
    }
    final Object? props = first['properties'];
    if (props is! Map<String, Object?>) {
      return const <String>[];
    }
    return <String>[for (final String key in props.keys) key];
  }

  static String? _namedColumn(
    List<String> fields,
    int named,
    List<String> prefer,
  ) {
    if (named >= 0 &&
        named < fields.length &&
        fields[named].trim().isNotEmpty) {
      return fields[named];
    }
    for (final String want in prefer) {
      for (final String name in fields) {
        if (name.toLowerCase() == want && name.trim().isNotEmpty) {
          return name;
        }
      }
    }
    return null;
  }

  static String? _dbfKeyName(Uint8List? attributes, String? requested) {
    if (attributes == null) {
      return null;
    }
    final _Dbf dbf = _Dbf.parse(attributes);
    final int named = dbf.column(requested);
    final int col = named >= 0 ? named : dbf.preferredKey();
    if (col < 0 || col >= dbf.fields.length) {
      return null;
    }
    final String name = dbf.fields[col].trim();
    return name.isEmpty ? null : name;
  }

  static String? _geoKeyName(String text, String? requested) {
    final Object? decoded;
    try {
      decoded = ReportData.fromJsonValue(jsonDecode(text));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    Map<String, Object?>? props;
    final String? type = decoded['type'] as String?;
    if (type == 'Feature') {
      final Object? p = decoded['properties'];
      if (p is Map<String, Object?>) {
        props = p;
      }
    } else if (type == 'FeatureCollection') {
      final Object? list = decoded['features'];
      if (list is List<Object?>) {
        for (final Object? item in list) {
          if (item is Map<String, Object?>) {
            final Object? p = item['properties'];
            if (p is Map<String, Object?> && p.isNotEmpty) {
              props = p;
              break;
            }
          }
        }
      }
    }
    if (props == null) {
      return null;
    }
    String? match(String name) {
      final String want = name.trim().toLowerCase();
      for (final MapEntry<String, Object?> e in props!.entries) {
        if (e.key.toLowerCase() == want && _prop(props, e.key) != null) {
          return e.key;
        }
      }
      return null;
    }

    if (requested != null && requested.trim().isNotEmpty) {
      return match(requested);
    }
    for (final String name in const <String>[
      'ISO_A2',
      'iso_a2',
      'ISO_A3',
      'ADM0_A3',
      'code',
      'CODE',
      'id',
      'ID',
      'NAME',
      'name',
    ]) {
      final String? found = match(name);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static String? _autoKey(Map<String, Object?> props) {
    for (final String name in const <String>[
      'ISO_A2',
      'iso_a2',
      'ISO_A3',
      'ADM0_A3',
      'code',
      'CODE',
      'id',
      'ID',
      'NAME',
      'name',
    ]) {
      final String? v = _prop(props, name);
      if (v != null) {
        return v;
      }
    }
    return null;
  }

  static List<String> _aliases(
    Map<String, Object?> props,
    String key,
    String label,
  ) {
    final List<String> out = <String>[];
    void add(String? v) {
      if (v == null) {
        return;
      }
      final String t = v.trim();
      if (t.isEmpty || t == key || t == label || out.contains(t)) {
        return;
      }
      if (out.length < 12) {
        out.add(t);
      }
    }

    for (final String name in const <String>[
      'ISO_A2',
      'ISO_A3',
      'ADM0_A3',
      'NAME',
      'ADMIN',
      'NAME_EN',
      'NAME_AR',
      'NAME_FR',
    ]) {
      add(_prop(props, name));
    }
    return out;
  }

  /// Microdegrees. 0.000001° is about 11 cm, so a diagonal border does
  /// not turn into a staircase when the map is drawn large.
  static int _micro(double degrees, double limit) {
    final double c = degrees.clamp(-limit, limit).toDouble();
    return (c * 1000000).round().clamp(-200000000, 200000000);
  }

  static void _u16(BytesBuilder b, int v) {
    final ByteData d = ByteData(2)..setUint16(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  static void _i32(BytesBuilder b, int v) {
    final ByteData d = ByteData(4)..setInt32(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  static void _str(BytesBuilder b, String text) {
    final List<int> bytes = utf8.encode(text);
    final int n = math.min(bytes.length, 255);
    b.addByte(n);
    b.add(bytes.sublist(0, n));
  }

  static int _readU16(ByteData data, int o) {
    if (o + 2 > data.lengthInBytes) {
      throw const ReportShapeException('Truncated shape layer');
    }
    return data.getUint16(o, Endian.little);
  }

  static int _readI16(ByteData data, int o) {
    if (o + 2 > data.lengthInBytes) {
      throw const ReportShapeException('Truncated shape layer');
    }
    return data.getInt16(o, Endian.little);
  }

  static int _readI32(ByteData data, int o) {
    if (o + 4 > data.lengthInBytes) {
      throw const ReportShapeException('Truncated shape layer');
    }
    return data.getInt32(o, Endian.little);
  }

  static (String, int) _readStr(Uint8List bytes, int o) {
    if (o >= bytes.length) {
      throw const ReportShapeException('Truncated shape layer');
    }
    final int n = bytes[o];
    final int end = o + 1 + n;
    if (end > bytes.length) {
      throw const ReportShapeException('Truncated shape layer');
    }
    return (utf8.decode(bytes.sublist(o + 1, end), allowMalformed: true), end);
  }
}

/// Bundled admin-0 countries, keyed by ISO code and by English, Arabic,
/// and French names.
abstract final class WorldCountries {
  static ReportShapeLayer? _layer;

  /// Decoded world atlas.
  static ReportShapeLayer get layer =>
      _layer ??= ReportShapeLayer.decode(worldCountriesAtlas);
}

/// `world` and `countries` are the bundled atlas. Anything else is an
/// embedded shape layer.
abstract final class ReportShapes {
  /// Name of the bundled atlas.
  static const String world = 'world';

  /// Whether [name] selects [WorldCountries].
  static bool isWorld(String name) {
    final String n = name.trim().toLowerCase();
    return n.isEmpty || n == 'world' || n == 'countries';
  }

  /// Layer for a chart `shape` attribute.
  static ReportShapeLayer? resolve(
    String name,
    Map<String, Uint8List> embedded,
  ) {
    if (isWorld(name)) {
      return WorldCountries.layer;
    }
    final Uint8List? bytes = embedded[name];
    if (bytes == null) {
      return null;
    }
    try {
      return ReportShapeLayer.decode(bytes);
    } on ReportShapeException {
      return null;
    }
  }
}

class _Dbf {
  _Dbf(this.fields, this.rows);

  final List<String> fields;
  final List<List<String>> rows;

  static _Dbf parse(Uint8List bytes) {
    if (bytes.length < 32) {
      throw const ReportShapeException('The .dbf file is too small');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int records = data.getUint32(4, Endian.little);
    final int header = data.getUint16(8, Endian.little);
    final int record = data.getUint16(10, Endian.little);
    final List<(String, int, int)> fields = <(String, int, int)>[];
    var at = 32;
    var width = 1;
    while (at + 32 <= header && bytes[at] != 0x0D) {
      final String name = latin1
          .decode(bytes.sublist(at, at + 11))
          .replaceAll('\u0000', '')
          .trim();
      final int length = bytes[at + 16];
      fields.add((name, width, length));
      width += length;
      at += 32;
    }
    final List<List<String>> rows = <List<String>>[];
    for (int r = 0; r < records; r++) {
      final int start = header + r * record;
      if (start + record > bytes.length) {
        break;
      }
      rows.add(<String>[
        for (final (String, int, int) f in fields)
          _cell(bytes.sublist(start + f.$2, start + f.$2 + f.$3)),
      ]);
    }
    return _Dbf(<String>[
      for (final (String, int, int) f in fields) f.$1,
    ], rows);
  }

  int column(String? name) {
    if (name == null || name.trim().isEmpty) {
      return -1;
    }
    final String want = name.trim().toLowerCase();
    for (int i = 0; i < fields.length; i++) {
      if (fields[i].toLowerCase() == want) {
        return i;
      }
    }
    return -1;
  }

  int preferredKey() {
    for (final String name in const <String>[
      'iso_a2',
      'iso_a3',
      'adm0_a3',
      'code',
      'id',
      'name',
    ]) {
      final int i = column(name);
      if (i >= 0) {
        return i;
      }
    }
    return fields.isEmpty ? -1 : 0;
  }

  static String _cell(List<int> bytes) {
    try {
      return utf8.decode(bytes).trim();
    } on FormatException {
      return latin1.decode(bytes).trim();
    }
  }
}
