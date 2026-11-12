import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/word_conversion_inspection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show CfbfWriter;

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _strictW = 'http://purl.oclc.org/ooxml/wordprocessingml/main';
const _rels = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _office =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _strictOffice = 'http://purl.oclc.org/ooxml/officeDocument/relationships';
const _types = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _wordPartType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml';
const _mainType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

String _relationships(String children) =>
    '<Relationships xmlns="$_rels">$children</Relationships>';

Map<String, Uint8List> _parts({
  String mainType = _mainType,
  String mainPart = 'word/document.xml',
  String namespace = _w,
  String relationshipNamespace = _office,
  String? body,
  Map<String, String> overrides = const {},
}) => {
  '[Content_Types].xml': _bytes(
    '<Types xmlns="$_types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Default Extension="bin" ContentType="application/octet-stream"/>'
    '<Override PartName="/$mainPart" ContentType="$mainType"/>'
    '${overrides.entries.map((e) => '<Override PartName="/${e.key}" ContentType="${e.value}"/>').join()}'
    '</Types>',
  ),
  '_rels/.rels': _bytes(
    _relationships(
      '<Relationship Id="main" Type="$_office/officeDocument" Target="$mainPart"/>',
    ),
  ),
  mainPart: _bytes(
    '<w:document xmlns:w="$namespace" xmlns:r="$relationshipNamespace">'
    '<w:body>${body ?? '<w:p><w:r><w:t>Example</w:t></w:r></w:p><w:sectPr/>'}</w:body>'
    '</w:document>',
  ),
};

const _allSourceFeatures = LegacyWordSourceInspection(
  hasObjects: true,
  hasHeaders: true,
  hasFootnotes: true,
  hasEndnotes: true,
  hasComments: true,
);
const _allFeatureLosses = [
  WordConversionLoss.objectsMissing,
  WordConversionLoss.headersMissing,
  WordConversionLoss.footnotesMissing,
  WordConversionLoss.endnotesMissing,
  WordConversionLoss.commentsMissing,
];
const _storyKinds = ['header', 'footer', 'footnotes', 'endnotes', 'comments'];

// Deliberately non-default main/relationship names and relative targets.
Map<String, Uint8List> _reachableParts({
  String namespace = _w,
  String relationshipNamespace = _office,
  String mode = '',
  String? relationshipKind,
  String? body,
}) {
  final parts = _parts(
    mainPart: 'content/body/main.xml',
    namespace: namespace,
    relationshipNamespace: relationshipNamespace,
    body:
        body ??
        '<w:p><w:r>'
            '<w:footnoteReference w:id="1"/><w:endnoteReference w:id="1"/>'
            '<w:commentReference w:id="1"/>'
            '<w:object><w:objectEmbed r:id="object"/></w:object>'
            '</w:r></w:p><w:sectPr>'
            '<w:headerReference w:type="default" r:id="header"/>'
            '<w:footerReference w:type="default" r:id="footer"/>'
            '</w:sectPr>',
    overrides: {
      for (final kind in _storyKinds)
        'content/shared/$kind.xml': '$_wordPartType.$kind+xml',
      'content/embeddings/object.bin':
          'application/vnd.openxmlformats-officedocument.oleObject',
    },
  );
  parts['_rels/.rels'] = _bytes(
    _relationships(
      '<Relationship Id="main" Type="$relationshipNamespace/officeDocument" Target="content/body/main.xml"/>',
    ),
  );
  parts['content/body/_rels/main.xml.rels'] = _bytes(
    _relationships(
      [
        for (final kind in _storyKinds)
          '<Relationship Id="$kind" Type="$relationshipNamespace/${relationshipKind ?? kind}" Target="../shared/$kind.xml" $mode/>',
        '<Relationship Id="object" Type="$relationshipNamespace/${relationshipKind ?? 'oleObject'}" Target="../embeddings/object.bin" $mode/>',
      ].join(),
    ),
  );
  for (final entry in {
    'header': '<w:hdr xmlns:w="$namespace"><w:p/></w:hdr>',
    'footer': '<w:ftr xmlns:w="$namespace"><w:p/></w:ftr>',
    'footnotes':
        '<w:footnotes xmlns:w="$namespace"><w:footnote w:id="1"><w:p/></w:footnote></w:footnotes>',
    'endnotes':
        '<w:endnotes xmlns:w="$namespace"><w:endnote w:id="1"><w:p/></w:endnote></w:endnotes>',
    'comments':
        '<w:comments xmlns:w="$namespace"><w:comment w:id="1"><w:p/></w:comment></w:comments>',
  }.entries) {
    parts['content/shared/${entry.key}.xml'] = _bytes(entry.value);
  }
  parts['content/embeddings/object.bin'] = Uint8List.fromList([1, 2]);
  return parts;
}

