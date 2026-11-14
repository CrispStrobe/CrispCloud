// STL decoding is adapted from Brickwright CAD's BSD-3-Clause files.ts.
// Copyright (c) 2026 Christian Ströbele (CrispStrobe).
// Modified for bounded Dart decoding and portable read-only previews.
// See docs/third-party/brickwright-cad/ for attribution and scope.
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart' show ZipReader;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const meshPreviewByteLimit = 16 * 1024 * 1024;
const meshPreviewTriangleLimit = 50000;
const _core = 'http://schemas.microsoft.com/3dmanufacturing/core/2015/02';

/// Expanded triangles, in millimetres for 3MF; STL carries no unit metadata.
class PreviewMesh {
  PreviewMesh(this.positions, {required this.format, required this.unit});
  final Float64List positions;
  final String format;
  final String unit;
  int get triangleCount => positions.length ~/ 9;
}

Never _invalid(String message) => throw FormatException(message);

double _number(String? value) {
  final n = double.tryParse(value ?? '');
  if (n == null || !n.isFinite || n.abs() > 1e9) {
    _invalid('Invalid or excessive model coordinate.');
  }
  return n;
}

PreviewMesh decodePreviewMesh(Uint8List bytes, {required String filename}) {
  if (bytes.length > meshPreviewByteLimit) {
    _invalid('3D preview is limited to 16 MiB.');
  }
  if (filename.toLowerCase().endsWith('.3mf') ||
      (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b)) {
    return _threeMf(bytes);
  }
  return _stl(bytes);
}

PreviewMesh _stl(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final count = bytes.length >= 84 ? view.getUint32(80, Endian.little) : 0;
  final values = <double>[];
  void add(double value) {
    if (!value.isFinite || value.abs() > 1e9) {
      _invalid('Invalid STL coordinate.');
    }
    values.add(value);
    if (values.length > meshPreviewTriangleLimit * 9) {
      _invalid('3D preview is limited to 50,000 triangles.');
    }
  }

  // A binary STL may start with "solid"; its exact byte count takes priority.
  if (count > 0 && bytes.length == 84 + count * 50) {
    if (count > meshPreviewTriangleLimit) {
      _invalid('3D preview is limited to 50,000 triangles.');
    }
    for (var i = 0; i < count; i++) {
      for (var j = 0; j < 9; j++) {
        add(view.getFloat32(84 + i * 50 + 12 + j * 4, Endian.little));
      }
    }
  } else {
    final text = utf8.decode(bytes);
    final tokens = RegExp(r'\S+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .iterator;
    String next() {
      if (!tokens.moveNext()) _invalid('Truncated ASCII STL.');
      return tokens.current;
    }

    if (next() != 'solid') _invalid('Not a binary or ASCII STL.');
    // Solid names are arbitrary text to the end of the first line.
    final firstLine = text.indexOf('\n');
    if (firstLine < 0) _invalid('Missing STL facets.');
    final body = RegExp(r'\S+')
        .allMatches(text.substring(firstLine + 1))
        .map((m) => m.group(0)!)
        .iterator;
    String take() {
      if (!body.moveNext()) _invalid('Truncated ASCII STL.');
      return body.current;
    }

    void expect(String word) {
      if (take() != word) _invalid('Malformed ASCII STL facet.');
    }

    var closed = false;
    while (body.moveNext()) {
      if (body.current == 'endsolid') {
        closed = true;
        break;
      }
      if (body.current != 'facet') _invalid('Malformed ASCII STL facet.');
      expect('normal');
      for (var j = 0; j < 3; j++) {
        _number(take());
      }
      expect('outer');
      expect('loop');
      for (var j = 0; j < 3; j++) {
        expect('vertex');
        for (var k = 0; k < 3; k++) {
          add(_number(take()));
        }
      }
      expect('endloop');
      expect('endfacet');
    }
    if (!closed) _invalid('Missing STL endsolid.');
    while (body.moveNext()) {
      if (body.current == 'solid' || body.current == 'facet') {
        _invalid('Multiple ASCII STL solids are unsupported.');
      }
    }
  }
  if (values.isEmpty) _invalid('The model contains no triangles.');
  return PreviewMesh(
    Float64List.fromList(values),
    format: 'STL',
    unit: 'unitless',
  );
}

XmlElement _xml(Uint8List bytes) {
  final text = utf8.decode(bytes);
  // No entity declarations, DTDs, network references or XML expansion.
  if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
    _invalid('DTD/entity declarations are unsupported.');
  }
  var depth = 0;
  var events = 0;
  for (final event in parseEvents(text)) {
    if (++events > 1000000) _invalid('3MF XML is too complex.');
    if (event is XmlStartElementEvent && !event.isSelfClosing && ++depth > 48) {
      _invalid('3MF XML is too deeply nested.');
    }
    if (event is XmlEndElementEvent) depth--;
  }
  return XmlDocument.parse(text).rootElement;
}

List<XmlElement> _children(XmlElement element, String name) => element
    .childElements
    .where(
      (e) => e.name.local == name && e.namespaceUri == element.namespaceUri,
    )
    .toList();
XmlElement _one(XmlElement element, String name) {
  final children = _children(element, name);
  if (children.length != 1) _invalid('Expected one 3MF $name element.');
  return children.single;
}

int _id(String? value) {
  final result = int.tryParse(value ?? '');
  if (result == null || result < 0) _invalid('Invalid 3MF reference.');
  return result;
}

List<double>? _transform(XmlElement e) {
  if (e.attributes.any((a) => a.name.local == 'path')) {
    _invalid('External 3MF object references are unsupported.');
  }
  final value = e.getAttribute('transform');
  if (value == null) return null;
  final result = value.trim().split(RegExp(r'\s+')).map(_number).toList();
  if (result.length != 12) _invalid('Invalid 3MF transform.');
  return result;
}

