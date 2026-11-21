import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:page-setup-test';
const _size =
    '<w:pgSz w:w="12240" w:h="15840" w:orient="portrait" '
    'w:code="9" x:w="foreign-width" x:code="foreign-paper"/>';
const _margins =
    '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" '
    'w:right="1440" w:header="720" w:footer="720" w:gutter="0" '
    'x:left="foreign-left"><x:child x:val="keep"/></w:pgMar>';

WmlDocument _fixture({
  String size = _size,
  String margins = _margins,
  String columns = '<w:cols w:num="2" w:space="720"/>',
  String extra = '',
  String settings = '',
  String settingsAttributes = '',
  String documentAttributes = '',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Original text')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x" '
        'xmlns:mc="${OfficeNamespaces.mc}" $documentAttributes><w:body>'
        '<w:p><w:r><w:t>Original text</w:t></w:r></w:p>'
        '<w:sectPr>$size$margins$columns$extra'
        '<w:pgNumType w:start="7"/><x:metadata x:val="keep"/>'
        '</w:sectPr></w:body></w:document>',
      );
  if (settings.isNotEmpty) {
    package
        .getPart('/word/settings.xml')!
        .writeText(
          '<w:settings xmlns:w="$_w" xmlns:x="$_x" '
          'xmlns:mc="${OfficeNamespaces.mc}" $settingsAttributes>$settings</w:settings>',
        );
  }
  return WordDeserializer().read(package);
}

