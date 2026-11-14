import 'dart:convert';

import '../tool/mesh_portability_smoke.dart' show brickwrightTriangle3mfBase64;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show ZipWriter;
import 'package:crisp_cloud/services/mesh_preview.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';

Uint8List binaryStl({bool solid = false}) {
  final b = Uint8List(134);
  if (solid) b.setAll(0, ascii.encode('solid binary'));
  final d = ByteData.sublistView(b)..setUint32(80, 1, Endian.little);
  for (var i = 0; i < 9; i++) {
    d.setFloat32(
      96 + i * 4,
      [0, 0, 0, 1, 0, 0, 0, 1, 0][i].toDouble(),
      Endian.little,
    );
  }
  return b;
}

const triangle =
    '<mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/><vertex x="0" y="1" z="0"/></vertices><triangles><triangle v1="0" v2="1" v3="2"/></triangles></mesh>';
Uint8List threeMf({
  String geometry = triangle,
  String extra = '',
  String build = '<item objectid="1"/>',
  String unit = 'millimeter',
  String required = '',
  String target = '/3D/3dmodel.model',
  String prefix = '',
}) {
  final w = ZipWriter();
  w.addFile(
    '_rels/.rels',
    utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="$target"/></Relationships>',
    ),
  );
  w.addFile(
    '3D/3dmodel.model',
    utf8.encode(
      '$prefix<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" unit="$unit" requiredextensions="$required"><resources><object id="1">$geometry</object>$extra</resources><build>$build</build></model>',
    ),
  );
  return w.close();
}

void main() {
  test('imports the current Brickwright CAD exporter output', () {
    final mesh = decodePreviewMesh(
      base64Decode(brickwrightTriangle3mfBase64),
      filename: 'brickwright.3mf',
    );
    expect(mesh.triangleCount, 1);
    expect(mesh.positions, [0, 0, 0, 10, 0, 0, 0, 10, 0]);
  });
  for (final solid in [false, true]) {
    test('binary STL, solid header=$solid', () {
      final m = decodePreviewMesh(binaryStl(solid: solid), filename: 'x.stl');
      expect(m.positions, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
      expect(m.triangleCount, 1);
    });
  }
  const text =
      'solid sample\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid sample';
  test('ASCII STL', () {
    expect(
      decodePreviewMesh(
        Uint8List.fromList(ascii.encode(text)),
        filename: 'x.stl',
      ).triangleCount,
      1,
    );
  });
  test('nonfinite STL', () {
    final b = binaryStl();
    ByteData.sublistView(b).setFloat32(96, double.nan, Endian.little);
    expect(
      () => decodePreviewMesh(b, filename: 'x.stl'),
      throwsFormatException,
    );
  });
  test('truncated binary', () {
    expect(
      () => decodePreviewMesh(binaryStl().sublist(0, 133), filename: 'x.stl'),
      throwsFormatException,
    );
  });
  for (final input in [
    'solid x\n',
    'solid x\nfacet normal 0 0 1\n',
    'solid x\nendsolid x',
    text.replaceFirst('endsolid sample', ''),
  ]) {
    test('malformed or empty ASCII $input', () {
      expect(
        () => decodePreviewMesh(
          Uint8List.fromList(ascii.encode(input)),
          filename: 'x.stl',
        ),
        throwsFormatException,
      );
    });
  }
  test('triangle limit before allocation', () {
    final b = Uint8List(84 + 50001 * 50);
    ByteData.sublistView(b).setUint32(80, 50001, Endian.little);
    expect(
      () => decodePreviewMesh(b, filename: 'x.stl'),
      throwsFormatException,
    );
  });
  test('byte limit', () {
    expect(
      () => decodePreviewMesh(
        Uint8List(meshPreviewByteLimit + 1),
        filename: 'x.3mf',
      ),
      throwsFormatException,
    );
  });
  test('core 3MF relationship', () {
    final m = decodePreviewMesh(threeMf(), filename: 'x.3mf');
    expect(m.positions, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
    expect(m.unit, 'mm');
  });
  test('units and build transform', () {
    final m = decodePreviewMesh(
      threeMf(
        unit: 'inch',
        build: '<item objectid="1" transform="1 0 0 0 1 0 0 0 1 2 0 0"/>',
      ),
      filename: 'x.3mf',
    );
    expect(m.positions[0], closeTo(50.8, 1e-9));
    expect(m.positions[3], closeTo(76.2, 1e-9));
  });
  test('component transform before build transform', () {
    final m = decodePreviewMesh(
      threeMf(
        extra: '<object id="2"><components><component objectid="1" transform="1 0 0 0 1 0 0 0 1 2 0 0"/></components></object>',
        build: '<item objectid="2" transform="2 0 0 0 2 0 0 0 2 0 0 0"/>',
      ),
      filename: 'x.3mf',
    );
    expect(m.positions[0], 4);
    expect(m.positions[3], 6);
  });
  final invalid = {
    'bad index': threeMf(geometry: triangle.replaceFirst('v3="2"', 'v3="99"')),
    'missing object': threeMf(build: '<item objectid="9"/>'),
    'cycle': threeMf(
      geometry: '<components><component objectid="1"/></components>',
    ),
    'external object': threeMf(
      geometry: '<components><component objectid="1" path="/other.model"/></components>',
    ),
    'required extension': threeMf(required: 'p'),
    'unknown unit': threeMf(unit: 'furlong'),
    'DTD': threeMf(prefix: '<!DOCTYPE model [<!ENTITY x "unsafe">]>'),
    'traversal relationship': threeMf(target: '../3D/3dmodel.model'),
    'empty build': threeMf(build: ''),
  };
  for (final entry in invalid.entries) {
    test('refuse ${entry.key}', () {
      expect(
        () => decodePreviewMesh(entry.value, filename: 'x.3mf'),
        throwsFormatException,
      );
    });
  }
  test('repeated components share the unique vertex budget', () {
    final extraVertices = '<vertex x="0" y="0" z="0"/>' * 25000;
    final geometry = triangle.replaceFirst(
      '</vertices>',
      '$extraVertices</vertices>',
    );
    final mesh = decodePreviewMesh(
      threeMf(geometry: geometry, build: '<item objectid="1"/>' * 6),
      filename: 'instances.3mf',
    );
    expect(mesh.triangleCount, 6);
  });
  test('F3 recognizes STL and 3MF before ZIP magic', () {
    const s = InternalViewerService();
    expect(s.detectMode('x.STL', header: binaryStl()), ViewerMode.model3d);
    expect(s.detectMode('x.3mf', header: threeMf()), ViewerMode.model3d);
    expect(s.detectMode('x.zip', header: threeMf()), ViewerMode.archive);
  });
}
