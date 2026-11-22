// Synthetic, reproducible native-picture interoperability fixtures. An actual
// converter must produce SAVED_DIR; verify never rewrites or repairs its input.
// This exercises file conversion, not an installed Zotero plugin or CSL session.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';

const _names = ['png-citations', 'jpeg-citations'];
const _link = 'https://example.org/research?figure=1&view=full';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';

Uint8List _raster(bool jpeg) {
  if (!jpeg) return base64Decode(_png);
  final pixels = image.Image(width: 12, height: 8, numChannels: 3);
  for (var y = 0; y < pixels.height; y++) {
    for (var x = 0; x < pixels.width; x++) {
      pixels.setPixelRgb(x, y, x * 20, y * 30, (x + y) * 12);
    }
  }
  return Uint8List.fromList(image.encodeJpg(pixels, quality: 95));
}

ZoteroCitation _citation(String id) => ZoteroCitation.fromJson({
  'citationID': id,
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '9–11',
      'label': 'page',
      'prefix': 'see ',
      'suppress-author': true,
      'itemData': {'id': 17, 'type': 'book', 'title': 'Research العربية 😀'},
      'futureItem': {'retain': true},
    },
  ],
  'properties': {'plainCitation': '(Same)', 'noteIndex': 0},
  'futureCitation': [true, null, 42],
});

WmlDocument _document(bool jpeg) {
  WmlRun picture({bool linked = false}) => WmlRun(
    text: '\uFFFC',
    hyperlink: linked ? const WmlHyperlink(url: _link) : null,
    inlineVisual: WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Research object',
        imageBytes: _raster(jpeg),
        width: 72,
        height: 48,
        picture: PictureAdjust(
          altTitle: 'Figure title',
          altDescription: 'Six samples & العربية 😀',
        ),
      ),
    ),
  );
  WmlRun cite(String id) => WmlRun(
    text: '(Same)',
    fieldInstruction: _citation(id).fieldInstruction,
    properties: WmlRunProps(italic: true),
  );
  return WmlDocument(
    zoteroDocumentData: jsonEncode({
      'dataVersion': 4,
      'sessionID': 'synthetic-picture-interoperability',
      'style': {
        'styleID': 'http://www.zotero.org/styles/apa',
        'locale': 'de-DE',
      },
      'prefs': {'fieldType': 'Field', 'noteType': 0},
      'futureDocument': {'retain': 'العربية 😀'},
    }),
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Native Zotero image fixture')]),
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Before 😀 '),
              picture(linked: true),
              WmlRun(text: ' '),
              cite('first'),
              WmlRun(text: ' middle '),
              cite('second'),
              picture(),
              WmlRun(text: ' after'),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'End of fixture')]),
        ],
      ),
    ],
  );
}

Map<String, Object?> _summary(WmlDocument document) => {
  'preferences': jsonDecode(WordZoteroDocumentData.read(document)),
  'paragraphs': document.paragraphs.map((p) => p.text).toList(),
  'fields': [
    for (final field in WordZotero.fields(document))
      {
        'metadata': field.metadata,
        'cache': field.cachedText,
        'editable': field.canEdit,
        'start': field.start,
        'end': field.end,
      },
  ],
  'images': [
    for (final paragraph in document.paragraphs)
      for (final run in paragraph.inlines.whereType<WmlRun>())
        if (run.inlineVisual case final visual?)
          {
            'placeholder': run.text,
            'sha256': sha256.convert(visual.visual.imageBytes!).toString(),
            'width': visual.visual.width,
            'height': visual.visual.height,
            'title': visual.visual.picture.altTitle,
            'description': visual.visual.picture.altDescription,
            'link': run.hyperlink?.url,
          },
  ],
};

void _compare(Object? actual, Object? expected, String path) {
  if (actual is num &&
      expected is num &&
      (path.endsWith('.width') || path.endsWith('.height'))) {
    // LibreOffice serializes extents in rounded physical units. This permits
    // at most 0.03 pt quantization, not layout rescaling or a missing picture.
    if ((actual - expected).abs() <= 0.03) return;
  } else if (actual is Map && expected is Map) {
    if (actual.length == expected.length &&
        actual.keys.every(expected.containsKey)) {
      for (final key in actual.keys) {
        _compare(actual[key], expected[key], '$path.$key');
      }
      return;
    }
  } else if (actual is List && expected is List) {
    if (actual.length == expected.length) {
      for (var i = 0; i < actual.length; i++) {
        _compare(actual[i], expected[i], '$path[$i]');
      }
      return;
    }
  } else if (actual == expected) {
    return;
  }
  throw StateError('Mismatch at $path: expected $expected, actual $actual');
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || !['create', 'verify'].contains(args[0])) {
    throw ArgumentError(
      'Use create DIR or verify SAVED_DIR EXPECTED_DIR OUT_DIR',
    );
  }
  final directory = Directory(args[1]);
  if (args[0] == 'create') {
    directory.createSync(recursive: true);
    for (var i = 0; i < _names.length; i++) {
      final document = _document(i == 1);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      File('${directory.path}/${_names[i]}.odt').writeAsBytesSync(bytes);
      File('${directory.path}/${_names[i]}.expected.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_summary(document)),
      );
      // Make a failed Quds-origin route explicit before using any converter.
      _compare(
        _summary(await OdtDocumentReader.readBytes(bytes)),
        _summary(document),
        _names[i],
      );
    }
    stdout.writeln(
      jsonEncode({'created': _names, 'nativeImportMatched': true}),
    );
    return;
  }
  if (args.length != 4) {
    throw ArgumentError('Expected and output directories required');
  }
  final output = Directory(args[3])..createSync(recursive: true);
  for (final name in _names) {
    final input = File('${directory.path}/$name.odt').readAsBytesSync();
    final expected = jsonDecode(
      File('${args[2]}/$name.expected.json').readAsStringSync(),
    );
    var document = await OdtDocumentReader.readBytes(input);
    for (var cycle = 0; cycle < 3; cycle++) {
      final actual = _summary(document);
      File(
        '${output.path}/$name-cycle-$cycle.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(actual));
      _compare(actual, expected, '$name.cycle$cycle');
      final docx = WordSerializer().writeBytes(document);
      File('${output.path}/$name-cycle-$cycle.docx').writeAsBytesSync(docx);
      document = WordDeserializer().readBytes(docx);
      _compare(_summary(document), expected, '$name.docx$cycle');
      final odt = OdtDocumentWriter.writeEditableZoteroBytes(document);
      File('${output.path}/$name-cycle-$cycle.odt').writeAsBytesSync(odt);
      document = await OdtDocumentReader.readBytes(odt);
      _compare(_summary(document), expected, '$name.odt$cycle');
    }
    stdout.writeln(
      jsonEncode({
        'file': name,
        'inputSha256': sha256.convert(input).toString(),
        'pictures': 2,
        'activeCitations': 2,
        'cycles': 3,
        'matched': true,
      }),
    );
  }
}