XmlElement _section(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('sectPr', namespaceUri: _w)!;

Map<String, Object?> _step(String property, Object? points) => {
  'op': 'pageSetup',
  'section': 0,
  'property': property,
  'points': points,
};

void _refuses(
  WmlDocument document,
  Map<String, Object?> operation, {
  Matcher? matcher,
}) {
  final section = document.sections.single;
  final size = section.pageSize;
  final margins = section.margins;
  final source = section.sourceProperties;
  final parts = <String, Uint8List>{
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  };
  expect(
    () => native.applyStep(document, operation),
    matcher ?? throwsUnsupportedError,
  );
  expect(section.pageSize, same(size));
  expect(section.margins, same(margins));
  expect(section.sourceProperties, same(source));
  expect({
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  }, parts);
}

void main() {
  for (final (property, attribute, points) in [
    ('width', 'w', 650.15),
    ('height', 'h', 820.05),
    ('top', 'top', 54.25),
    ('bottom', 'bottom', 54.25),
    ('left', 'left', 54.25),
    ('right', 'right', 54.25),
    ('header', 'header', 18.15),
    ('footer', 'footer', 18.15),
  ]) {
    test('$property owns one native attribute through repeated reopens', () {
      var document = _fixture();
      final dimension = property == 'width' || property == 'height';
      native.applyStep(document, _step(property, points));
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final section = _section(bytes);
        final size = section.firstChild('pgSz', namespaceUri: _w)!;
        final margins = section.firstChild('pgMar', namespaceUri: _w)!;
        final target = dimension ? size : margins;
        expect(
          target.getAttribute(attribute, namespaceUri: _w),
          '${(points * 20).round()}',
        );
        for (final entry in {'w': '12240', 'h': '15840'}.entries) {
          expect(
            size.getAttribute(entry.key, namespaceUri: _w),
            dimension && attribute == entry.key
                ? '${(points * 20).round()}'
                : entry.value,
          );
        }
        for (final entry in {
          'top': '1440',
          'bottom': '1440',
          'left': '1440',
          'right': '1440',
          'header': '720',
          'footer': '720',
        }.entries) {
          expect(
            margins.getAttribute(entry.key, namespaceUri: _w),
            !dimension && attribute == entry.key
                ? '${(points * 20).round()}'
                : entry.value,
          );
        }
        expect(
          size.getAttribute('code', namespaceUri: _w),
          dimension ? null : '9',
        );
        expect(size.getAttribute('code', namespaceUri: _x), 'foreign-paper');
        expect(size.getAttribute('w', namespaceUri: _x), 'foreign-width');
        expect(size.getAttribute('orient', namespaceUri: _w), 'portrait');
        expect(margins.getAttribute('left', namespaceUri: _x), 'foreign-left');
        expect(margins.firstChild('child', namespaceUri: _x), isNotNull);
        expect(
          section
              .firstChild('pgNumType', namespaceUri: _w)!
              .getAttribute('start', namespaceUri: _w),
          '7',
        );
        expect(section.firstChild('metadata', namespaceUri: _x), isNotNull);
        expect(
          section
              .firstChild('cols', namespaceUri: _w)!
              .getAttribute('num', namespaceUri: _w),
          '2',
        );
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.single.text, 'Original text');
      }
    });
  }

  test(
    'same-value dimensions select custom paper and preserve foreign code',
    () {
      final document = _fixture();
      native.applyStep(document, _step('width', 612));
      final size = _section(
        WordSerializer().writeBytes(document),
      ).firstChild('pgSz', namespaceUri: _w)!;
      expect(size.getAttribute('code', namespaceUri: _w), isNull);
      expect(size.getAttribute('code', namespaceUri: _x), 'foreign-paper');
      expect(size.getAttribute('w', namespaceUri: _w), '12240');
      expect(size.getAttribute('h', namespaceUri: _w), '15840');
    },
  );

  test(
    'successive sparse writes and preceding native edits are all retained',
    () {
      final document = _fixture();
      native.applyStep(document, {
        'op': 'sectionFormat',
        'section': 0,
        'left': 60,
        'height': 900,
      });
      native.applyStep(document, _step('right', 48));
      native.applyStep(document, _step('top', 36));
      native.applyStep(document, _step('width', 700));
      final saved = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final section = saved.sections.single;
      expect(section.margins.left, 60);
      expect(section.margins.right, 48);
      expect(section.margins.top, 36);
      expect(section.margins.bottom, 72);
      expect(section.pageSize.width, 700);
      expect(section.pageSize.height, 900);
    },
  );

  test('missing native groups are created with complete modeled geometry', () {
    final document = _fixture(size: '', margins: '');
    native.applyStep(document, _step('width', 612));
    native.applyStep(document, _step('left', 36));
    final section = _section(WordSerializer().writeBytes(document));
    final size = section.firstChild('pgSz', namespaceUri: _w)!;
    final margins = section.firstChild('pgMar', namespaceUri: _w)!;
    expect(size.getAttribute('w', namespaceUri: _w), '12240');
    expect(size.getAttribute('h', namespaceUri: _w), isNotNull);
    for (final name in ['top', 'bottom', 'left', 'right', 'header', 'footer']) {
      expect(margins.getAttribute(name, namespaceUri: _w), isNotNull);
    }
  });

  test('pending general dimension edits retain their orientation behavior', () {
    final document = _fixture();
    native.applyStep(document, {
      'op': 'sectionFormat',
      'section': 0,
      'width': 900,
    });
    native.applyStep(document, _step('height', 800));
    final size = _section(
      WordSerializer().writeBytes(document),
    ).firstChild('pgSz', namespaceUri: _w)!;
    expect(size.getAttribute('w', namespaceUri: _w), '18000');
    expect(size.getAttribute('h', namespaceUri: _w), '16000');
    expect(size.getAttribute('orient', namespaceUri: _w), 'landscape');
  });

  test(
    'preceding native dimensions create missing size without namespace loss',
    () {
      final document = _fixture(size: '');
      native.applyStep(document, {
        'op': 'sectionFormat',
        'section': 0,
        'width': 700,
        'height': 900,
      });
      native.applyStep(document, _step('left', 48));
      final bytes = WordSerializer().writeBytes(document);
      final size = _section(bytes).firstChild('pgSz', namespaceUri: _w)!;
      expect(size.getAttribute('w', namespaceUri: _w), '14000');
      expect(size.getAttribute('h', namespaceUri: _w), '18000');
      final reopened = WordDeserializer().readBytes(bytes).sections.single;
      expect(reopened.pageSize.width, 700);
      expect(reopened.pageSize.height, 900);
      expect(reopened.margins.left, 48);
    },
  );

  test('imported sparse groups do not acquire unrelated attributes', () {
    final document = _fixture(margins: '<w:pgMar w:top="1440"/>');
    native.applyStep(document, _step('left', 36));
    final margins = _section(
      WordSerializer().writeBytes(document),
    ).firstChild('pgMar', namespaceUri: _w)!;
    expect(margins.getAttribute('top', namespaceUri: _w), '1440');
    expect(margins.getAttribute('left', namespaceUri: _w), '720');
    expect(margins.getAttribute('right', namespaceUri: _w), isNull);
    expect(margins.getAttribute('header', namespaceUri: _w), isNull);
  });

  test('namespace aliases and default namespace preserve foreign prefixes', () {
    final document = _fixture(
      margins:
          '<pgMar xmlns="$_w" xmlns:w="$_x" xmlns:n="$_w" '
          'n:top="1440" n:bottom="1440" n:left="1440" n:right="1440" '
          'n:header="720" n:footer="720" w:left="foreign"/>',
    );
    native.applyStep(document, _step('left', 48));
    final margins = _section(
      WordSerializer().writeBytes(document),
    ).firstChild('pgMar', namespaceUri: _w)!;
    expect(margins.getAttribute('left', namespaceUri: _w), '960');
    expect(margins.getAttribute('left', namespaceUri: _x), 'foreign');
  });

  test('mixed native edits never rebind an imported foreign namespace', () {
    final document = _fixture(
      size:
          '<pgSz xmlns="$_w" xmlns:w="$_x" w:token="keep"><w:metadata/></pgSz>',
    );
    native.applyStep(document, {
      'op': 'sectionFormat',
      'section': 0,
      'width': 700,
      'height': 900,
    });
    native.applyStep(document, _step('left', 48));
    final size = _section(
      WordSerializer().writeBytes(document),
    ).firstChild('pgSz', namespaceUri: _w)!;
    expect(size.getAttribute('token', namespaceUri: _x), 'keep');
    expect(size.getAttribute('token', namespaceUri: _w), isNull);
    expect(size.firstChild('metadata', namespaceUri: _x), isNotNull);
    expect(size.firstChild('metadata', namespaceUri: _w), isNull);
    expect(size.getAttribute('w', namespaceUri: _w), '14000');
    expect(size.getAttribute('h', namespaceUri: _w), '18000');
  });

  test(
    'repeated writes reuse a native prefix without growing source metadata',
    () {
      final document = _fixture(
        margins: '<pgMar xmlns="$_w" xmlns:w="$_x" w:token="keep"/>',
      );
      native.applyStep(document, _step('left', 48));
      final source = document.sections.single.sourceProperties!.xml;
      for (var index = 0; index < 50; index++) {
        native.applyStep(document, _step('left', 48));
      }
      expect(document.sections.single.sourceProperties!.xml, source);
    },
  );

  test('ProcessContent cannot hide active settings or section geometry', () {
    _refuses(
      _fixture(
        settings: '<x:wrapper><w:mirrorMargins/></x:wrapper>',
        settingsAttributes: 'mc:Ignorable="x" mc:ProcessContent="x:wrapper"',
      ),
      _step('left', 36),
    );
    _refuses(
      _fixture(
        extra: '<x:wrapper><w:pgMar w:left="20"/></x:wrapper>',
        documentAttributes: 'mc:Ignorable="x" mc:ProcessContent="x:wrapper"',
      ),
      _step('left', 36),
    );
  });

  for (final (name, document) in <(String, WmlDocument Function())>[
    ('duplicate page size', () => _fixture(size: '$_size$_size')),
    ('duplicate margins', () => _fixture(margins: '$_margins$_margins')),
    ('duplicate columns', () => _fixture(columns: '<w:cols/><w:cols/>')),
    (
      'negative source margin',
      () => _fixture(margins: '<w:pgMar w:top="-1440"/>'),
    ),
    (
      'malformed source margin',
      () => _fixture(margins: '<w:pgMar w:top="oops"/>'),
    ),
    ('universal measure', () => _fixture(margins: '<w:pgMar w:top="1in"/>')),
    ('gutter', () => _fixture(margins: '<w:pgMar w:gutter="100"/>')),
    (
      'custom columns',
      () => _fixture(columns: '<w:cols w:num="2"><w:col w:w="1200"/></w:cols>'),
    ),
    ('unequal columns', () => _fixture(columns: '<w:cols w:equalWidth="0"/>')),
    ('invalid columns', () => _fixture(columns: '<w:cols w:num="oops"/>')),
    (
      'alternate geometry',
      () => _fixture(
        extra:
            '<mc:AlternateContent><mc:Choice Requires="x"><w:pgMar w:left="20"/>'
            '</mc:Choice><mc:Fallback/></mc:AlternateContent>',
      ),
    ),
  ]) {
    test('$name is refused without native mutation', () {
      _refuses(document(), _step('left', 36));
    });
  }

  for (final setting in [
    'mirrorMargins',
    'gutterAtTop',
    'bookFoldPrinting',
    'bookFoldRevPrinting',
  ]) {
    test('$setting is refused unless explicitly disabled', () {
      _refuses(_fixture(settings: '<w:$setting/>'), _step('left', 36));
      for (final value in ['0', 'false', 'off']) {
        final document = _fixture(settings: '<w:$setting w:val="$value"/>');
        native.applyStep(document, _step('left', 36));
        expect(document.sections.single.margins.left, 36);
      }
      _refuses(
        _fixture(
          settings:
              '<mc:AlternateContent><mc:Choice Requires="x"><w:$setting/>'
              '</mc:Choice><mc:Fallback/></mc:AlternateContent>',
        ),
        _step('left', 36),
      );
    });
  }

  for (final points in <Object?>[
    -0.05,
    1.01,
    double.nan,
    double.infinity,
    107374182.4,
    '36',
    null,
    true,
  ]) {
    test('invalid native points $points fail atomically', () {
      _refuses(_fixture(), _step('left', points), matcher: throwsArgumentError);
    });
  }

  test('intermediate page body and column width are checked atomically', () {
    _refuses(_fixture(), _step('width', 144), matcher: throwsArgumentError);
    _refuses(_fixture(), _step('height', 144), matcher: throwsArgumentError);
    _refuses(_fixture(), _step('width', 170), matcher: throwsArgumentError);
    _refuses(_fixture(), _step('width', 0.95), matcher: throwsArgumentError);
    _refuses(_fixture(), _step('unknown', 36), matcher: throwsArgumentError);
    _refuses(_fixture(), {
      'op': 'pageSetup',
      'property': 'left',
      'points': 36,
    }, matcher: throwsArgumentError);
  });

  test('programmatically constructed section uses ordinary serializer', () {
    final document = WmlDocument();
    document.sections.single.blocks.add(WmlParagraph());
    native.applyStep(document, _step('left', 0));
    native.applyStep(document, _step('width', 612));
    final saved = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(saved.sections.single.margins.left, 0);
    expect(saved.sections.single.pageSize.width, 612);
  });
}