Uint8List _zip(Map<String, Uint8List> parts) {
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, part.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Independent FIB fixture. FibRgLw97 indices are from [MS-DOC] 2.5.4:
/// https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/37713d3c-a0c8-40f5-821f-bc9622c7de48
Uint8List _source({
  Map<int, int> stories = const {},
  Map<String, List<int>> streams = const {},
  int flags = 0x0200,
  String wordPath = 'WordDocument',
  bool headerSeparatorsOnly = false,
}) {
  final word = Uint8List(512);
  final fib = ByteData.sublistView(word);
  fib.setUint16(0, 0xa5ec, Endian.little);
  fib.setUint16(2, 0x00c1, Endian.little);
  fib.setUint16(10, flags, Endian.little);
  fib.setUint16(32, 14, Endian.little);
  fib.setUint16(62, 22, Endian.little);
  fib.setUint16(152, 93, Endian.little);
  fib.setUint32(64, word.length, Endian.little);
  for (final story in stories.entries) {
    fib.setInt32(64 + story.key * 4, story.value, Endian.little);
  }
  final writer = CfbfWriter()..addStream(wordPath, word);
  final headerCount = stories[5] ?? 0;
  if (headerCount > 0) {
    // [MS-DOC] 2.3.3: first six PlcfHdd stories are separators, not headers.
    // FibRgFcLcb97 pair 11 locates this CP-only array in the selected table.
    // The second-last CP is ccpHdd - 1; the last CP is undefined/ignored.
    // [MS-DOC] 2.8.22: 8f336b7e-66cb-4346-9fd4-88ede9a4a9db.
    final positions = headerSeparatorsOnly
        ? [
            0,
            headerCount - 1,
            headerCount - 1,
            headerCount - 1,
            headerCount - 1,
            headerCount - 1,
            headerCount - 1,
            0,
          ]
        : [0, 0, 0, 0, 0, 0, 0, headerCount - 1, 0];
    final table = ByteData(positions.length * 4);
    for (var i = 0; i < positions.length; i++) {
      table.setInt32(i * 4, positions[i], Endian.little);
    }
    fib.setUint32(154 + 11 * 8, 0, Endian.little);
    fib.setUint32(158 + 11 * 8, table.lengthInBytes, Endian.little);
    // CfbfWriter snapshots input bytes, so replace the FIB after adding offsets.
    writer.addStream(wordPath, word);
    writer.addStream(
      flags & 0x0200 != 0 ? '1Table' : '0Table',
      table.buffer.asUint8List(),
    );
  }
  for (final stream in streams.entries) {
    writer.addStream(stream.key, stream.value);
  }
  return writer.build();
}

Uint8List _vba(Map<String, List<int>> streams) {
  final writer = CfbfWriter();
  for (final stream in streams.entries) {
    writer.addStream(stream.key, stream.value);
  }
  return writer.build();
}

Map<String, Uint8List> _macroParts(Uint8List project) {
  final parts = _parts(
    mainType: _macroType,
    overrides: {'word/vbaProject.bin': 'application/vnd.ms-office.vbaProject'},
  );
  parts['word/vbaProject.bin'] = project;
  parts['word/_rels/document.xml.rels'] = _bytes(
    _relationships(
      '<Relationship Id="vba" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/>',
    ),
  );
  return parts;
}

Future<WordConversionInspection> _inspect(
  Map<String, Uint8List> parts, {
  String extension = 'docx',
  LegacyWordSourceInspection source = const LegacyWordSourceInspection(),
}) => inspectConvertedWord(_zip(parts), extension: extension, source: source);

Matcher _issue(WordConversionInspectionIssue issue) => throwsA(
  isA<WordConversionInspectionException>().having(
    (e) => e.issue,
    'issue',
    issue,
  ),
);

Uint8List _patchCentral(
  Uint8List original,
  String name, {
  int? size,
  bool corruptCrc = false,
}) {
  final bytes = Uint8List.fromList(original);
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset + 46 <= bytes.length; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    final length = data.getUint16(offset + 28, Endian.little);
    if (offset + 46 + length > bytes.length) continue;
    if (utf8.decode(bytes.sublist(offset + 46, offset + 46 + length)) != name) {
      continue;
    }
    if (size != null) data.setUint32(offset + 24, size, Endian.little);
    if (corruptCrc) {
      final crc = data.getUint32(offset + 16, Endian.little);
      data.setUint32(offset + 16, crc ^ 0x80000000, Endian.little);
    }
    return bytes;
  }
  throw StateError('Fixture central directory member was not found');
}

