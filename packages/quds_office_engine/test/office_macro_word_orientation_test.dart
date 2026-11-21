import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_page_setup_steps.dart';
import 'package:quds_office_engine/src/automation/operations/word_section_start_steps.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_page_setup_smoke.dart' as fixture;

const _w = OfficeNamespaces.w;
const _x = 'urn:word-orientation-test';
const _size =
    '<w:pgSz w:w="12240" w:h="15840" w:orient="portrait" w:code="9" '
    'x:orient="foreign" x:code="opaque"><x:paper/></w:pgSz>';
const _margins =
    '<w:pgMar w:top="1000" w:bottom="1200" w:left="1400" '
    'w:right="1600" w:header="500" w:footer="600"/>';

WmlDocument _document({
  String size = _size,
  String margins = _margins,
  String columns = '<w:cols w:num="2" w:space="360"/>',
  String extra = '',
  String settings = '',
  String attributes = '',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Original text')).build(),
  );
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}" $attributes><w:body>
<w:p><w:r><w:t>Original text</w:t></w:r></w:p>
<w:sectPr>$size$margins$columns<w:pgNumType w:start="7"/>
<x:metadata x:val="keep"/>$extra</w:sectPr></w:body></w:document>''');
  if (settings.isNotEmpty) {
    package.getPart('/word/settings.xml')!.writeText(
      '''
<w:settings xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}">$settings</w:settings>''',
    );
  }
  return WordDeserializer().read(package);
}

XmlElement _source(WmlSection section) =>
    XmlDocument.parse(section.sourceProperties!.xml).root!;

XmlElement _pageSize(WmlSection section) =>
    _source(section).firstChild('pgSz', namespaceUri: _w)!;

void _set(WmlDocument document, String orientation) => setWordPageOrientation(
  document,
  document.sections.single,
  orientation: orientation,
);

void _refuses(
  WmlDocument document, {
  String orientation = 'landscape',
  Matcher? failure,
}) {
  final section = document.sections.single;
  final size = section.pageSize;
  final margins = section.margins;
  final source = section.sourceProperties;
  final parts = <String, Uint8List>{
    for (final part in document.package?.parts ?? <PackagePart>[])
      part.uri: part.readBytes(),
  };
  expect(() => _set(document, orientation), failure ?? throwsUnsupportedError);
  expect(section.pageSize, same(size));
  expect(section.margins, same(margins));
  expect(section.sourceProperties, same(source));
  expect({
    for (final part in document.package?.parts ?? <PackagePart>[])
      part.uri: part.readBytes(),
  }, parts);
}

