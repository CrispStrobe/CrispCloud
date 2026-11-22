import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:quds_office_engine/src/automation/operations/word_text_columns_steps.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:text-columns-test';
const _size =
    '<w:pgSz w:w="12240" w:h="15840" w:orient="portrait" '
    'w:code="9" x:w="foreign-width"/>';
const _margins =
    '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" '
    'w:right="1440" w:header="720" w:footer="720" w:gutter="0" '
    'x:left="foreign-left"/>';
const _columns =
    '<w:cols w:num="2" w:space="720" w:sep="0" w:equalWidth="true" '
    'x:num="foreign-count" x:space="foreign-space" x:sep="foreign-separator">'
    '<x:metadata><w:cols w:num="99"/></x:metadata></w:cols>';

WmlDocument _fixture({
  String size = _size,
  String margins = _margins,
  String columns = _columns,
  String extra = '',
  String settings = '',
  String settingsAttributes = '',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Original text')).build(),
  );
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:q="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}">
<w:body><w:p><w:r><w:t>Original text</w:t></w:r></w:p>
<w:sectPr>$size$margins$columns$extra
<w:pgNumType w:start="7"/><x:metadata x:val="keep"/>
</w:sectPr></w:body></w:document>''');
  if (settings.isNotEmpty || settingsAttributes.isNotEmpty) {
    package.getPart('/word/settings.xml')!.writeText(
      '''
<w:settings xmlns:w="$_w" xmlns:q="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}" $settingsAttributes>$settings</w:settings>''',
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

Map<String, Object?> _step(String property, Object? value) => {
  'op': 'textColumns',
  'section': 0,
  property: value,
};

void _refuses(
  WmlDocument document,
  Map<String, Object?> operation, {
  Matcher? matcher,
}) {
  final section = document.sections.first;
  final before = (section.columnCount, section.columnSpace, section.columnSep);
  final source = section.sourceProperties;
  final size = section.pageSize;
  final margins = section.margins;
  final parts = <String, Uint8List>{
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  };
  expect(
    () => native.applyStep(document, operation),
    matcher ?? throwsUnsupportedError,
  );
  expect(section.columnCount, before.$1);
  expect(section.columnSpace, before.$2.isNaN ? isNaN : before.$2);
  expect(section.columnSep, before.$3);
  expect(section.sourceProperties, same(source));
  expect(section.pageSize, same(size));
  expect(section.margins, same(margins));
  expect({
    for (final part in document.package!.parts) part.uri: part.readBytes(),
  }, parts);
}

void main() {
  for (final (property, value, attribute, expected)
      in <(String, Object, String, String)>[
        ('count', 3, 'num', '3'),
        ('spacing', 18.15, 'space', '363'),
        ('lineBetween', true, 'sep', '1'),
        ('lineBetween', false, 'sep', '0'),
      ]) {
    test('$property $value owns only its native column attribute', () {
      var document = _fixture();
      native.applyStep(document, _step(property, value));
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final section = _section(bytes);
        final columns = section.firstChild('cols', namespaceUri: _w)!;
        for (final entry in {'num': '2', 'space': '720', 'sep': '0'}.entries) {
          expect(
            columns.getAttribute(entry.key, namespaceUri: _w),
            entry.key == attribute ? expected : entry.value,
          );
        }
        expect(columns.getAttribute('equalWidth', namespaceUri: _w), 'true');
        expect(columns.getAttribute('num', namespaceUri: _x), 'foreign-count');
        expect(
          columns.getAttribute('space', namespaceUri: _x),
          'foreign-space',
        );
        expect(
          columns.getAttribute('sep', namespaceUri: _x),
          'foreign-separator',
        );
        expect(columns.firstChild('metadata', namespaceUri: _x), isNotNull);
        final size = section.firstChild('pgSz', namespaceUri: _w)!;
        expect(size.getAttribute('w', namespaceUri: _w), '12240');
        expect(size.getAttribute('h', namespaceUri: _w), '15840');
        expect(size.getAttribute('orient', namespaceUri: _w), 'portrait');
        expect(size.getAttribute('code', namespaceUri: _w), '9');
        expect(size.getAttribute('w', namespaceUri: _x), 'foreign-width');
        expect(
          section
              .firstChild('pgNumType', namespaceUri: _w)!
              .getAttribute('start', namespaceUri: _w),
          '7',
        );
        expect(section.firstChild('metadata', namespaceUri: _x), isNotNull);
        document = WordDeserializer().readBytes(bytes);
        final model = document.sections.single;
        expect(model.columnCount, property == 'count' ? value : 2);
        expect(model.columnSpace, property == 'spacing' ? value : 36);
        expect(model.columnSep, property == 'lineBetween' ? value : false);
        expect(document.paragraphs.single.text, 'Original text');
      }
    });
  }

  test('native namespace aliases and foreign prefix bindings are retained', () {
    var document = _fixture(
      columns:
          '<q:cols xmlns:w="$_x" q:num="2" q:space="720" q:sep="1" '
          'w:num="foreign-count"><w:col w:w="opaque"/></q:cols>',
    );
    native.applyStep(document, _step('spacing', 24));
    final bytes = WordSerializer().writeBytes(document);
    final columns = _section(bytes).firstChild('cols', namespaceUri: _w)!;
    expect(columns.prefix, 'q');
    expect(columns.getAttribute('num', namespaceUri: _x), 'foreign-count');
    expect(columns.firstChild('col', namespaceUri: _x), isNotNull);
    expect(columns.getAttribute('space', namespaceUri: _w), '480');
    document = WordDeserializer().readBytes(bytes);
    expect(document.sections.single.columnSpace, 24);
    expect(document.sections.single.columnSep, isTrue);
  });

  for (final (property, value, attribute, expected)
      in <(String, Object, String, String)>[
        ('count', 1, 'num', '1'),
        ('spacing', 36, 'space', '720'),
        ('lineBetween', false, 'sep', '0'),
      ]) {
    test(
      'same-value $property explicitly owns its previously absent attribute',
      () {
        final document = _fixture(columns: '<w:cols x:num="opaque"/>');
        native.applyStep(document, _step(property, value));
        final columns = _section(
          WordSerializer().writeBytes(document),
        ).firstChild('cols', namespaceUri: _w)!;
        expect(columns.getAttribute(attribute, namespaceUri: _w), expected);
        for (final other in [
          'num',
          'space',
          'sep',
        ].where((v) => v != attribute)) {
          expect(columns.getAttribute(other, namespaceUri: _w), isNull);
        }
        expect(columns.getAttribute('num', namespaceUri: _x), 'opaque');
      },
    );
  }

  test(
    'missing columns and source-free sections get complete uniform groups',
    () {
      for (final document in [
        _fixture(columns: ''),
        WmlDocument.empty(text: 'New'),
      ]) {
        native.applyStep(document, _step('count', 3));
        final bytes = WordSerializer().writeBytes(document);
        final columns = _section(bytes).firstChild('cols', namespaceUri: _w)!;
        expect(columns.getAttribute('num', namespaceUri: _w), '3');
        expect(columns.getAttribute('space', namespaceUri: _w), '720');
        expect(columns.getAttribute('sep', namespaceUri: _w), '0');
        final reopened = WordDeserializer().readBytes(bytes).sections.single;
        expect(
          (reopened.columnCount, reopened.columnSpace, reopened.columnSep),
          (3, 36, false),
        );
      }
    },
  );

  for (final lexical in ['1', 'true', 'on', '0', 'false', 'off']) {
    test(
      'separator $lexical projects correctly and survives another column edit',
      () {
        final enabled = {'1', 'true', 'on'}.contains(lexical);
        final document = _fixture(
          columns:
              '<w:cols w:num="2" w:space="720" w:sep="$lexical" '
              'x:sep="${enabled ? '0' : '1'}"/>',
        );
        expect(document.sections.single.columnSep, enabled);
        native.applyStep(document, _step('count', 3));
        final bytes = WordSerializer().writeBytes(document);
        expect(
          _section(bytes)
              .firstChild('cols', namespaceUri: _w)!
              .getAttribute('sep', namespaceUri: _w),
          lexical,
        );
        expect(
          WordDeserializer().readBytes(bytes).sections.single.columnSep,
          enabled,
        );
      },
    );
  }

  test('successive sparse setters preserve pending general section edits', () {
    final document = _fixture();
    native.applyStep(document, {
      'op': 'sectionFormat',
      'section': 0,
      'width': 700,
      'height': 900,
      'left': 60,
      'columns': 3,
      'columnSpace': 12,
      'columnSep': true,
    });
    native.applyStep(document, _step('spacing', 18));
    native.applyStep(document, _step('count', 4));
    final bytes = WordSerializer().writeBytes(document);
    final section = WordDeserializer().readBytes(bytes).sections.single;
    expect(
      (section.columnCount, section.columnSpace, section.columnSep),
      (4, 18, true),
    );
    expect((section.pageSize.width, section.pageSize.height), (700, 900));
    expect(section.margins.left, 60);
    expect(
      _section(bytes)
          .firstChild('cols', namespaceUri: _w)!
          .firstChild('metadata', namespaceUri: _x),
      isNotNull,
    );
  });

  test(
    'column writes compose with independent geometry and section starts',
    () {
      final document = _fixture(columns: '');
      native.applyStep(document, {
        'op': 'pageOrientation',
        'section': 0,
        'orientation': 'landscape',
      });
      native.applyStep(document, _step('count', 3));
      native.applyStep(document, {
        'op': 'pageSetup',
        'section': 0,
        'property': 'left',
        'points': 36,
      });
      native.applyStep(document, _step('spacing', 18));
      native.applyStep(document, {
        'op': 'sectionStart',
        'section': 0,
        'kind': 'oddPage',
      });
      native.applyStep(document, _step('lineBetween', true));
      final section = WordDeserializer()
          .readBytes(WordSerializer().writeBytes(document))
          .sections
          .single;
      expect((section.pageSize.width, section.pageSize.height), (792, 612));
      expect(section.margins.left, 36);
      expect(section.breakKind, WmlSectionBreakKind.oddPage);
      expect(
        (section.columnCount, section.columnSpace, section.columnSep),
        (3, 18, true),
      );
    },
  );

  test('a sparse source made by another section edit retains its geometry', () {
    final document = WmlDocument.empty(text: 'Sparse');
    final originalSize = document.sections.single.pageSize;
    native.applyStep(document, {
      'op': 'pageOrientation',
      'section': 0,
      'orientation': 'landscape',
    });
    native.applyStep(document, _step('count', 3));
    final section = WordDeserializer()
        .readBytes(WordSerializer().writeBytes(document))
        .sections
        .single;
    expect(section.pageSize.width, pointsToTwips(originalSize.height) / 20);
    expect(section.pageSize.height, pointsToTwips(originalSize.width) / 20);
    expect(section.columnCount, 3);
  });

  test('both column setter orders retain dimensions and separator layout', () {
    for (final countFirst in [true, false]) {
      final document = _fixture();
      final operations = [_step('count', 3), _step('spacing', 18)];
      for (final operation in countFirst ? operations : operations.reversed) {
        native.applyStep(document, operation);
      }
      native.applyStep(document, _step('lineBetween', true));
      final section = document.sections.single;
      expect(section.columnWidth, 144);
      final laid = WordLayoutEngine(font: null).layout(document);
      final separators = laid.pages.first.frames
          .where((box) => box.kind == LaidOutBoxKind.columnSep)
          .toList();
      expect(separators.length, 2);
      expect(separators.map((box) => box.x), [225, 387]);
      native.applyStep(document, _step('lineBetween', false));
      expect(
        WordLayoutEngine(font: null)
            .layout(document)
            .pages
            .first
            .frames
            .where((box) => box.kind == LaidOutBoxKind.columnSep),
        isEmpty,
      );
    }
  });

  test('45 columns work when each has 12 points and zero gap', () {
    final document = _fixture(
      size: '<w:pgSz w:w="13680" w:h="15840"/>',
      columns: '<w:cols w:num="1" w:space="0"/>',
    );
    native.applyStep(document, _step('count', 45));
    expect(document.sections.single.columnWidth, 12);
    expect(
      WordDeserializer()
          .readBytes(WordSerializer().writeBytes(document))
          .sections
          .single
          .columnCount,
      45,
    );
  });

  test('one column retains bounded spacing that is unused by its layout', () {
    final document = _fixture(columns: '<w:cols w:num="1"/>');
    native.applyStep(document, _step('spacing', 2147483647 / 20));
    expect(document.sections.single.columnWidth, 468);
    _refuses(document, _step('count', 2), matcher: throwsArgumentError);
  });

  for (final operation in <Map<String, Object?>>[
    {'op': 'textColumns', 'section': 0},
    {'op': 'textColumns', 'section': 0, 'count': 2, 'spacing': 18},
    {'op': 'textColumns', 'section': 0, 'count': 2, 'lineBetween': false},
    {'op': 'textColumns', 'count': 2},
    {'op': 'textColumns', 'section': 99, 'count': 2},
    {'op': 'textColumns', 'section': 0, 'columns': 2},
    for (final value in [0, -1, 46, 2.5, '2', true, null])
      _step('count', value),
    for (final value in [
      -1,
      0.01,
      2147483648 / 20,
      double.nan,
      double.infinity,
      '18',
      true,
      null,
    ])
      _step('spacing', value),
    for (final value in [0, 1, 'true', null]) _step('lineBetween', value),
  ]) {
    test('invalid native arguments refuse without mutation: $operation', () {
      _refuses(_fixture(), operation, matcher: throwsArgumentError);
    });
  }

  for (final columns in [
    '<w:cols/><w:cols/>',
    '<w:cols w:num="2" q:num="3"/>',
    '<w:cols w:num="0"/>',
    '<w:cols w:num="46"/>',
    '<w:cols w:num="2.5"/>',
    '<w:cols w:space="-1"/>',
    '<w:cols w:space="18pt"/>',
    '<w:cols w:space="2147483648"/>',
    '<w:cols w:sep="maybe"/>',
    '<w:cols w:sep="1" q:sep="0"/>',
    '<w:cols w:equalWidth="false"/>',
    '<w:cols w:equalWidth="off"/>',
    '<w:cols w:equalWidth="maybe"/>',
    '<w:cols><w:col w:w="2400"/></w:cols>',
    '<w:cols w:unknown="1"/>',
    '<w:cols><w:unknown/></w:cols>',
  ]) {
    test('ambiguous or custom column source is refused: $columns', () {
      _refuses(_fixture(columns: columns), _step('count', 3));
    });
  }

  for (final extra in [
    '<w:pgSz w:w="12240" w:h="15840"/>',
    '<w:textDirection w:val="tbRl"/>',
    '<w:bidi/>',
    '<w:bidi w:val="true"/>',
    '<mc:AlternateContent><mc:Choice Requires="x"><w:cols w:num="3"/></mc:Choice>'
        '<mc:Fallback><w:cols w:num="2"/></mc:Fallback></mc:AlternateContent>',
    '<x:metadata mc:ProcessContent="x:child"><x:child/></x:metadata>',
  ]) {
    test('unreliable section geometry is refused: $extra', () {
      _refuses(_fixture(extra: extra), _step('spacing', 18));
    });
  }

  for (final margins in [
    '<w:pgMar w:left="1440" q:left="720"/>',
    '<w:pgMar w:left="-1"/>',
    '<w:pgMar w:left="1in"/>',
    '<w:pgMar w:gutter="120"/>',
  ]) {
    test('unmodeled margins are refused: $margins', () {
      _refuses(_fixture(margins: margins), _step('count', 3));
    });
  }

  for (final settings in [
    '<w:mirrorMargins/>',
    '<w:gutterAtTop w:val="true"/>',
    '<w:bookFoldPrinting w:val="1"/>',
    '<w:bookFoldRevPrinting w:val="on"/>',
    '<w:mirrorMargins w:val="false" q:val="true"/>',
    '<mc:AlternateContent><mc:Choice Requires="x"><w:mirrorMargins/></mc:Choice>'
        '<mc:Fallback><w:mirrorMargins w:val="false"/></mc:Fallback></mc:AlternateContent>',
  ]) {
    test('unmodeled settings are refused: $settings', () {
      _refuses(_fixture(settings: settings), _step('count', 3));
    });
  }

  test('foreign settings and disabled native special modes remain opaque', () {
    final document = _fixture(
      extra: '<w:bidi w:val="false"/><w:textDirection w:val="lrTb"/>',
      settings:
          '<w:mirrorMargins w:val="off"/><w:gutterAtTop w:val="0"/>'
          '<x:mirrorMargins/><x:metadata><w:bookFoldPrinting/></x:metadata>',
    );
    native.applyStep(document, _step('count', 3));
    expect(document.sections.single.columnCount, 3);
  });

  test('width below the native 12-point layout minimum is refused', () {
    _refuses(_fixture(), _step('spacing', 445), matcher: throwsArgumentError);
    _refuses(_fixture(), _step('count', 45), matcher: throwsArgumentError);
    final document = _fixture();
    document.sections.single.pageSize = const WmlPageSize(
      width: 167.99,
      height: 792,
    );
    _refuses(document, _step('spacing', 0), matcher: throwsArgumentError);
  });

  test('invalid live geometry and aliased sections do not change state', () {
    final document = _fixture();
    document.sections.single.columnSpace = double.nan;
    _refuses(document, _step('count', 3));
    final aliased = _fixture();
    aliased.sections.add(aliased.sections.single);
    _refuses(aliased, _step('count', 3));
  });

  test('incomplete or inconsistent source snapshots are refused', () {
    for (final snapshot in [
      null,
      '2|720',
      '2|720|false|extra',
      '3|720|false',
      '2|bogus|false',
      '2|720|maybe',
    ]) {
      final document = _fixture();
      final source = document.sections.single.sourceProperties!;
      final values = {...source.values}..remove('cols');
      if (snapshot != null) values['cols'] = snapshot;
      document.sections.single.sourceProperties = WmlSectionSource(
        xml: source.xml,
        values: values,
      );
      _refuses(document, _step('count', 3));
    }
  });

  test(
    'direct helper rejects no action and multiple actions before mutation',
    () {
      final document = _fixture();
      final section = document.sections.single;
      final source = section.sourceProperties;
      expect(() => setWordTextColumns(document, section), throwsArgumentError);
      expect(
        () => setWordTextColumns(document, section, count: 3, spacing: 18),
        throwsArgumentError,
      );
      expect(section.sourceProperties, same(source));
      expect(section.columnCount, 2);
    },
  );
}
