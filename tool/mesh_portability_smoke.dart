// Authored triangle emitted by Brickwright CAD bd03ee7b's current 3MF exporter.
// No model-library asset or third-party geometry is included.
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart'
    show ZipReader, ZipWriter;

import '../test/support/mesh_fixtures.dart';
import '../lib/services/mesh_preview.dart';

void main() {
  final mesh = decodePreviewMesh(
    base64Decode(brickwrightTriangle3mfBase64),
    filename: 'brickwright.3mf',
  );
  if (mesh.triangleCount != 1 ||
      mesh.unit != 'mm' ||
      mesh.positions[3] != 10 ||
      mesh.positions[7] != 10) {
    throw StateError('Brickwright 3MF geometry did not survive import.');
  }
  final stl = Uint8List(134);
  final view = ByteData.sublistView(stl)..setUint32(80, 1, Endian.little);
  view.setFloat32(108, 1, Endian.little);
  view.setFloat32(124, 1, Endian.little);
  if (decodePreviewMesh(stl, filename: 'authored.stl').triangleCount != 1)
    throw StateError('STL import failed.');
  final original = ZipReader.fromBytes(
    base64Decode(brickwrightTriangle3mfBase64),
  );
  final package = ZipWriter()
    ..addFile('_rels/.rels', original.read('_rels/.rels'))
    ..addFile(
      '3D/3dmodel.model',
      utf8.encode(
        '<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:prod="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" requiredextensions="prod"><resources><object id="1"><components><component objectid="1" prod:path="/3D/object.model"/></components></object></resources><build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 2 0 0"/></build></model>',
      ),
    )
    ..addFile('3D/object.model', original.read('3D/3dmodel.model'));
  final production = decodePreviewMesh(
    package.close(),
    filename: 'production.3mf',
  );
  if (production.triangleCount != 1 ||
      production.positions[0] != 2 ||
      production.positions[3] != 12) {
    throw StateError('3MF production package geometry did not survive import.');
  }
  print(
    'STL, current Brickwright 3MF and cross-part production imports passed.',
  );
}
