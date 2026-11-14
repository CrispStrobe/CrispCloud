// Authored triangle emitted by Brickwright CAD bd03ee7b's current 3MF exporter.
// No model-library asset or third-party geometry is included.
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart'
    show ZipReader, ZipWriter;

import '../lib/services/mesh_preview.dart';

const brickwrightTriangle3mfBase64 =
    'UEsDBBQAAAAIAKOkbl3kFNlasQAAACwBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbIWQXQrCMBCErxLyKm2qgg/S1g'
    'f1Bl5gSbdtMH8k21Jvb9oqggg+zs7sfDDlaTKajRiicrbi27zgp7q8PTxGlhwbK94T+aMQUfZoIObOo01O64IBSjJ0'
    'woO8Q4diVxQHIZ0ltJTR3MHr8oItDJrYdUrnlRJQR87Oa3BmVRy810oCJV+MtvmiZC9Cnj6XTOyVj5sU4OInwbgG9R'
    '+E+dTuGwN2aEHSEJTtsqTngjdALHvUT1BLAwQUAAAACACjpG5d/ELM9aMAAADxAAAACwAAAF9yZWxzLy5yZWxzZY9N'
    'CsIwEIWvEuYAmdSCC2najRu30guEdJoGmx+SVPT2RkGwuBmYmfe+x+uGh1vZnVK2wUtouICh7660qlIPebExs6rwWc'
    'JSSjwhZr2QU5mHSL5+5pCcKnVNBqPSN2UID0IcMf0yYM9ko0qGigRsz9hOLky08s8EdpkkVK8ANj4j/cU6q1PIYS5c'
    'B/f2Kr/NSpctWW9qctOiaL5MwL7DXZn+BVBLAwQUAAAACACjpG5dWB1IHgABAAC+AQAAEAAAADNELzNkbW9kZWwubW'
    '9kZWx9UFtuwyAQvAriP8F2VKmKgKg/vUCbAziwqal4RLBYTk9fwI3qr/ysFmZnZ2b5aXGWzBCTCV7Qft9RAl4FbfyX'
    'oOfP990rPUnuggZLsjcoqDPWGgcIkZJCPtqxjoLfnT/ah0+CToi3I2NJTeDGtHdGxZDCFfcqOHbQbvT5OirMscgwFS'
    'KwoetfWDdQySOkkKOCJHm4fINCYnRxRgneb1DkqxVK/OjK4y3jVNiaYDTFhoXCd5AmyUskNG1J7WAhi6Al273Vn1rZ'
    'FuqfYCtUJx4Y+9/+EN60ZO4baR6a7fkg6NBYm1m2umRrwtJsUl+ysVpyg+DIiq8HqCv+MNauIH8BUEsBAhQAFAAAAA'
    'gAo6RuXeQU2VqxAAAALAEAABMAAAAAAAAAAAAAAAAAAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAAUAAAACACj'
    'pG5d/ELM9aMAAADxAAAACwAAAAAAAAAAAAAAAADiAAAAX3JlbHMvLnJlbHNQSwECFAAUAAAACACjpG5dWB1IHgABAA'
    'C+AQAAEAAAAAAAAAAAAAAAAACuAQAAM0QvM2Rtb2RlbC5tb2RlbFBLBQYAAAAAAwADALgAAADcAgAAAAA=';

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