void main() {
  group('legacy source evidence', () {
    test('reads the four distinct signed FIB story counts', () {
      for (final index in [4, 5, 7, 8]) {
        final inspected = inspectLegacyWordSource(_source(stories: {index: 3}));
        expect(inspected.hasFootnotes, index == 4);
        expect(inspected.hasHeaders, index == 5);
        expect(inspected.hasComments, index == 7);
        expect(inspected.hasEndnotes, index == 8);
      }
      final unrelated = inspectLegacyWordSource(
        _source(stories: {3: 12, 9: 5, 10: 2}),
      );
      expect(unrelated.hasHeaders, isFalse);
      expect(unrelated.hasFootnotes, isFalse);
      expect(unrelated.hasEndnotes, isFalse);
      expect(unrelated.hasComments, isFalse);
    });

    test(
      'footnote/endnote separator stories do not imply a header or footer',
      () {
        final source = inspectLegacyWordSource(
          _source(stories: {4: 12, 5: 3}, headerSeparatorsOnly: true),
        );
        expect(source.hasFootnotes, isTrue);
        expect(source.hasHeaders, isFalse);
      },
    );

    test(
      'rejects negative story counts and encrypted or nested-only source',
      () {
        expect(
          () => inspectLegacyWordSource(_source(stories: {4: -1})),
          _issue(WordConversionInspectionIssue.invalidInput),
        );
        for (final flag in [0x0100, 0x8000]) {
          expect(
            () => inspectLegacyWordSource(_source(flags: flag)),
            _issue(WordConversionInspectionIssue.encrypted),
          );
        }
        expect(
          () => inspectLegacyWordSource(
            _source(wordPath: 'Embedded/WordDocument'),
          ),
          _issue(WordConversionInspectionIssue.invalidInput),
        );
      },
    );

    test('limits VBA evidence to the document macro root', () {
      final nested = inspectLegacyWordSource(
        _source(
          streams: {
            'ObjectPool/Embedded/Macros/VBA/Module1': [9],
            'ObjectPool/Embedded/Signature': [8],
          },
        ),
      );
      expect(nested.hasVba, isFalse);
      expect(nested.vbaStreams, isEmpty);
      expect(nested.hasObjects, isTrue);
      final namedStream = inspectLegacyWordSource(
        _source(
          streams: {
            'Macros': [7],
          },
        ),
      );
      expect(namedStream.hasVba, isFalse);
      final real = inspectLegacyWordSource(
        _source(
          streams: {
            'Macros/PROJECT': [1, 2],
            'Macros/VBA/Module1': [3, 4],
            'ObjectPool/Embedded/VBA/Module1': [9],
          },
        ),
      );
      expect(real.hasVba, isTrue);
      expect(real.vbaStreams.keys, unorderedEquals(['PROJECT', 'VBA/MODULE1']));
    });

    test('supports the alternate root VBA project layout', () {
      final legacy = inspectLegacyWordSource(
        _source(
          streams: {
            '_VBA_PROJECT_CUR/PROJECT': [1],
            '_VBA_PROJECT_CUR/VBA/Module1': [2],
          },
        ),
      );
      final direct = inspectLegacyWordSource(
        _source(
          streams: {
            'PROJECT': [1],
            'VBA/Module1': [2],
          },
        ),
      );
      expect(legacy.hasVba, isTrue);
      expect(direct.vbaStreams, legacy.vbaStreams);
    });

    test('bounds even a flat macro storage stream count', () {
      final streams = <String, List<int>>{
        for (var i = 0; i < 4097; i++) 'Macros/VBA/Module$i': const [],
      };
      expect(
        () => inspectLegacyWordSource(_source(streams: streams)),
        _issue(WordConversionInspectionIssue.tooLarge),
      );
    });
  });

  group('converted OPC validation', () {
    test('accepts genuine transitional and strict main parts', () async {
      final normal = await _inspect(_parts());
      expect(normal.counts['paragraphs'], 1);
      expect(normal.counts['sections'], 1);
      expect(normal.losses, isEmpty);
      final strict = _parts(namespace: _strictW);
      strict['_rels/.rels'] = _bytes(
        _relationships(
          '<Relationship Id="main" Type="http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument" Target="word/document.xml"/>',
        ),
      );
      expect((await _inspect(strict)).counts['paragraphs'], 1);
    });

    test(
      'requires the exact main document relationship and a Word body',
      () async {
        final fake = _parts();
        fake['_rels/.rels'] = _bytes(
          _relationships(
            '<Relationship Id="main" Type="https://example.invalid/officeDocument" Target="word/document.xml"/>',
          ),
        );
        await expectLater(
          _inspect(fake),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
        final wrongBody = _parts();
        wrongBody['word/document.xml'] = _bytes(
          '<w:document xmlns:w="$_w"><body/></w:document>',
        );
        await expectLater(
          _inspect(wrongBody),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
      },
    );

    test(
      'rejects templates, spreadsheet packages, and extension/type mismatch',
      () async {
        for (final type in [
          'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml',
          'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
          _macroType,
        ]) {
          await expectLater(
            _inspect(_parts(mainType: type)),
            _issue(WordConversionInspectionIssue.invalidOutput),
          );
        }
        await expectLater(
          _inspect(_parts(), extension: 'docm'),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
        await expectLater(
          _inspect(_parts(), extension: 'dotx'),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
      },
    );

    test('rejects lookalike content-type and relationship element namespaces', () async {
      final types = _parts();
      types['[Content_Types].xml'] = _bytes(
        utf8
            .decode(types['[Content_Types].xml']!)
            .replaceAll('<Override ', '<x:Override xmlns:x="urn:unrelated" '),
      );
      await expectLater(
        _inspect(types),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
      final relationships = _parts();
      relationships['_rels/.rels'] = _bytes(
        _relationships(
          '<x:Relationship xmlns:x="urn:unrelated" Id="main" Type="$_office/officeDocument" Target="word/document.xml"/>',
        ),
      );
      await expectLater(
        _inspect(relationships),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
    });

    test(
      'rejects dangling, escaping and network internal relationships',
      () async {
        for (final target in [
          'missing.png',
          '../../outside.bin',
          '%2e%2e/%2e%2e/outside.bin',
          'https://example.invalid/payload',
          '//example.invalid/payload',
          '..%5coutside.bin',
          'document.xml?query',
        ]) {
          final parts = _parts();
          parts['word/_rels/document.xml.rels'] = _bytes(
            _relationships(
              '<Relationship Id="bad" Type="$_office/image" Target="$target"/>',
            ),
          );
          await expectLater(
            _inspect(parts),
            _issue(WordConversionInspectionIssue.invalidOutput),
            reason: target,
          );
        }
      },
    );

    test('retains external links without fetching their targets', () async {
      final parts = _parts();
      parts['word/_rels/document.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="link" Type="$_office/hyperlink" Target="https://no-such-host.invalid/private" TargetMode="External"/>',
        ),
      );
      expect((await _inspect(parts)).counts['paragraphs'], 1);
    });

    test('rejects duplicate relationship ids and orphan relationship owners', () async {
      final duplicate = _parts();
      duplicate['word/_rels/document.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="same" Type="$_office/hyperlink" Target="https://one.invalid" TargetMode="External"/>'
          '<Relationship Id="same" Type="$_office/hyperlink" Target="https://two.invalid" TargetMode="External"/>',
        ),
      );
      await expectLater(
        _inspect(duplicate),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
      final orphan = _parts();
      orphan['word/_rels/not-present.xml.rels'] = _bytes(_relationships(''));
      await expectLater(
        _inspect(orphan),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
    });

    test(
      'rejects escaped archive paths and verifies CRC of unused parts',
      () async {
        final escaped = _parts()..['../outside.bin'] = Uint8List.fromList([1]);
        await expectLater(
          _inspect(escaped),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
        final parts = _parts()
          ..['word/unused.bin'] = Uint8List.fromList([1, 2, 3]);
        final corrupt = _patchCentral(
          _zip(parts),
          'word/unused.bin',
          corruptCrc: true,
        );
        await expectLater(
          inspectConvertedWord(
            corrupt,
            extension: 'docx',
            source: const LegacyWordSourceInspection(),
          ),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
      },
    );

    test('rejects DTDs and excessive XML nesting', () async {
      final dtd = _parts();
      dtd['word/document.xml'] = _bytes(
        '<!DOCTYPE document [<!ENTITY secret "value">]><w:document xmlns:w="$_w"><w:body><w:p>&secret;</w:p></w:body></w:document>',
      );
      await expectLater(
        _inspect(dtd),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
      final deep = _parts(
        body:
            '${List.filled(129, '<w:sdt>').join()}${List.filled(129, '</w:sdt>').join()}',
      );
      await expectLater(
        _inspect(deep),
        _issue(WordConversionInspectionIssue.tooLarge),
      );
    });

    test('rejects oversized XML and aggregate advertised expansion', () async {
      final hugeXml = _parts();
      hugeXml['word/document.xml'] = Uint8List(16 * 1024 * 1024 + 1);
      await expectLater(
        _inspect(hugeXml),
        _issue(WordConversionInspectionIssue.tooLarge),
      );
      final parts = _parts();
      for (var i = 0; i < 3; i++) {
        parts['word/payload$i.bin'] = Uint8List.fromList([i]);
      }
      var bytes = _zip(parts);
      for (var i = 0; i < 3; i++) {
        bytes = _patchCentral(
          bytes,
          'word/payload$i.bin',
          size: 50 * 1024 * 1024,
        );
      }
      await expectLater(
        inspectConvertedWord(
          bytes,
          extension: 'docx',
          source: const LegacyWordSourceInspection(),
        ),
        _issue(WordConversionInspectionIssue.tooLarge),
      );
    });
  });

  group('reachable feature evidence', () {
    test(
      'orphan parts retain inventory counts without hiding losses',
      () async {
        final parts = _reachableParts()
          ..remove('content/body/_rels/main.xml.rels');
        final result = await _inspect(parts, source: _allSourceFeatures);
        for (final key in [
          'headers',
          'footers',
          'footnotes',
          'endnotes',
          'comments',
          'objects',
        ]) {
          expect(result.counts[key], 1, reason: key);
        }
        expect(result.losses, unorderedEquals(_allFeatureLosses));
      },
    );

    test(
      'resolves both relationship namespaces from the actual main part',
      () async {
        for (final (namespace, relationships) in [
          (_w, _office),
          (_strictW, _strictOffice),
        ]) {
          final result = await _inspect(
            _reachableParts(
              namespace: namespace,
              relationshipNamespace: relationships,
              mode: 'TargetMode="Internal"',
            ),
            source: _allSourceFeatures,
          );
          expect(result.losses, isEmpty, reason: relationships);
        }
      },
    );

    test('unused relationships cannot hide missing document anchors', () async {
      final result = await _inspect(
        _reachableParts(body: '<w:p/><w:sectPr/>'),
        source: _allSourceFeatures,
      );
      expect(result.losses, unorderedEquals(_allFeatureLosses));
      for (final key in [
        'headers',
        'footers',
        'footnotes',
        'endnotes',
        'comments',
        'objects',
      ]) {
        expect(result.counts[key], 1, reason: 'inventory $key');
      }
    });

    test('header/footer anchors require the matching relationship id', () async {
      for (final attributes in [
        'r:id="missing"',
        'id="header"',
        'x:id="header" xmlns:x="urn:unrelated"',
      ]) {
        final parts = _reachableParts(
          body:
              '<w:p/><w:sectPr><w:headerReference w:type="default" $attributes/></w:sectPr>',
        );
        expect(
          (await _inspect(
            parts,
            source: const LegacyWordSourceInspection(hasHeaders: true),
          )).losses,
          [WordConversionLoss.headersMissing],
          reason: attributes,
        );
      }
    });

    test(
      'prior section properties do not supply current header anchors',
      () async {
        final parts = _reachableParts(
          body:
              '<w:p/><w:sectPr><w:sectPrChange w:id="0" w:author="A">'
              '<w:sectPr><w:headerReference w:type="default" r:id="header"/>'
              '<w:footerReference w:type="default" r:id="footer"/>'
              '</w:sectPr></w:sectPrChange></w:sectPr>',
        );
        expect(
          (await _inspect(
            parts,
            source: const LegacyWordSourceInspection(hasHeaders: true),
          )).losses,
          [WordConversionLoss.headersMissing],
        );
      },
    );

    test('notes and comments require matching namespaced decimal ids', () async {
      for (final attributes in [
        'w:id="2"',
        'w:id="0x1"',
        'id="1"',
        'x:id="1" xmlns:x="urn:unrelated"',
      ]) {
        final parts = _reachableParts(
          body:
              '<w:p><w:r><w:footnoteReference $attributes/>'
              '<w:endnoteReference $attributes/><w:commentReference $attributes/>'
              '</w:r></w:p><w:sectPr/>',
        );
        expect(
          (await _inspect(
            parts,
            source: const LegacyWordSourceInspection(
              hasFootnotes: true,
              hasEndnotes: true,
              hasComments: true,
            ),
          )).losses,
          unorderedEquals([
            WordConversionLoss.footnotesMissing,
            WordConversionLoss.endnotesMissing,
            WordConversionLoss.commentsMissing,
          ]),
          reason: attributes,
        );
      }
      final canonical = _reachableParts(
        body:
            '<w:p><w:r><w:footnoteReference w:id="+001"/>'
            '<w:endnoteReference w:id="01"/><w:commentReference w:id="0001"/>'
            '</w:r></w:p><w:sectPr/>',
      );
      expect(
        (await _inspect(
          canonical,
          source: const LegacyWordSourceInspection(
            hasFootnotes: true,
            hasEndnotes: true,
            hasComments: true,
          ),
        )).losses,
        isEmpty,
      );
    });

    test('range markers and lookalike elements do not attach comments', () async {
      for (final body in [
        '<w:p><w:commentRangeStart w:id="1"/>'
            '<w:r><w:t>Text</w:t></w:r><w:commentRangeEnd w:id="1"/></w:p>',
        '<w:p><w:r><x:commentReference xmlns:x="urn:unrelated" w:id="1"/></w:r></w:p>',
        '<w:p><w:commentReference w:id="1"/></w:p>',
      ]) {
        expect(
          (await _inspect(
            _reachableParts(body: body),
            source: const LegacyWordSourceInspection(hasComments: true),
          )).losses,
          [WordConversionLoss.commentsMissing],
          reason: body,
        );
      }
    });

    test(
      'ambiguous or foreign definition ids cannot prove attachment',
      () async {
        for (final definitions in [
          '<w:comment w:id="1"><w:p/></w:comment>'
              '<w:comment w:id="+01"><w:p/></w:comment>',
          '<w:comment id="1"><w:p/></w:comment>',
          '<w:comment xmlns:x="urn:unrelated" x:id="1"><w:p/></w:comment>',
        ]) {
          final parts = _reachableParts();
          parts['content/shared/comments.xml'] = _bytes(
            '<w:comments xmlns:w="$_w">$definitions</w:comments>',
          );
          expect(
            (await _inspect(
              parts,
              source: const LegacyWordSourceInspection(hasComments: true),
            )).losses,
            [WordConversionLoss.commentsMissing],
          );
        }
      },
    );

    test('recognizes comment references in Office Math runs', () async {
      final parts = _reachableParts(
        body:
            '<w:p><m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">'
            '<m:r><w:commentReference w:id="1"/></m:r></m:oMath></w:p>',
      );
      expect(
        (await _inspect(
          parts,
          source: const LegacyWordSourceInspection(hasComments: true),
        )).losses,
        isEmpty,
      );
    });

    test('rejects competing document note or comment parts', () async {
      for (final kind in ['footnotes', 'endnotes', 'comments']) {
        final parts = _reachableParts();
        parts['content/shared/other.xml'] = parts['content/shared/$kind.xml']!;
        parts['[Content_Types].xml'] = _bytes(
          utf8
              .decode(parts['[Content_Types].xml']!)
              .replaceFirst(
                '</Types>',
                '<Override PartName="/content/shared/other.xml" '
                    'ContentType="$_wordPartType.$kind+xml"/></Types>',
              ),
        );
        const rels = 'content/body/_rels/main.xml.rels';
        parts[rels] = _bytes(
          utf8
              .decode(parts[rels]!)
              .replaceFirst(
                '</Relationships>',
                '<Relationship Id="other" Type="$_office/$kind" '
                    'Target="../shared/other.xml"/></Relationships>',
              ),
        );
        await expectLater(
          _inspect(parts),
          _issue(WordConversionInspectionIssue.invalidOutput),
          reason: kind,
        );
      }
    });

    test('unreferenced notes cannot lend their comments or objects', () async {
      for (final referencedId in ['1', '2']) {
        final parts = _reachableParts(
          body:
              '<w:p><w:r><w:footnoteReference w:id="$referencedId"/></w:r></w:p>',
        );
        parts['content/shared/footnotes.xml'] = _bytes(
          '<w:footnotes xmlns:w="$_w" xmlns:r="$_office">'
          '<w:footnote w:id="1"><w:p/></w:footnote>'
          '<w:footnote w:id="2"><w:p><w:r><w:commentReference w:id="1"/>'
          '<w:object><w:objectEmbed r:id="object"/></w:object>'
          '</w:r></w:p></w:footnote></w:footnotes>',
        );
        parts['content/shared/_rels/footnotes.xml.rels'] = _bytes(
          _relationships(
            '<Relationship Id="object" Type="$_office/oleObject" Target="../embeddings/object.bin"/>',
          ),
        );
        final result = await _inspect(
          parts,
          source: const LegacyWordSourceInspection(
            hasFootnotes: true,
            hasComments: true,
            hasObjects: true,
          ),
        );
        expect(
          result.losses,
          referencedId == '1'
              ? unorderedEquals([
                  WordConversionLoss.objectsMissing,
                  WordConversionLoss.commentsMissing,
                ])
              : isEmpty,
          reason: 'referenced note $referencedId',
        );
      }
    });

    test('only embedded object markup uses its relationship as evidence', () async {
      for (final markup in [
        '<w:drawing r:id="object"/>',
        '<w:object><w:objectEmbed r:id="missing"/></w:object>',
        '<w:object><w:objectEmbed id="object"/></w:object>',
        '<w:object><x:objectEmbed xmlns:x="urn:unrelated" r:id="object"/></w:object>',
        '<w:object><o:OLEObject xmlns:o="urn:schemas-microsoft-com:office:office" Type="Link" r:id="object"/></w:object>',
      ]) {
        final parts = _reachableParts(body: '<w:p><w:r>$markup</w:r></w:p>');
        expect(
          (await _inspect(
            parts,
            source: const LegacyWordSourceInspection(hasObjects: true),
          )).losses,
          [WordConversionLoss.objectsMissing],
          reason: markup,
        );
      }
      final legacy = _reachableParts(
        body:
            '<w:p><w:r><w:object><o:OLEObject '
            'xmlns:o="urn:schemas-microsoft-com:office:office" '
            'Type="Embed" r:id="object"/></w:object></w:r></w:p>',
      );
      expect(
        (await _inspect(
          legacy,
          source: const LegacyWordSourceInspection(hasObjects: true),
        )).losses,
        isEmpty,
      );
    });

    test(
      'external and lookalike relationships cannot prove preservation',
      () async {
        for (final parts in [
          _reachableParts(mode: 'TargetMode="External"'),
          _reachableParts(relationshipKind: 'customXml'),
          _reachableParts(relationshipKind: 'hyperlink'),
        ]) {
          final result = await _inspect(parts, source: _allSourceFeatures);
          expect(result.losses, unorderedEquals(_allFeatureLosses));
        }
        final lookalike = _reachableParts();
        const rels = 'content/body/_rels/main.xml.rels';
        lookalike[rels] = _bytes(
          utf8
              .decode(lookalike[rels]!)
              .replaceAll(_office, 'https://example.invalid'),
        );
        expect(
          (await _inspect(lookalike, source: _allSourceFeatures)).losses,
          unorderedEquals(_allFeatureLosses),
        );
      },
    );

    test('glossary-only stories do not substitute for document stories', () async {
      final parts = _reachableParts();
      parts['content/body/_rels/glossary.xml.rels'] =
          parts['content/body/_rels/main.xml.rels']!;
      parts['content/body/glossary.xml'] = _bytes(
        '<w:glossaryDocument xmlns:w="$_w"><w:docParts/></w:glossaryDocument>',
      );
      parts['content/body/_rels/main.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="glossary" Type="$_office/glossaryDocument" Target="glossary.xml"/>',
        ),
      );
      parts['[Content_Types].xml'] = _bytes(
        utf8
            .decode(parts['[Content_Types].xml']!)
            .replaceFirst(
              '</Types>',
              '<Override PartName="/content/body/glossary.xml" ContentType="$_wordPartType.document.glossary+xml"/></Types>',
            ),
      );
      expect(
        (await _inspect(parts, source: _allSourceFeatures)).losses,
        unorderedEquals(_allFeatureLosses),
      );
    });

    test('objects must belong to main or an attached document story', () async {
      for (final kind in _storyKinds) {
        for (final objectKind in ['oleObject', 'package']) {
          final parts = _reachableParts();
          parts['content/body/_rels/main.xml.rels'] = _bytes(
            _relationships(
              '<Relationship Id="$kind" Type="$_office/$kind" Target="../shared/$kind.xml"/>',
            ),
          );
          parts['content/shared/_rels/$kind.xml.rels'] = _bytes(
            _relationships(
              '<Relationship Id="object" Type="$_office/$objectKind" Target="../embeddings/object.bin"/>',
            ),
          );
          final storyName = 'content/shared/$kind.xml';
          parts[storyName] = _bytes(
            utf8
                .decode(parts[storyName]!)
                .replaceFirst(
                  '<w:p/>',
                  '<w:p><w:r><w:object><w:objectEmbed '
                      'xmlns:r="$_office" r:id="object"/></w:object></w:r></w:p>',
                ),
          );
          const source = LegacyWordSourceInspection(hasObjects: true);
          expect(
            (await _inspect(parts, source: source)).losses,
            isEmpty,
            reason: '$kind/$objectKind',
          );
          parts.remove('content/body/_rels/main.xml.rels');
          expect((await _inspect(parts, source: source)).losses, [
            WordConversionLoss.objectsMissing,
          ], reason: 'disconnected $kind/$objectKind');
        }
      }
    });

    test('object relationships cannot alias structural package parts', () async {
      for (final kind in ['oleObject', 'package']) {
        for (final target in [
          'document.xml',
          'comments.xml',
          'styles.xml',
          '../[Content_Types].xml',
          '_rels/document.xml.rels',
        ]) {
          final parts = _parts(
            overrides: {
              'word/comments.xml': '$_wordPartType.comments+xml',
              'word/styles.xml': '$_wordPartType.styles+xml',
            },
          );
          parts['word/comments.xml'] = _bytes(
            '<w:comments xmlns:w="$_w"><w:comment w:id="1"><w:p/></w:comment></w:comments>',
          );
          parts['word/styles.xml'] = _bytes('<w:styles xmlns:w="$_w"/>');
          parts['word/_rels/document.xml.rels'] = _bytes(
            _relationships(
              '<Relationship Id="object" Type="$_office/$kind" Target="$target"/>',
            ),
          );
          final result = await _inspect(
            parts,
            source: const LegacyWordSourceInspection(hasObjects: true),
          );
          expect(result.counts['objects'], 0);
          expect(result.losses, [
            WordConversionLoss.objectsMissing,
          ], reason: '$kind/$target');
        }
      }
    });

    test('OLE needs its content type while packages may use registered types', () async {
      final image = _parts();
      image['word/image.png'] = Uint8List.fromList([137, 80, 78, 71]);
      image['word/_rels/document.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="object" Type="$_office/oleObject" Target="image.png"/>',
        ),
      );
      expect(
        (await _inspect(
          image,
          source: const LegacyWordSourceInspection(hasObjects: true),
        )).losses,
        [WordConversionLoss.objectsMissing],
      );
      for (final type in [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.example.embedded-package',
      ]) {
        final parts = _reachableParts();
        parts['content/body/_rels/main.xml.rels'] = _bytes(
          _relationships(
            '<Relationship Id="object" Type="$_office/package" Target="../embeddings/object.bin"/>',
          ),
        );
        parts['[Content_Types].xml'] = _bytes(
          utf8
              .decode(parts['[Content_Types].xml']!)
              .replaceFirst(
                'application/vnd.openxmlformats-officedocument.oleObject',
                type,
              ),
        );
        expect(
          (await _inspect(
            parts,
            source: const LegacyWordSourceInspection(hasObjects: true),
          )).losses,
          isEmpty,
          reason: type,
        );
      }
    });

    test('attached separator-only note parts do not prove note preservation', () async {
      final parts = _reachableParts();
      for (final kind in ['footnote', 'endnote']) {
        parts['content/shared/${kind}s.xml'] = _bytes(
          '<w:${kind}s xmlns:w="$_w"><w:$kind w:type="separator" w:id="-1"><w:p/></w:$kind></w:${kind}s>',
        );
      }
      expect(
        (await _inspect(parts, source: _allSourceFeatures)).losses,
        unorderedEquals([
          WordConversionLoss.footnotesMissing,
          WordConversionLoss.endnotesMissing,
        ]),
      );
    });

    test('foreign type attributes do not turn ordinary notes into separators', () async {
      final parts = _reachableParts();
      for (final kind in ['footnote', 'endnote']) {
        parts['content/shared/${kind}s.xml'] = _bytes(
          '<w:${kind}s xmlns:w="$_w" xmlns:x="urn:unrelated"><w:$kind x:type="separator" w:id="1"><w:p/></w:$kind></w:${kind}s>',
        );
      }
      final result = await _inspect(parts, source: _allSourceFeatures);
      expect(result.counts['footnotes'], 1);
      expect(result.counts['endnotes'], 1);
      expect(result.losses, isEmpty);
    });

    test('rejects mismatched story target types and roots', () async {
      for (final kind in _storyKinds) {
        final wrongType = _reachableParts();
        wrongType['[Content_Types].xml'] = _bytes(
          utf8
              .decode(wrongType['[Content_Types].xml']!)
              .replaceFirst('$_wordPartType.$kind+xml', 'application/xml'),
        );
        await expectLater(
          _inspect(wrongType, source: _allSourceFeatures),
          _issue(WordConversionInspectionIssue.invalidOutput),
          reason: '$kind content type',
        );
        final wrongRoot = _reachableParts();
        wrongRoot['content/shared/$kind.xml'] = _bytes(
          '<w:document xmlns:w="$_w"><w:body><w:p/></w:body></w:document>',
        );
        await expectLater(
          _inspect(wrongRoot, source: _allSourceFeatures),
          _issue(WordConversionInspectionIssue.invalidOutput),
          reason: '$kind root',
        );
      }
    });

    test('disconnected relationship errors are still validated', () async {
      final parts = _reachableParts()
        ..remove('content/body/_rels/main.xml.rels');
      parts['content/shared/_rels/comments.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="missing" Type="$_office/oleObject" Target="missing.bin"/>',
        ),
      );
      await expectLater(
        _inspect(parts, source: _allSourceFeatures),
        _issue(WordConversionInspectionIssue.invalidOutput),
      );
    });
  });

  group('observable content and losses', () {
    test('counts emitted rich parts and excludes note separators', () async {
      const prefix =
          'application/vnd.openxmlformats-officedocument.wordprocessingml';
      final parts = _parts(
        body:
            '<w:p><w:ins><w:r><w:t>New</w:t></w:r></w:ins><w:del><w:r/></w:del>'
            '<w:r><w:footnoteReference w:id="2"/><w:endnoteReference w:id="2"/>'
            '<w:commentReference w:id="1"/><w:object>'
            '<w:objectEmbed r:id="rembeddings_object.bin"/></w:object></w:r></w:p>'
            '<w:tbl><w:tr><w:tc><w:p/></w:tc><w:tc><w:p/></w:tc></w:tr></w:tbl>'
            '<w:sectPr><w:headerReference w:type="default" r:id="rheader1.xml"/>'
            '<w:footerReference w:type="default" r:id="rfooter1.xml"/></w:sectPr>',
        overrides: {
          'word/header1.xml': '$prefix.header+xml',
          'word/footer1.xml': '$prefix.footer+xml',
          'word/footnotes.xml': '$prefix.footnotes+xml',
          'word/endnotes.xml': '$prefix.endnotes+xml',
          'word/comments.xml': '$prefix.comments+xml',
          'word/embeddings/object.bin':
              'application/vnd.openxmlformats-officedocument.oleObject',
        },
      );
      parts.addAll({
        'word/header1.xml': _bytes('<w:hdr xmlns:w="$_w"><w:p/></w:hdr>'),
        'word/footer1.xml': _bytes('<w:ftr xmlns:w="$_w"><w:p/></w:ftr>'),
        'word/footnotes.xml': _bytes(
          '<w:footnotes xmlns:w="$_w"><w:footnote w:type="separator" w:id="-1"/><w:footnote w:id="2"><w:p/></w:footnote></w:footnotes>',
        ),
        'word/endnotes.xml': _bytes(
          '<w:endnotes xmlns:w="$_w"><w:endnote w:type="continuationSeparator" w:id="0"/><w:endnote w:id="2"><w:p/></w:endnote></w:endnotes>',
        ),
        'word/comments.xml': _bytes(
          '<w:comments xmlns:w="$_w"><w:comment w:id="1"><w:p/></w:comment></w:comments>',
        ),
        'word/media/image1.png': Uint8List.fromList([137, 80, 78, 71]),
        'word/embeddings/object.bin': Uint8List.fromList([1, 2]),
      });
      parts['word/_rels/document.xml.rels'] = _bytes(
        _relationships(
          [
            for (final (name, kind) in [
              ('header1.xml', 'header'),
              ('footer1.xml', 'footer'),
              ('footnotes.xml', 'footnotes'),
              ('endnotes.xml', 'endnotes'),
              ('comments.xml', 'comments'),
              ('media/image1.png', 'image'),
              ('embeddings/object.bin', 'oleObject'),
            ])
              '<Relationship Id="r${name.replaceAll('/', '_')}" Type="$_office/$kind" Target="$name"/>',
          ].join(),
        ),
      );
      final result = await _inspect(
        parts,
        source: const LegacyWordSourceInspection(
          hasObjects: true,
          hasHeaders: true,
          hasFootnotes: true,
          hasEndnotes: true,
          hasComments: true,
        ),
      );
      expect(result.counts, containsPair('paragraphs', 8));
      expect(result.counts, containsPair('tables', 1));
      expect(result.counts, containsPair('cells', 2));
      expect(result.counts, containsPair('sections', 1));
      for (final key in [
        'headers',
        'footers',
        'footnotes',
        'endnotes',
        'comments',
        'images',
        'objects',
      ]) {
        expect(result.counts[key], 1, reason: key);
      }
      expect(result.counts['revisions'], 2);
      expect(
        result.losses,
        isEmpty,
      ); // Presence only; never a fidelity assertion.
    });

    test('warns for absent source features without inventing missing image evidence', () async {
      final result = await _inspect(
        _parts(),
        source: const LegacyWordSourceInspection(
          hasVba: true,
          hasObjects: true,
          hasHeaders: true,
          hasFootnotes: true,
          hasEndnotes: true,
          hasComments: true,
        ),
      );
      expect(
        result.losses,
        unorderedEquals([
          WordConversionLoss.vbaMissing,
          WordConversionLoss.objectsMissing,
          WordConversionLoss.headersMissing,
          WordConversionLoss.footnotesMissing,
          WordConversionLoss.endnotesMissing,
          WordConversionLoss.commentsMissing,
        ]),
      );
    });

    test(
      'compares scoped VBA payloads and warns when contents changed',
      () async {
        final source = inspectLegacyWordSource(
          _source(
            streams: {
              'Macros/PROJECT': [1, 2],
              'Macros/VBA/Module1': [3, 4],
            },
          ),
        );
        final same = _macroParts(
          _vba({
            'PROJECT': [1, 2],
            'VBA/Module1': [3, 4],
          }),
        );
        final retained = await _inspect(
          same,
          extension: 'docm',
          source: source,
        );
        expect(retained.counts['vba'], 1);
        expect(retained.losses, isEmpty);
        final changed = _macroParts(
          _vba({
            'PROJECT': [1, 2],
            'VBA/Module1': [3, 5],
          }),
        );
        expect(
          (await _inspect(changed, extension: 'docm', source: source)).losses,
          contains(WordConversionLoss.vbaChanged),
        );
        final added = _macroParts(
          _vba({
            'PROJECT': [1, 2],
            'VBA/Module1': [3, 4],
            'VBA/NewModule': [7, 8],
          }),
        );
        expect(
          (await _inspect(added, extension: 'docm', source: source)).losses,
          contains(WordConversionLoss.vbaChanged),
        );
      },
    );

    test('embedded VBA cannot substitute for the main document macro project', () async {
      final source = inspectLegacyWordSource(
        _source(
          streams: {
            'Macros/VBA/Module1': [1, 2],
          },
        ),
      );
      final parts = _parts(
        mainType: _macroType,
        overrides: {
          'word/embeddings/project.bin': 'application/vnd.ms-office.vbaProject',
        },
      );
      parts['word/embeddings/project.bin'] = _vba({
        'VBA/Module1': [1, 2],
      });
      parts['word/_rels/document.xml.rels'] = _bytes(
        _relationships(
          '<Relationship Id="embedded" Type="$_office/oleObject" Target="embeddings/project.bin"/>',
        ),
      );
      final inspected = await _inspect(
        parts,
        extension: 'docm',
        source: source,
      );
      expect(inspected.losses, contains(WordConversionLoss.vbaMissing));
    });

    test(
      'DOCX cannot carry a VBA part regardless of the main content type',
      () async {
        final parts = _parts(
          overrides: {
            'word/vbaProject.bin': 'application/vnd.ms-office.vbaProject',
          },
        );
        parts['word/vbaProject.bin'] = _vba({
          'VBA/Module1': [1],
        });
        await expectLater(
          _inspect(parts),
          _issue(WordConversionInspectionIssue.invalidOutput),
        );
      },
    );
  });
}
