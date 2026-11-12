import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source(String content) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" '
        'xmlns:m="${OfficeNamespaces.m}"><w:body>$content'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

XmlElement _body(OpcPackage package) => XmlDocument.parse(
  package.getPart('/word/document.xml')!.readText(),
).root!.firstChild('body')!;

Iterable<XmlElement> _all(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _all(child, name);
  }
}

const _begin = '<w:r><w:fldChar w:fldCharType="begin"/></w:r>';
const _instruction =
    '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h </w:instrText></w:r>';
const _separate = '<w:r><w:fldChar w:fldCharType="separate"/></w:r>';
const _end = '<w:r><w:fldChar w:fldCharType="end"/></w:r>';
const _title =
    '<w:p><w:pPr><w:pStyle w:val="TOCHeading"/></w:pPr><w:r><w:t>Contents</w:t></w:r></w:p>';
const _entry =
    '<w:hyperlink w:anchor="target"><w:r><w:rPr><w:b/></w:rPr><w:t>Heading</w:t></w:r></w:hyperlink>'
    '<w:r><w:rPr><w:i/><w:color w:val="228844"/></w:rPr><w:tab/><w:t>2</w:t></w:r>';

OpcPackage _tocSource({bool separateParagraphs = false, bool title = true}) {
  final package = _source(
    '${title ? _title : ''}'
    '${separateParagraphs ? '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr>$_begin$_instruction</w:p><w:p>$_separate</w:p>' : ''}'
    '<w:p><w:pPr><w:pStyle w:val="TOC1"/></w:pPr>'
    '${separateParagraphs ? '' : '$_begin$_instruction$_separate'}'
    '$_entry${separateParagraphs ? '' : _end}</w:p>'
    '${separateParagraphs ? '<w:p>$_end</w:p>' : ''}',
  );
  package.createPart(
    '/word/styles.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode(
      '<w:styles xmlns:w="${OfficeNamespaces.w}"><w:style w:type="paragraph" w:styleId="TOC1"><w:name w:val="TOC 1"/><w:rPr><w:color w:val="123456"/></w:rPr></w:style></w:styles>',
    ),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return package;
}

OpcPackage _settingsSource(
  String settings, {
  String uri = '/word/settings.xml',
}) {
  final package = _source('<w:p><w:r><w:t>Settings body</w:t></w:r></w:p>');
  package.createPart(
    uri,
    OfficeContentTypes.wordSettings,
    utf8.encode(settings),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        id: 'nativeSettings',
        type: RelationshipTypes.settings,
        target: uri == '/word/settings.xml'
            ? 'settings.xml'
            : '../settings/native.xml',
      );
  return package;
}

String _settings(String content) =>
    '<w:settings xmlns:w="${OfficeNamespaces.w}">$content</w:settings>';

OpcPackage _rangeTocSource({required bool control, bool includePage = true}) {
  final start = control
      ? '<w:sdt><w:sdtPr><w:id w:val="50"/><w:richText/></w:sdtPr><w:sdtContent>'
      : '<w:bookmarkStart w:id="50" w:name="Cache"/>';
  final end = control
      ? '</w:sdtContent></w:sdt>'
      : '<w:bookmarkEnd w:id="50"/>';
  return _source(
    '<w:p><w:pPr><w:pStyle w:val="TOC1"/></w:pPr>'
    '$_begin$_instruction$_separate$start<w:r><w:t>Heading</w:t></w:r>'
    '${includePage ? '' : end}<w:r><w:tab/><w:t>2</w:t></w:r>'
    '${includePage ? end : ''}$_end</w:p>',
  );
}