void main() {
  test(
    'selected DOCM section rotates dimensions and keeps opaque payloads',
    () {
      var document = WordDeserializer().readBytes(fixture.wordPageSetupInput());
      final before = fixture.wordPageSetupState(fixture.wordPageSetupInput());
      setWordPageOrientation(
        document,
        document.sections[0],
        orientation: 'landscape',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        expect(fixture.wordPageSetupState(bytes), [
          {...before[0], 'width': 792, 'height': 612},
          before[1],
          before[2],
        ]);
        final size = fixture
            .wordPageSetupSection(bytes, 0)
            .firstChild('pgSz', namespaceUri: _w)!;
        expect(size.getAttribute('orient', namespaceUri: _w), 'landscape');
        expect(size.getAttribute('code', namespaceUri: _w), '9');
        expect(
          size.getAttribute('w', namespaceUri: 'urn:word-page-setup-example'),
          'foreign-width',
        );
        expect(
          size.firstChild('paper', namespaceUri: 'urn:word-page-setup-example'),
          isNotNull,
        );
        fixture.assertWordPageSetupPackage(bytes);
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'same-value assignment owns orientation without changing dimensions',
    () {
      final document = _document(
        size: '<w:pgSz w:w="12240" w:h="15840" w:code="9"/>',
      );
      final size = document.sections.single.pageSize;
      final margins = document.sections.single.margins;
      _set(document, 'portrait');
      expect(document.sections.single.pageSize, same(size));
      expect(document.sections.single.margins, same(margins));
      final source = _pageSize(document.sections.single);
      expect(source.getAttribute('w', namespaceUri: _w), '12240');
      expect(source.getAttribute('h', namespaceUri: _w), '15840');
      expect(source.getAttribute('orient', namespaceUri: _w), 'portrait');
      expect(source.getAttribute('code', namespaceUri: _w), '9');
    },
  );

  test(
    'same-value sparse size materializes a fractional default at native precision',
    () {
      final document = _document(size: '<w:pgSz w:w="12240"/>');
      _set(document, 'portrait');
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final source = _pageSize(reopened.sections.single);
      expect(source.getAttribute('w', namespaceUri: _w), '12240');
      expect(source.getAttribute('h', namespaceUri: _w), '16838');
      expect(reopened.sections.single.pageSize.height, 841.9);
      expect(source.getAttribute('orient', namespaceUri: _w), 'portrait');
    },
  );

  test(
    'toggle resolves current orientation after earlier writes and reopens',
    () {
      var document = _document();
      for (var index = 0; index < 6; index++) {
        _set(document, 'toggle');
        final landscape = index.isEven;
        final section = document.sections.single;
        expect(section.pageSize.width, landscape ? 792 : 612);
        expect(section.pageSize.height, landscape ? 612 : 792);
        final bytes = WordSerializer().writeBytes(document);
        document = WordDeserializer().readBytes(bytes);
        final source = _pageSize(document.sections.single);
        expect(
          source.getAttribute('orient', namespaceUri: _w),
          landscape ? 'landscape' : 'portrait',
        );
        expect(source.getAttribute('code', namespaceUri: _w), '9');
        expect(source.getAttribute('orient', namespaceUri: _x), 'foreign');
        expect(source.getAttribute('code', namespaceUri: _x), 'opaque');
        expect(source.firstChild('paper', namespaceUri: _x), isNotNull);
        expect(document.sections.single.margins.top, 50);
        expect(document.sections.single.margins.right, 80);
        expect(document.sections.single.margins.header, 25);
        expect(document.sections.single.margins.footer, 30);
      }
    },
  );

  for (final initial in ['portrait', 'landscape']) {
    test(
      'square source $initial retains explicit state through same and toggle',
      () {
        var document = _document(
          size:
              '<w:pgSz w:w="12000" w:h="12000" w:orient="$initial" w:code="9"/>',
        );
        _set(document, initial);
        var expected = initial;
        for (var index = 0; index < 5; index++) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(
            _pageSize(
              document.sections.single,
            ).getAttribute('orient', namespaceUri: _w),
            expected,
          );
          _set(document, 'toggle');
          expected = expected == 'portrait' ? 'landscape' : 'portrait';
          expect(document.sections.single.pageSize.width, 600);
          expect(document.sections.single.pageSize.height, 600);
        }
      },
    );
  }

  test(
    'new square orientation survives serialization without losing other settings',
    () {
      var document = WmlDocument.empty(text: 'Fresh');
      final section = document.sections.single
        ..pageSize = const WmlPageSize(width: 600, height: 600)
        ..margins = const WmlPageMargins(left: 50, right: 60, header: 20)
        ..columnCount = 2
        ..columnSpace = 24
        ..differentFirstPage = true
        ..lineNumbers = true
        ..breakKind = WmlSectionBreakKind.oddPage;
      expect(section.sourceProperties, isNull);
      _set(document, 'landscape');
      expect(section.sourceProperties!.values.keys, ['pgSz']);
      setWordPageSetup(document, section, property: 'top', points: 40);
      setWordSectionStart(document, section, kind: 'evenPage');
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final current = document.sections.single;
        expect(
          _pageSize(current).getAttribute('orient', namespaceUri: _w),
          'landscape',
        );
        expect(current.pageSize.width, 600);
        expect(current.pageSize.height, 600);
        expect(current.margins.top, 40);
        expect(current.margins.left, 50);
        expect(current.margins.right, 60);
        expect(current.margins.header, 20);
        expect(current.margins.footer, 36);
        expect(current.columnCount, 2);
        expect(current.columnSpace, 24);
        expect(current.differentFirstPage, isTrue);
        expect(current.lineNumbers, isTrue);
        expect(current.breakKind, WmlSectionBreakKind.evenPage);
        expect(document.paragraphs.single.text, 'Fresh');
      }
    },
  );

  test('new square state toggles repeatedly before first serialization', () {
    final document = WmlDocument.empty(text: 'Fresh');
    document.sections.single.pageSize = const WmlPageSize(
      width: 600,
      height: 600,
    );
    for (var index = 0; index < 6; index++) {
      _set(document, 'toggle');
      final expected = index.isEven ? 'landscape' : 'portrait';
      expect(
        _pageSize(
          document.sections.single,
        ).getAttribute('orient', namespaceUri: _w),
        expected,
      );
    }
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      _pageSize(
        reopened.sections.single,
      ).getAttribute('orient', namespaceUri: _w),
      'portrait',
    );
  });

  test(
    'new near-square landscape uses exact dimensions rather than a tolerance',
    () {
      final document = WmlDocument.empty(text: 'Fresh');
      document.sections.single.pageSize = const WmlPageSize(
        width: 600.05,
        height: 600,
      );
      _set(document, 'portrait');
      expect(document.sections.single.pageSize.width, 600);
      expect(document.sections.single.pageSize.height, 600.05);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(reopened.sections.single.pageSize.height, 600.05);
      expect(
        _pageSize(
          reopened.sections.single,
        ).getAttribute('orient', namespaceUri: _w),
        'portrait',
      );
    },
  );

  test('missing native size is created from effective imported geometry', () {
    final document = _document(size: '');
    final original = document.sections.single.pageSize;
    _set(document, 'landscape');
    expect(
      document.sections.single.pageSize.width,
      pointsToTwips(original.height) / 20,
    );
    expect(
      document.sections.single.pageSize.height,
      pointsToTwips(original.width) / 20,
    );
    final source = _pageSize(document.sections.single);
    expect(
      source.getAttribute('w', namespaceUri: _w),
      '${pointsToTwips(original.height)}',
    );
    expect(
      source.getAttribute('h', namespaceUri: _w),
      '${pointsToTwips(original.width)}',
    );
    expect(source.getAttribute('orient', namespaceUri: _w), 'landscape');
  });

  for (final (name, width, height, expectedWidth, expectedHeight) in [
    ('default A4', 595.28, 841.89, 841.9, 595.3),
    ('custom fractional dimensions', 605.024, 800.026, 800.05, 605.0),
    ('fractional dimensions becoming square', 600.01, 600.02, 600.0, 600.0),
  ]) {
    test(
      '$name uses ordinary serializer twip precision before orientation',
      () {
        var document = WmlDocument.empty(text: 'Fresh');
        document.sections.single.pageSize = WmlPageSize(
          width: width,
          height: height,
        );
        _set(document, 'landscape');
        expect(document.sections.single.pageSize.width, expectedWidth);
        expect(document.sections.single.pageSize.height, expectedHeight);
        for (var cycle = 0; cycle < 3; cycle++) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(document.sections.single.pageSize.width, expectedWidth);
          expect(document.sections.single.pageSize.height, expectedHeight);
          expect(
            _pageSize(
              document.sections.single,
            ).getAttribute('orient', namespaceUri: _w),
            'landscape',
          );
          _set(document, 'landscape');
        }
      },
    );
  }

  test('dimension rounding cannot eliminate the page body', () {
    final document = WmlDocument.empty(text: 'Fresh');
    document.sections.single
      ..pageSize = const WmlPageSize(width: 600.01, height: 800)
      ..margins = const WmlPageMargins(left: 300, right: 300);
    _refuses(document, orientation: 'portrait', failure: throwsArgumentError);
  });

  test('margin rounding cannot eliminate the serialized page body', () {
    final document = WmlDocument.empty(text: 'Fresh');
    document.sections.single
      ..pageSize = const WmlPageSize(width: 600, height: 800)
      ..margins = const WmlPageMargins(left: 299.98, right: 299.98);
    _refuses(document, orientation: 'portrait', failure: throwsArgumentError);
  });

  test('column-gap rounding cannot eliminate serialized column text width', () {
    final document = WmlDocument.empty(text: 'Fresh');
    document.sections.single
      ..pageSize = const WmlPageSize(width: 600, height: 800)
      ..margins = const WmlPageMargins(left: 150, right: 150)
      ..columnCount = 3
      ..columnSpace = 149.99;
    _refuses(document, orientation: 'portrait', failure: throwsArgumentError);
  });

  for (final target in ['portrait', 'landscape', 'toggle']) {
    test('prior general geometry edits resolve before $target', () {
      final document = _document();
      native.applyStep(document, {
        'op': 'sectionFormat',
        'section': 0,
        'width': 900,
        'left': 60,
      });
      _set(document, target);
      final landscape = target == 'landscape';
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final section = reopened.sections.single;
      expect(section.pageSize.width, landscape ? 900 : 792);
      expect(section.pageSize.height, landscape ? 792 : 900);
      expect(section.margins.left, 60);
      expect(section.margins.right, 80);
      expect(_pageSize(section).getAttribute('code', namespaceUri: _w), '9');
      expect(
        _pageSize(section).getAttribute('orient', namespaceUri: _w),
        landscape ? 'landscape' : 'portrait',
      );
    });
  }

  test(
    'measurement after orientation selects custom paper but keeps orientation',
    () {
      final document = _document();
      _set(document, 'landscape');
      setWordPageSetup(
        document,
        document.sections.single,
        property: 'width',
        points: 800,
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(reopened.sections.single.pageSize.width, 800);
      expect(reopened.sections.single.pageSize.height, 612);
      expect(
        _pageSize(
          reopened.sections.single,
        ).getAttribute('code', namespaceUri: _w),
        isNull,
      );
      expect(
        _pageSize(
          reopened.sections.single,
        ).getAttribute('orient', namespaceUri: _w),
        'landscape',
      );
    },
  );

  test('pending near-square general geometry is refused before rotation', () {
    final document = _document();
    native.applyStep(document, {
      'op': 'sectionFormat',
      'section': 0,
      'width': 800.1,
      'height': 800,
    });
    for (final orientation in ['portrait', 'landscape', 'toggle']) {
      _refuses(document, orientation: orientation);
    }
  });

  test(
    'inconsistent width assignment is refused before a later orientation',
    () {
      final document = _document();
      setWordPageSetup(
        document,
        document.sections.single,
        property: 'width',
        points: 900,
      );
      _refuses(document);
    },
  );

  test(
    'repeated namespace collisions retain foreign attributes and children',
    () {
      var document = _document(
        size:
            '<pgSz xmlns="$_w" xmlns:w="$_x" qudsWord0="opaque" w:token="keep"><w:child/></pgSz>',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        _set(document, 'landscape');
        final first = document.sections.single.sourceProperties!.xml;
        for (var repeat = 0; repeat < 20; repeat++) {
          _set(document, 'landscape');
        }
        expect(document.sections.single.sourceProperties!.xml, first);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final size = _pageSize(document.sections.single);
        expect(size.getAttribute('orient', namespaceUri: _w), 'landscape');
        expect(size.getAttribute('token', namespaceUri: _x), 'keep');
        expect(size.firstChild('child', namespaceUri: _x), isNotNull);
        expect(
          size.attributes
              .singleWhere((a) => a.qualifiedName == 'qudsWord0')
              .value,
          'opaque',
        );
        expect(
          size.attributes.map((a) => a.qualifiedName).toSet(),
          hasLength(size.attributes.length),
        );
      }
    },
  );

  test('recorded prior orientation remains opaque history', () {
    final history =
        '<w:sectPrChange w:id="10" w:author="Author"><w:sectPr>'
        '<w:pgSz w:w="12000" w:h="16000" w:orient="legacy"/>'
        '<mc:AlternateContent><mc:Fallback/></mc:AlternateContent>'
        '</w:sectPr></w:sectPrChange>';
    var document = _document(extra: history);
    _set(document, 'landscape');
    document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    final change = _source(
      document.sections.single,
    ).firstChild('sectPrChange', namespaceUri: _w)!;
    final size = change
        .firstChild('sectPr', namespaceUri: _w)!
        .firstChild('pgSz', namespaceUri: _w)!;
    expect(size.getAttribute('orient', namespaceUri: _w), 'legacy');
    expect(size.getAttribute('w', namespaceUri: _w), '12000');
    expect(change.getAttribute('id', namespaceUri: _w), '10');
  });

  for (final (name, size) in [
    ('wide default portrait', '<w:pgSz w:w="15840" w:h="12240"/>'),
    (
      'wide explicit portrait',
      '<w:pgSz w:w="15840" w:h="12240" w:orient="portrait"/>',
    ),
    (
      'narrow explicit landscape',
      '<w:pgSz w:w="12240" w:h="15840" w:orient="landscape"/>',
    ),
    ('near-square default portrait', '<w:pgSz w:w="12001" w:h="12000"/>'),
    (
      'unknown orientation',
      '<w:pgSz w:w="12240" w:h="15840" w:orient="sideways"/>',
    ),
    (
      'wrong-case orientation',
      '<w:pgSz w:w="12240" w:h="15840" w:orient="Portrait"/>',
    ),
    ('duplicate size', '$_size$_size'),
    ('universal native size', '<w:pgSz w:w="8in" w:h="15840"/>'),
  ]) {
    test('$name is refused without mutation even for same-value portrait', () {
      _refuses(_document(size: size), orientation: 'portrait');
    });
  }

  test('pending model edit cannot hide inconsistent original orientation', () {
    final document = _document(size: '<w:pgSz w:w="15840" w:h="12240"/>');
    native.applyStep(document, {
      'op': 'sectionFormat',
      'section': 0,
      'width': 600,
      'height': 800,
    });
    _refuses(document);
  });

  for (final (name, document) in <(String, WmlDocument Function())>[
    ('gutter', () => _document(margins: '<w:pgMar w:gutter="100"/>')),
    (
      'custom columns',
      () =>
          _document(columns: '<w:cols w:num="2"><w:col w:w="1200"/></w:cols>'),
    ),
    ('mirror margins', () => _document(settings: '<w:mirrorMargins/>')),
    ('book fold', () => _document(settings: '<w:bookFoldPrinting/>')),
    (
      'alternate section',
      () => _document(
        extra:
            '<mc:AlternateContent><mc:Choice Requires="x"><w:pgSz w:w="12000"/></mc:Choice><mc:Fallback/></mc:AlternateContent>',
      ),
    ),
    (
      'ProcessContent identity',
      () => _document(
        attributes: 'mc:Ignorable="x" mc:ProcessContent="x:metadata"',
      ),
    ),
  ]) {
    test('$name is refused without mutation', () {
      _refuses(document());
    });
  }

  test('rotated page body must retain positive height', () {
    _refuses(
      _document(
        size: '<w:pgSz w:w="6000" w:h="16000"/>',
        margins:
            '<w:pgMar w:top="3600" w:bottom="3600" w:left="1000" w:right="1000"/>',
        columns: '<w:cols w:num="1"/>',
      ),
      failure: throwsArgumentError,
    );
  });

  test('rotated uniform columns must retain positive text width', () {
    _refuses(
      _document(
        size: '<w:pgSz w:w="16000" w:h="6000" w:orient="landscape"/>',
        margins:
            '<w:pgMar w:top="1000" w:bottom="1000" w:left="2000" w:right="2000"/>',
        columns: '<w:cols w:num="3" w:space="2000"/>',
      ),
      orientation: 'portrait',
      failure: throwsArgumentError,
    );
  });

  test('unsupported requested orientation fails before native mutation', () {
    _refuses(
      _document(),
      orientation: 'reverseLandscape',
      failure: throwsArgumentError,
    );
  });

  test(
    'nonfinite authored size is refused before a source snapshot is created',
    () {
      final document = WmlDocument.empty(text: 'Fresh');
      document.sections.single.pageSize = const WmlPageSize(width: double.nan);
      _refuses(document);
    },
  );
}