PreviewMesh _threeMf(Uint8List bytes) {
  final zip = ZipReader.fromBytes(
    bytes,
    maxEntries: 4096,
    rejectDuplicateNames: true,
  );
  for (final entry in zip.entries) {
    final name = entry.fileName;
    if (name.contains('\\') ||
        name.startsWith('/') ||
        name.split('/').contains('..')) {
      _invalid('Unsafe 3MF package path.');
    }
  }
  final relations = _xml(zip.read('_rels/.rels', maxBytes: 256 * 1024));
  final models = relations.childElements
      .where(
        (e) =>
            e.name.local == 'Relationship' &&
            e.getAttribute('Type') ==
                'http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel',
      )
      .toList();
  if (models.length != 1 ||
      models.single.getAttribute('TargetMode') == 'External') {
    _invalid('Missing or external 3MF model relationship.');
  }
  var path = models.single.getAttribute('Target') ?? '';
  if (path.startsWith('/')) path = path.substring(1);
  if (path.isEmpty ||
      path.split('/').any((p) => p == '..' || p == '.') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('%')) {
    _invalid('Unsupported 3MF model path.');
  }
  final model = _xml(zip.read(path, maxBytes: meshPreviewByteLimit));
  if (model.name.local != 'model' || model.namespaceUri != _core) {
    _invalid('Not a 3MF core model.');
  }
  if ((model.getAttribute('requiredextensions') ?? '').trim().isNotEmpty) {
    _invalid('This model requires unsupported 3MF extensions.');
  }
  final scale = switch (model.getAttribute('unit') ?? 'millimeter') {
    'micron' => 0.001,
    'millimeter' => 1.0,
    'centimeter' => 10.0,
    'inch' => 25.4,
    'foot' => 304.8,
    'meter' => 1000.0,
    _ => throw const FormatException('Unsupported 3MF unit.'),
  };
  final objects = <int, XmlElement>{};
  for (final object in _children(_one(model, 'resources'), 'object')) {
    final id = _id(object.getAttribute('id'));
    if (objects.containsKey(id)) _invalid('Duplicate 3MF object ID.');
    objects[id] = object;
  }
  final values = <double>[];
  final parsedMeshes = <int, (List<List<double>>, List<List<int>>)>{};
  var vertexBudget = 0;
  var visits = 0;
  void emit(int id, List<List<double>> transforms, Set<int> active) {
    if (active.contains(id) || active.length >= 32 || ++visits > 4096) {
      _invalid('Cyclic or excessive 3MF components.');
    }
    final object = objects[id];
    if (object == null) _invalid('Missing 3MF object.');
    final meshes = _children(object, 'mesh');
    final components = _children(object, 'components');
    if (meshes.length + components.length != 1) {
      _invalid('Unsupported 3MF object geometry.');
    }
    if (components.isNotEmpty) {
      for (final component in _children(components.single, 'component')) {
        final transform = _transform(component);
        emit(
          _id(component.getAttribute('objectid')),
          [...transforms, if (transform != null) transform],
          {...active, id},
        );
      }
      return;
    }
    var decoded = parsedMeshes[id];
    if (decoded == null) {
      final mesh = meshes.single;
      final vertexElements = _children(_one(mesh, 'vertices'), 'vertex');
      vertexBudget += vertexElements.length;
      if (vertexBudget > 150000) _invalid('Too many 3MF vertices.');
      final vertices = vertexElements
          .map(
            (v) => [
              _number(v.getAttribute('x')),
              _number(v.getAttribute('y')),
              _number(v.getAttribute('z')),
            ],
          )
          .toList();
      final triangleElements = _children(_one(mesh, 'triangles'), 'triangle');
      if (triangleElements.length > meshPreviewTriangleLimit) {
        _invalid('3D preview is limited to 50,000 triangles.');
      }
      final indices = triangleElements
          .map(
            (t) => ['v1', 'v2', 'v3'].map((a) {
              final index = _id(t.getAttribute(a));
              if (index >= vertices.length)
                _invalid('Invalid 3MF triangle index.');
              return index;
            }).toList(),
          )
          .toList();
      decoded = (vertices, indices);
      parsedMeshes[id] = decoded;
    }
    final vertices = decoded.$1;
    for (final triangle in decoded.$2) {
      if (values.length >= meshPreviewTriangleLimit * 9) {
        _invalid('3D preview is limited to 50,000 triangles.');
      }
      for (final index in triangle) {
        var [x, y, z] = vertices[index];
        for (final t in transforms.reversed) {
          final nx = x * t[0] + y * t[3] + z * t[6] + t[9];
          final ny = x * t[1] + y * t[4] + z * t[7] + t[10];
          final nz = x * t[2] + y * t[5] + z * t[8] + t[11];
          x = nx;
          y = ny;
          z = nz;
        }
        for (final n in [x * scale, y * scale, z * scale]) {
          if (!n.isFinite || n.abs() > 1e9) {
            _invalid('Excessive transformed coordinate.');
          }
          values.add(n);
        }
      }
    }
  }

  for (final item in _children(_one(model, 'build'), 'item')) {
    if (item.getAttribute('printable') == '0' ||
        item.getAttribute('printable') == 'false') {
      continue;
    }
    final transform = _transform(item);
    emit(_id(item.getAttribute('objectid')), [
      if (transform != null) transform,
    ], {});
  }
  if (values.isEmpty) _invalid('The model contains no printable triangles.');
  return PreviewMesh(Float64List.fromList(values), format: '3MF', unit: 'mm');
}