void main() {
  for (final scenario in [(false, false), (false, true), (true, true)]) {
    final (control, includesPage) = scenario;
    test(
      'native TOC ${control ? 'control' : 'bookmark'} keeps exact title/page range $includesPage through three saves',
      () async {
        var document = WordDeserializer().read(
          _rangeTocSource(control: control, includePage: includesPage),
        );
        final toc = WordToc.tocs(document).single;
        final item = toc.itemParagraphs.single;
        WmlRunEdit.replaceRange(item, 0, item.text.length, 'Edited 😀 title');
        toc.entries.single.pageNumber = 17;
        if (!control) {
          document.sections.single.blocks.add(
            WmlParagraph(
              inlines: [WmlRun(text: 'stale', fieldInstruction: ' REF Cache ')],
            ),
          );
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          final live = WordToc.tocs(document).single;
          final title = live.itemParagraphs.single;
          if (!control) {
            final range = WordBookmarks.byName(document, 'Cache')!;
            expect(
              range.text,
              includesPage ? 'Edited 😀 title\t17' : 'Edited 😀 title',
            );
            expect(range.startParagraph, same(title));
            expect(range.endParagraph, same(title));
            WordFields.update(document);
            expect(document.paragraphs.last.text, range.text);
          }
          document.sections.single.blocks[0] = WmlClone.toc(live);
          final package = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final body = _body(package);
          final paragraph = body.childrenNamed('p').first;
          if (control) {
            final native = paragraph.childrenNamed('sdt').single;
            expect(native.firstChild('sdtContent')!.text, 'Edited 😀 title17');
            expect(_all(native, 'tab'), hasLength(1));
          } else {
            expect(_all(paragraph, 'bookmarkStart'), hasLength(1));
            expect(_all(paragraph, 'bookmarkEnd'), hasLength(1));
            final children = paragraph.childElements.toList();
            final endpoint = children.indexWhere(
              (n) => n.localName == 'bookmarkEnd',
            );
            final page = children.indexWhere(
              (n) => n.firstChild('tab') != null,
            );
            expect(endpoint > page, includesPage);
          }
          document = WordDeserializer().read(package);
          expect(
            WordToc.tocs(document).single.itemParagraphs.single.text,
            'Edited 😀 title',
          );
        }
      },
    );
  }

  for (final control in [false, true]) {
    test(
      'native TOC ${control ? 'control' : 'bookmark'} regeneration fails before model or package mutation',
      () async {
        final document = WordDeserializer().read(
          _rangeTocSource(control: control),
        );
        final toc = WordToc.tocs(document).single;
        final presentation = toc.sourcePresentation;
        final paragraph = toc.itemParagraphs.single;
        final inlines = List<WmlInline>.of(paragraph.inlines);
        final before = document.package!.save();
        expect(() => WordToc.refresh(toc, document), throwsUnsupportedError);
        expect(toc.sourcePresentation, same(presentation));
        expect(toc.itemParagraphs.single, same(paragraph));
        expect(paragraph.inlines, orderedEquals(inlines));
        expect(document.package!.save(), orderedEquals(before));
        toc.maxLevel = 2;
        expect(() => WordSerializer().write(document), throwsUnsupportedError);
        await expectLater(
          OfficeIsolateSave.word(document),
          throwsUnsupportedError,
        );
        expect(document.package!.save(), orderedEquals(before));
        expect(toc.sourcePresentation, same(presentation));
        expect(paragraph.inlines, orderedEquals(inlines));
      },
    );
  }
  for (final useDefaultNamespace in [false, true]) {
    test(
      'settings edits preserve foreign w bindings with ${useDefaultNamespace ? 'default' : 'aliased'} Word elements',
      () {
        final prefix = useDefaultNamespace ? '' : 'q:';
        final source = _settingsSource(
          '<${prefix}settings xmlns="${OfficeNamespaces.w}" xmlns:q="${OfficeNamespaces.w}" xmlns:w="urn:foreign" '
          'xmlns:mc="${OfficeNamespaces.mc}" mc:Ignorable="w">'
          '<${prefix}documentProtection q:enforcement="0" w:enforcement="foreign" w:hash="retain"/>'
          '<${prefix}defaultTabStop q:val="360"/></${prefix}settings>',
        );
        var document = WordDeserializer().read(source);
        expect(document.trackRevisions || document.restrictEditing, isFalse);
        document
          ..trackRevisions = true
          ..restrictEditing = true;
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = WordSerializer().write(document);
          final root = XmlDocument.parse(
            saved.getPart('/word/settings.xml')!.readText(),
          ).root!;
          expect(
            root.attributes
                .singleWhere((a) => a.prefix == 'xmlns' && a.localName == 'w')
                .value,
            'urn:foreign',
          );
          final tracking = root.firstChild(
            'trackRevisions',
            namespaceUri: OfficeNamespaces.w,
          )!;
          expect(
            tracking.getAttribute('val', namespaceUri: OfficeNamespaces.w),
            '1',
          );
          final protection = root.firstChild(
            'documentProtection',
            namespaceUri: OfficeNamespaces.w,
          )!;
          expect(
            protection.getAttribute(
              'enforcement',
              namespaceUri: OfficeNamespaces.w,
            ),
            '1',
          );
          expect(
            protection.getAttribute('enforcement', namespaceUri: 'urn:foreign'),
            'foreign',
          );
          expect(
            protection.getAttribute('hash', namespaceUri: 'urn:foreign'),
            'retain',
          );
          expect(
            root
                .firstChild('defaultTabStop', namespaceUri: OfficeNamespaces.w)!
                .getAttribute('val', namespaceUri: OfficeNamespaces.w),
            '360',
          );
          expect(
            root.firstChild('trackRevisions', namespaceUri: 'urn:foreign'),
            isNull,
          );
          document = WordDeserializer().read(saved);
          expect(document.trackRevisions && document.restrictEditing, isTrue);
        }
      },
    );
  }
  for (final inline in [false, true]) {
    test('native ${inline ? 'inline' : 'display'} math keeps its wrapper '
        'through clone and three saves', () async {
      const math = '<m:oMath><m:r><m:t>x+1</m:t></m:r></m:oMath>';
      var document = WordDeserializer().read(
        _source(
          '<w:p>${inline ? math : '<m:oMathPara>$math</m:oMathPara>'}</w:p>',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final equation = document.sections.single.blocks.single as WmlEquation;
        expect(
          equation.math.display,
          inline ? OmmlDisplay.inline : OmmlDisplay.display,
        );
        document.sections.single.blocks[0] = WmlClone.equation(equation);
        final bytes = await OfficeIsolateSave.word(document);
        final package = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(
          package.getPart('/word/document.xml')!.readText(),
        ).root!;
        final paragraph = root.firstChild('body')!.firstChild('p')!;
        expect(paragraph.firstChild('oMath') != null, inline);
        expect(paragraph.firstChild('oMathPara') != null, !inline);
        expect(
          inline
              ? paragraph.firstChild('oMath')!.text
              : paragraph.firstChild('oMathPara')!.firstChild('oMath')!.text,
          'x+1',
        );
        document = WordDeserializer().read(package);
      }
    });
  }

  for (final separate in [false, true]) {
    test(
      'native TOC ${separate ? 'separate' : 'shared'} field paragraphs '
      'retain omission, rich suffix and live edits for three saves',
      () async {
        var document = WordDeserializer().read(
          _tocSource(separateParagraphs: separate),
        );
        var toc = WordToc.tocs(document).single;
        toc.titleParagraph.inlines.whereType<WmlRun>().single.text =
            'Live contents';
        toc.itemParagraphs.single.inlines.whereType<WmlRun>().single
          ..text = 'Edited heading'
          ..properties.color = 'AA0022';
        toc.entries.single.pageNumber = 17;
        for (var cycle = 0; cycle < 3; cycle++) {
          toc = WordToc.tocs(document).single;
          document.sections.single.blocks[0] = WmlClone.toc(toc);
          final package = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final paragraphs = _body(package).childrenNamed('p');
          expect(paragraphs, hasLength(separate ? 5 : 2));
          expect(paragraphs.first.text, 'Live contents');
          expect(
            _all(
              _body(package),
              'tab',
            ).where((n) => n.parent?.localName == 'tabs'),
            isEmpty,
          );
          final item = paragraphs.singleWhere(
            (p) => p.text.contains('Edited heading'),
          );
          expect(item.text, contains('Edited heading17'));
          final suffix = item
              .childrenNamed('r')
              .singleWhere((r) => r.firstChild('tab') != null);
          expect(suffix.firstChild('rPr')!.firstChild('i'), isNotNull);
          expect(
            suffix.firstChild('rPr')!.firstChild('color')!.getAttribute('val'),
            '228844',
          );
          expect(suffix.firstChild('rPr')!.firstChild('rFonts'), isNull);
          expect(_all(_body(package), 'instrText').map((n) => n.text), [
            ' TOC \\o "1-3" \\h ',
          ]);
          final boundaries = [
            for (var index = 0; index < paragraphs.length; index++)
              for (final field in _all(paragraphs[index], 'fldChar'))
                (index, field.getAttribute('fldCharType')),
          ];
          expect(
            boundaries,
            separate
                ? [(1, 'begin'), (2, 'separate'), (4, 'end')]
                : [(1, 'begin'), (1, 'separate'), (1, 'end')],
          );
          document = WordDeserializer().read(package);
        }
      },
    );
  }

  test('native TOC without a title does not acquire an invented heading', () {
    final document = WordDeserializer().read(_tocSource(title: false));
    final package = WordSerializer().write(document);
    expect(_body(package).childrenNamed('p'), hasLength(1));
    expect(_body(package).text, isNot(contains('Table of Contents')));
  });

  test(
    'TOC setting changes and explicit refresh select generated presentation',
    () {
      final document = WordDeserializer().read(_tocSource());
      final toc = WordToc.tocs(document).single;
      toc.showPageNumbers = false;
      var package = WordSerializer().write(document);
      expect(_all(_body(package), 'instrText').single.text, contains('\\n'));
      expect(_all(_body(package), 'tab'), isEmpty);
      expect(_body(package).childrenNamed('p'), hasLength(4));
      toc.showPageNumbers = true;
      document.sections.single.blocks.add(
        WmlParagraph(
          properties: WmlParagraphProps(styleId: 'Heading1', headingLevel: 1),
          inlines: [WmlRun(text: 'Replacement heading')],
        ),
      );
      WordToc.refresh(toc, document);
      expect(toc.sourcePresentation, isNull);
      package = WordSerializer().write(document);
      expect(
        _all(_body(package), 'tab').where((n) => n.parent?.localName == 'tabs'),
        hasLength(1),
      );
      expect(_body(package).text, contains('Replacement heading'));
    },
  );

  for (final sourceProperties in [
    '<wps:bodyPr/>',
    '<wps:bodyPr lIns="0" tIns="0" rIns="0" bIns="0"/>',
    '<wps:bodyPr lIns="127000" bIns="63500" vert="vert" anchor="ctr"><a:noAutofit/></wps:bodyPr>',
  ]) {
    test(
      'native frame insets and host properties survive clone and three saves: $sourceProperties',
      () async {
        final package = OpcPackage.create(OpcPackageKind.word);
        package
            .getPart('/word/document.xml')!
            .writeText(
              File('test/fixtures/fidelity/frame_wrap_source.xml')
                  .readAsStringSync()
                  .replaceFirst('<wps:bodyPr/>', sourceProperties),
            );
        var document = WordDeserializer().read(package);
        final expected = sourceProperties.contains('lIns="0"')
            ? [0.0, 0.0, 0.0, 0.0]
            : sourceProperties.contains('127000')
            ? [10.0, 3.6, 7.2, 5.0]
            : [7.2, 3.6, 7.2, 3.6];
        for (var cycle = 0; cycle < 3; cycle++) {
          final frame = document.sections.single.blocks.first as WmlFrame;
          expect([
            frame.insetLeft,
            frame.insetTop,
            frame.insetRight,
            frame.insetBottom,
          ], expected);
          document.sections.single.blocks[0] = WmlClone.frame(frame);
          final saved = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final nativeBody = _all(_body(saved), 'bodyPr').single;
          final originalBody = XmlDocument.parse(sourceProperties).root!;
          expect(
            nativeBody.attributes
                .where((a) => a.prefix != 'xmlns')
                .map((a) => (a.localName, a.value)),
            originalBody.attributes.map((a) => (a.localName, a.value)),
          );
          expect(
            nativeBody.childElements.map((e) => e.localName),
            originalBody.childElements.map((e) => e.localName),
          );
          expect(
            _body(saved).childrenNamed('p').first.firstChild('pPr'),
            isNull,
          );
          final fallback = _all(
            _body(saved),
            'textbox',
          ).single.getAttribute('inset');
          final nativeInsets = fallback!.split(',');
          expect(nativeInsets.every((v) => v.endsWith('pt')), isTrue);
          expect(
            nativeInsets.map((v) => double.parse(v.substring(0, v.length - 2))),
            expected,
          );
          document = WordDeserializer().read(saved);
        }
      },
    );
  }

  const originalLine =
      '<a:ln><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill></a:ln>';
  for (final sourceLine in [
    '',
    originalLine,
    '<a:ln w="38100" cap="rnd" cmpd="sng" algn="ctr"><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill><a:prstDash val="dash"/><a:round/></a:ln>',
  ]) {
    test(
      'native frame line omissions and properties survive clone, color edit and three saves: $sourceLine',
      () async {
        final source = OpcPackage.create(OpcPackageKind.word);
        source
            .getPart('/word/document.xml')!
            .writeText(
              File(
                'test/fixtures/fidelity/frame_wrap_source.xml',
              ).readAsStringSync().replaceFirst(originalLine, sourceLine),
            );
        var document = WordDeserializer().read(source);
        for (var cycle = 0; cycle < 3; cycle++) {
          final frame = document.sections.single.blocks.first as WmlFrame;
          if (cycle == 1) frame.strokeColor = 'AA1122';
          document.sections.single.blocks[0] = WmlClone.frame(frame);
          final saved = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final lines = _all(_body(saved), 'ln').toList();
          if (cycle == 0 && sourceLine.isEmpty) {
            expect(lines, isEmpty);
          } else {
            final line = lines.single;
            final explicitWidth = sourceLine.contains('38100');
            expect(line.getAttribute('w'), explicitWidth ? '38100' : null);
            expect(line.getAttribute('cap'), explicitWidth ? 'rnd' : null);
            expect(line.getAttribute('cmpd'), explicitWidth ? 'sng' : null);
            expect(line.getAttribute('algn'), explicitWidth ? 'ctr' : null);
            expect(
              line.firstChild('prstDash')?.getAttribute('val'),
              explicitWidth ? 'dash' : null,
            );
            expect(line.firstChild('round') != null, explicitWidth);
            expect(
              line
                  .firstChild('solidFill')!
                  .firstChild('srgbClr')!
                  .getAttribute('val'),
              cycle == 0 ? '355C7D' : 'AA1122',
            );
            expect(
              _all(_body(saved), 'rect').single.getAttribute('strokeweight'),
              explicitWidth ? '3pt' : null,
            );
          }
          document = WordDeserializer().read(saved);
        }
      },
    );
  }

  test('new frame native insets match the eight-point editor default', () {
    final frame = WmlFrame(
      blocks: [
        WmlParagraph(inlines: [WmlRun(text: 'New frame')]),
      ],
    );
    final package = WordSerializer().write(
      WmlDocument(
        sections: [
          WmlSection(blocks: [frame]),
        ],
      ),
    );
    final body = _all(_body(package), 'bodyPr').single;
    for (final name in ['lIns', 'tIns', 'rIns', 'bIns']) {
      expect(body.getAttribute(name), '101600');
    }
    final imported =
        WordDeserializer().read(package).sections.single.blocks.first
            as WmlFrame;
    expect(
      [
        imported.insetLeft,
        imported.insetTop,
        imported.insetRight,
        imported.insetBottom,
      ],
      [8.0, 8.0, 8.0, 8.0],
    );
  });

  test(
    'frame inset edit changes only its attribute and retains native host spacing',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File(
              'test/fixtures/fidelity/frame_wrap_source.xml',
            ).readAsStringSync().replaceFirst(
              '<w:p><w:r><w:drawing>',
              '<w:p><w:pPr><w:spacing w:after="160" w:line="300"/></w:pPr><w:r><w:drawing>',
            ),
          );
      final document = WordDeserializer().read(package);
      final frame = document.sections.single.blocks.first as WmlFrame;
      frame.insetLeft = 12;
      final saved = WordSerializer().write(document);
      final body = _all(_body(saved), 'bodyPr').single;
      expect(body.getAttribute('lIns'), '152400');
      expect(body.getAttribute('rIns'), isNull);
      expect(body.getAttribute('tIns'), isNull);
      expect(body.getAttribute('bIns'), isNull);
      final spacing = _body(
        saved,
      ).childrenNamed('p').first.firstChild('pPr')!.firstChild('spacing')!;
      expect(spacing.getAttribute('after'), '160');
      expect(spacing.getAttribute('line'), '300');
      expect(spacing.getAttribute('lineRule'), isNull);
    },
  );

  for (final existing in [false, true]) {
    test(
      '${existing ? 'empty' : 'absent'} native settings retain their distinction through three saves',
      () async {
        final source = existing
            ? _settingsSource(_settings(''))
            : _source('<w:p><w:r><w:t>Body</w:t></w:r></w:p>');
        var document = WordDeserializer().read(source);
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          expect(saved.getPart('/word/settings.xml') != null, existing);
          expect(
            saved
                    .relationshipsFor('/word/document.xml')
                    .firstByType(RelationshipTypes.settings) !=
                null,
            existing,
          );
          if (existing) {
            expect(
              saved.getPart('/word/settings.xml')!.readText(),
              _settings(''),
            );
          }
          document = WordDeserializer().read(saved);
        }
      },
    );
  }

  test(
    'owned settings parse their own flags and preserve native values and part ownership for three saves',
    () async {
      final settings = _settings(
        '<w:trackRevisions/>'
        '<w:documentProtection w:edit="readOnly" w:enforcement="0" w:cryptProviderType="rsaFull" w:cryptAlgorithmClass="hash" w:cryptAlgorithmType="typeAny" w:cryptAlgorithmSid="14" w:cryptSpinCount="100000" w:hash="AAAA" w:salt="AQID"/>'
        '<w:defaultTabStop w:val="360"/><w:evenAndOddHeaders w:val="off"/>'
        '<w:compat><w:doNotUseHTMLParagraphAutoSpacing w:val="0"/></w:compat>',
      );
      final source = _settingsSource(settings, uri: '/settings/native.xml');
      source.createPart(
        '/word/settings.xml',
        OfficeContentTypes.wordSettings,
        utf8.encode(_settings('<w:zoom w:percent="125"/>')),
      );
      var document = WordDeserializer().read(source);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.trackRevisions, isTrue);
        expect(document.restrictEditing, isFalse);
        expect(document.sections.single.differentOddEven, isFalse);
        final saved = OpcPackage.openBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(saved.getPart('/settings/native.xml')!.readText(), settings);
        expect(
          saved.getPart('/word/settings.xml')!.readText(),
          _settings('<w:zoom w:percent="125"/>'),
        );
        expect(
          saved
              .relationshipsFor('/word/document.xml')
              .firstByType(RelationshipTypes.settings)!
              .id,
          'nativeSettings',
        );
        document = WordDeserializer().read(saved);
      }
    },
  );

  test(
    'live settings edits preserve protection metadata and insert owned nodes in schema order',
    () {
      final source = _settingsSource(
        _settings(
          '<w:zoom w:percent="125"/>'
          '<w:documentProtection w:enforcement="0" w:edit="readOnly" w:hash="AAAA" w:salt="AQID"/>'
          '<w:defaultTabStop w:val="360"/><w:compat><w:doNotUseHTMLParagraphAutoSpacing w:val="0"/></w:compat>',
        ),
      );
      var document = WordDeserializer().read(source);
      document
        ..trackRevisions = true
        ..restrictEditing = true;
      document.sections.single.differentOddEven = true;
      for (var cycle = 0; cycle < 3; cycle++) {
        final package = WordSerializer().write(document);
        final settings = XmlDocument.parse(
          package.getPart('/word/settings.xml')!.readText(),
        ).root!;
        expect(settings.childElements.map((e) => e.localName), [
          'zoom',
          'trackRevisions',
          'documentProtection',
          'defaultTabStop',
          'evenAndOddHeaders',
          'compat',
        ]);
        final protection = settings.firstChild('documentProtection')!;
        expect(protection.getAttribute('enforcement'), '1');
        expect(protection.getAttribute('hash'), 'AAAA');
        expect(protection.getAttribute('salt'), 'AQID');
        expect(
          settings.firstChild('defaultTabStop')!.getAttribute('val'),
          '360',
        );
        document = WordDeserializer().read(package);
        expect(
          document.trackRevisions &&
              document.restrictEditing &&
              document.sections.single.differentOddEven,
          isTrue,
        );
      }
      document
        ..trackRevisions = false
        ..restrictEditing = false;
      document.sections.single.differentOddEven = false;
      final saved = WordSerializer().write(document);
      final settings = XmlDocument.parse(
        saved.getPart('/word/settings.xml')!.readText(),
      ).root!;
      expect(settings.firstChild('trackRevisions')!.getAttribute('val'), '0');
      expect(
        settings.firstChild('documentProtection')!.getAttribute('enforcement'),
        '0',
      );
      expect(
        settings.firstChild('documentProtection')!.getAttribute('hash'),
        'AAAA',
      );
      expect(
        settings.firstChild('evenAndOddHeaders')!.getAttribute('val'),
        '0',
      );
    },
  );

  test('requested live settings create an owned settings part when absent', () {
    final document = WordDeserializer().read(_source('<w:p/>'))
      ..trackRevisions = true;
    final package = WordSerializer().write(document);
    expect(package.getPart('/word/settings.xml'), isNotNull);
    expect(
      package
          .relationshipsFor('/word/document.xml')
          .firstByType(RelationshipTypes.settings),
      isNotNull,
    );
    expect(WordDeserializer().read(package).trackRevisions, isTrue);
  });
}
