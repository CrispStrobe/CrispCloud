import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _types = {
  'docm': 'application/vnd.ms-word.document.macroEnabled.main+xml',
  'dotm': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
  'dotx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml',
};
const _rels = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _office =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';
const _vba =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _package(Map<String, Uint8List> parts) {
  final zip = ZipWriter();
  for (final part in parts.entries) {
    zip.addFile(part.key, part.value);
  }
  return zip.close();
}

Map<String, Uint8List> _parts(Uint8List bytes) {
  final zip = ZipReader.fromBytes(bytes);
  return {for (final name in zip.fileNames) name: zip.read(name)};
}

// Authored minimal OPC package; expected MIME values are fixed independently of
// the guard. No host, Flutter controller or application archive adapter is used.
Map<String, Uint8List> _fixtureParts(
  String extension, {
  String main = 'word/document.xml',
}) {
  final macro = extension != 'dotx';
  return {
    '[Content_Types].xml': _utf8('''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="bin" ContentType="application/octet-stream"/>
  <Override PartName="/$main" ContentType="${_types[extension]}"/>
  ${macro ? '<Override PartName="/word/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject"/>' : ''}
</Types>'''),
    '_rels/.rels': _utf8('''
<Relationships xmlns="$_rels">
  <Relationship Id="office" Type="$_office" Target="$main"/>
</Relationships>'''),
    main: _utf8('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Template body.</w:t></w:r></w:p><w:sectPr/></w:body>
</w:document>'''),
    if (macro) ...{
      OpcUris.toZipName(OpcUris.relationshipsUriFor('/$main')): _utf8('''
<Relationships xmlns="$_rels">
  <Relationship Id="macro" Type="$_vba" Target="${OpcUris.relativize('/$main', '/word/vbaProject.bin')}"/>
</Relationships>'''),
      'word/vbaProject.bin': Uint8List.fromList([0xd0, 0xcf, 0, 255, 67, 7]),
      'word/vbaProjectSignature.bin': Uint8List.fromList([9, 8, 7, 6]),
      'word/vbaData.xml': _utf8('<vba opaque="true"/>'),
      'word/_rels/vbaProject.bin.rels': _utf8('''
<Relationships xmlns="$_rels">
  <Relationship Id="signature" Type="${_vba}Signature" Target="vbaProjectSignature.bin"/>
</Relationships>'''),
    },
  };
}

Matcher _message(String expected) => throwsA(
  isA<FormatException>().having((error) => error.message, 'message', expected),
);

void main() {
  for (final extension in _types.keys) {
    for (final main in [
      'word/document.xml',
      'content/manuscript.xml',
      'content/manuscript%20draft.xml',
    ]) {
      test(
        '$extension retains native main part and opaque bytes over three edits: $main',
        () async {
          final originalParts = _fixtureParts(extension, main: main);
          var bytes = _package(originalParts);
          final guard = (await WordPackagePreservation.capture(
            bytes,
            'template.${extension.toUpperCase()}',
          ))!;
          for (var cycle = 1; cycle <= 3; cycle++) {
            final document = WordDeserializer().readBytes(bytes);
            document.paragraphs.first.inlines.whereType<WmlRun>().first.text =
                'Edited cycle $cycle';
            bytes = await OfficeIsolateSave.word(document);
            await guard.validateSaved(bytes);
            final after = _parts(bytes);
            final types = ContentTypes.parse(
              utf8.decode(after['[Content_Types].xml']!),
            );
            expect(types.contentTypeFor('/$main'), _types[extension]);
            final rootRels = RelationshipCollection.parse(
              utf8.decode(after['_rels/.rels']!),
              '/',
            );
            expect(
              rootRels.resolve(
                rootRels.items.singleWhere((rel) => rel.id == 'office'),
              ),
              '/$main',
            );
            expect(utf8.decode(after[main]!), contains('Edited cycle $cycle'));
            if (main != 'word/document.xml') {
              expect(after, isNot(contains('word/document.xml')));
            }
            if (extension != 'dotx') {
              for (final part in [
                'word/vbaProject.bin',
                'word/vbaProjectSignature.bin',
                'word/vbaData.xml',
              ]) {
                expect(
                  after[part],
                  orderedEquals(originalParts[part]!),
                  reason: part,
                );
              }
              final owner = OpcUris.toZipName(
                OpcUris.relationshipsUriFor('/$main'),
              );
              final relationships = RelationshipCollection.parse(
                utf8.decode(after[owner]!),
                '/$main',
              );
              final macro = relationships.items.singleWhere(
                (rel) => rel.id == 'macro',
              );
              expect(macro.type, _vba);
              expect(relationships.resolve(macro), '/word/vbaProject.bin');
              final signatures = RelationshipCollection.parse(
                utf8.decode(after['word/_rels/vbaProject.bin.rels']!),
                '/word/vbaProject.bin',
              );
              expect(signatures.items.single.target, 'vbaProjectSignature.bin');
            }
          }
        },
      );
    }
  }

  test(
    'unsupported extensions do not inspect or execute package contents',
    () async {
      expect(
        await WordPackagePreservation.capture(Uint8List(0), 'document.doc'),
        isNull,
      );
    },
  );

  test('filename type mismatch has the same precise public error', () async {
    await expectLater(
      WordPackagePreservation.capture(
        _package(_fixtureParts('docm')),
        'template.dotm',
      ),
      _message(
        'The Word package type does not match its filename. Open it in Word and save with the correct extension.',
      ),
    );
  });

  for (final change in [
    'mime',
    'missing',
    'mutated',
    'binary-mime',
    'relationship',
    'signature-relationship',
  ]) {
    test('rejects $change loss before a host replaces its original', () async {
      final parts = _fixtureParts('dotm');
      final original = _package(parts);
      final guard = (await WordPackagePreservation.capture(
        original,
        'template.dotm',
      ))!;
      switch (change) {
        case 'mime':
          parts['[Content_Types].xml'] = _utf8(
            utf8
                .decode(parts['[Content_Types].xml']!)
                .replaceAll(_types['dotm']!, _types['docm']!),
          );
        case 'missing':
          parts.remove('word/vbaProject.bin');
        case 'mutated':
          parts['word/vbaProject.bin'] = Uint8List.fromList([1]);
        case 'binary-mime':
          parts['[Content_Types].xml'] = _utf8(
            utf8
                .decode(parts['[Content_Types].xml']!)
                .replaceAll(
                  'application/vnd.ms-office.vbaProject',
                  'application/octet-stream',
                ),
          );
        case 'relationship':
          parts['word/_rels/document.xml.rels'] = _utf8(
            '<Relationships xmlns="$_rels"/>',
          );
        case 'signature-relationship':
          parts.remove('word/_rels/vbaProject.bin.rels');
      }
      await expectLater(
        guard.validateSaved(_package(parts)),
        throwsFormatException,
      );
      // The guard only reads; even rejection cannot alter the captured original.
      expect(
        _parts(original)['word/vbaProject.bin'],
        orderedEquals([0xd0, 0xcf, 0, 255, 67, 7]),
      );
    });
  }

  test('package signatures are rejected before editing', () async {
    final parts = _fixtureParts('dotm')
      ..['_xmlsignatures/sig1.xml'] = _utf8('<Signature/>');
    await expectLater(
      WordPackagePreservation.capture(_package(parts), 'signed.dotm'),
      _message(
        'This Word package is digitally signed. Save an unsigned copy in Word before editing it here.',
      ),
    );
  });

  for (final opaque in [
    'word/embeddings/object1.bin',
    'customUI/customUI.xml',
  ]) {
    test(
      'relationships to an opaque part remain protected without VBA names: $opaque',
      () async {
        final parts = _fixtureParts('dotx');
        parts[opaque] = _utf8('<opaque/>');
        parts['word/_rels/document.xml.rels'] = _utf8('''
<Relationships xmlns="$_rels">
  <Relationship Id="opaque" Type="urn:fixture:opaque" Target="${OpcUris.relativize('/word/document.xml', '/$opaque')}"/>
</Relationships>''');
        final guard = (await WordPackagePreservation.capture(
          _package(parts),
          'template.dotx',
        ))!;
        parts.remove('word/_rels/document.xml.rels');
        await expectLater(
          guard.validateSaved(_package(parts)),
          _message(
            'Saving would remove a preserved Word relationship. The original was not changed.',
          ),
        );
      },
    );
  }

  test(
    'outgoing relationships owned by a non-VBA binary part are protected',
    () async {
      final parts = _fixtureParts('dotx')
        ..['word/embeddings/object1.bin'] = Uint8List.fromList([1, 2, 3])
        ..['word/embeddings/_rels/object1.bin.rels'] = _utf8('''
<Relationships xmlns="$_rels"><Relationship Id="metadata" Type="urn:fixture:metadata" Target="details.xml"/></Relationships>''')
        ..['word/embeddings/details.xml'] = _utf8('<details/>');
      final guard = (await WordPackagePreservation.capture(
        _package(parts),
        'template.dotx',
      ))!;
      parts.remove('word/embeddings/_rels/object1.bin.rels');
      await expectLater(
        guard.validateSaved(_package(parts)),
        throwsFormatException,
      );
    },
  );

  test(
    'root relationships select the native main part, including strict types',
    () async {
      final parts = _fixtureParts('dotx', main: 'content/manuscript.xml');
      parts['_rels/.rels'] = _utf8(
        utf8
            .decode(parts['_rels/.rels']!)
            .replaceAll(
              _office,
              'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument',
            ),
      );
      final bytes = _package(parts);
      final guard = (await WordPackagePreservation.capture(
        bytes,
        'template.dotx',
      ))!;
      await guard.validateSaved(bytes);
    },
  );

  for (final target in [
    '../outside.xml',
    '%2e%2e/outside.xml',
    'https://example.test/main.xml',
    'word/document.xml?x=1',
  ]) {
    test('unsafe native main target is rejected: $target', () async {
      final parts = _fixtureParts('dotx');
      parts['_rels/.rels'] = _utf8(
        '<Relationships xmlns="$_rels"><Relationship Id="office" Type="$_office" Target="$target"/></Relationships>',
      );
      await expectLater(
        WordPackagePreservation.capture(_package(parts), 'template.dotx'),
        _message('Invalid Word main document relationship.'),
      );
    });
  }

  test(
    'declared part, cumulative, file and member budgets reject before expansion',
    () async {
      final parts = _fixtureParts('dotm');
      final bytes = _package(parts);
      for (final limits in [
        const WordPackagePreservationLimits(maxPartBytes: 1),
        const WordPackagePreservationLimits(maxTotalReadBytes: 700),
        WordPackagePreservationLimits(maxFileBytes: bytes.length - 1),
        const WordPackagePreservationLimits(maxEntries: 1),
      ]) {
        await expectLater(
          WordPackagePreservation.capture(
            bytes,
            'template.dotm',
            limits: limits,
          ),
          _message('Word package exceeds the safe editing limit.'),
        );
      }
    },
  );

  test(
    'actual inflated bytes cannot bypass a forged small size declaration',
    () async {
      final parts = _fixtureParts('dotm')
        ..['word/vbaProject.bin'] = Uint8List(20000);
      final bytes = _package(parts);
      final view = ByteData.sublistView(bytes);
      var offset = view.getUint32(bytes.length - 6, Endian.little);
      while (view.getUint32(offset, Endian.little) == zipCentralSig) {
        final nameLength = view.getUint16(offset + 28, Endian.little);
        final name = utf8.decode(
          bytes.sublist(offset + 46, offset + 46 + nameLength),
        );
        if (name == 'word/vbaProject.bin') {
          view.setUint32(offset + 24, 1, Endian.little);
          break;
        }
        offset +=
            46 +
            nameLength +
            view.getUint16(offset + 30, Endian.little) +
            view.getUint16(offset + 32, Endian.little);
      }
      await expectLater(
        WordPackagePreservation.capture(
          bytes,
          'template.dotm',
          limits: const WordPackagePreservationLimits(maxPartBytes: 2048),
        ),
        _message('Word package exceeds the safe editing limit.'),
      );
    },
  );

  test(
    'duplicate ZIP members are not silently collapsed by the package reader',
    () async {
      final writer = ZipWriter();
      for (final part in _fixtureParts('dotm').entries) {
        writer.addFile(part.key, part.value);
      }
      writer.addFile('word/vbaProject.bin', [1, 2, 3]);
      await expectLater(
        WordPackagePreservation.capture(writer.close(), 'template.dotm'),
        _message('Duplicate Word package part.'),
      );
    },
  );

  for (final badXml in [
    '<Types',
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    '<wrong/>',
  ]) {
    test(
      'malformed content-type metadata cannot look like a valid package: $badXml',
      () async {
        final parts = _fixtureParts('dotm')
          ..['[Content_Types].xml'] = _utf8(badXml);
        await expectLater(
          WordPackagePreservation.capture(_package(parts), 'template.dotm'),
          throwsFormatException,
        );
      },
    );
  }
}
