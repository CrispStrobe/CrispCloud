// SPDX-License-Identifier: MPL-2.0

// Deterministic authored native controls. No parser/converter call is used.
// Usage: dart run tool/fidelity/metafile_cases.dart [output-directory]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'metafile_records.dart';

void main(List<String> arguments) {
  if (arguments.length > 1) {
    throw ArgumentError('Expected an optional output directory.');
  }
  final output = Directory(
    arguments.isEmpty ? 'test/fixtures/fidelity/media' : arguments.single,
  )..createSync(recursive: true);
  for (final (extension, bytes) in [
    ('emf', authoredEmfVectors()),
    ('wmf', authoredWmfVectors()),
  ]) {
    final name = '$extension-vectors';
    File('${output.path}/$name.$extension').writeAsBytesSync(bytes);
    File(
      '${output.path}/$name.docx',
    ).writeAsBytesSync(_package(extension, bytes));
    print('$name: ${bytes.length} native vector bytes');
  }
}

Uint8List _package(String extension, Uint8List image) {
  final archive = Archive();
  void binary(String path, Uint8List bytes) {
    archive.addFile(ArchiveFile.bytes(path, bytes)..lastModTime = 315532800);
  }

  void xml(String path, String content) => binary(path, utf8.encode(content));
  const relationships =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  const office =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  xml('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="$extension" ContentType="image/x-$extension"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');
  xml(
    '_rels/.rels',
    '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$relationships"><Relationship Id="rId1" Type="$office/officeDocument" Target="word/document.xml"/></Relationships>''',
  );
  xml(
    'word/_rels/document.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$relationships"><Relationship Id="rId1" Type="$office/image" Target="media/control.$extension"/></Relationships>''',
  );
  xml('word/document.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
xmlns:r="$office" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
<w:body><w:p><w:r><w:t>${extension.toUpperCase()} vector control</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:drawing>
<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5486400" cy="3291840"/>
<wp:docPr id="1" name="Independent raw vector records"/><wp:cNvGraphicFramePr/>
<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>
<pic:nvPicPr><pic:cNvPr id="1" name="control.$extension"/><pic:cNvPicPr/></pic:nvPicPr>
<pic:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="5486400" cy="3291840"/></a:xfrm>
<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
<w:p><w:r><w:t>Solid shapes and signed coordinate mapping.</w:t></w:r></w:p>
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
</w:body></w:document>''');
  binary('word/media/control.$extension', image);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
