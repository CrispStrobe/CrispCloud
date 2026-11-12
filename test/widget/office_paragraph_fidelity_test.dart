// Exercise the host's actual paragraph dialog/native-menu action. The source
// XML and expected values are authored independently of Quds serialization.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _fixture() {
  final parts = <String, String>{
    '[Content_Types].xml': '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
</Types>''',
    '_rels/.rels':
        '<Relationships xmlns="$_pr"><Relationship Id="office" Type="$_r/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels':
        '''<Relationships xmlns="$_pr">
<Relationship Id="styles" Type="$_r/styles" Target="styles.xml"/>
<Relationship Id="header" Type="$_r/header" Target="header1.xml"/>
</Relationships>''',
    'word/styles.xml': '''<w:styles xmlns:w="$_w">
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ImportedBody"><w:name w:val="Imported body"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr></w:style>
</w:styles>''',
    'word/document.xml': '''<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>
<w:p><w:pPr><w:pStyle w:val="ImportedBody"/><w:tabs><w:tab w:val="decimal" w:leader="dot" w:pos="1447"/><w:tab w:val="right" w:leader="hyphen" w:pos="2893"/></w:tabs><w:spacing w:before="65" w:after="145" w:line="301" w:lineRule="auto"/><w:ind w:left="247" w:right="-31" w:firstLine="15"/></w:pPr><w:r><w:t>First paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:tabs><w:tab w:val="right" w:leader="underscore" w:pos="1447"/></w:tabs><w:spacing w:before="40" w:after="320"/><w:ind w:left="500"/></w:pPr><w:r><w:t>Second paragraph</w:t></w:r></w:p>
<w:sectPr><w:headerReference w:type="default" r:id="header"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1531" w:bottom="1441" w:left="1453" w:header="725" w:footer="715" w:gutter="33"/></w:sectPr>
</w:body></w:document>''',
    'word/header1.xml':
        '''<w:hdr xmlns:w="$_w"><w:p><w:pPr><w:tabs><w:tab w:val="center" w:leader="dot" w:pos="2205"/></w:tabs><w:spacing w:before="25" w:after="50"/><w:ind w:left="725"/></w:pPr><w:r><w:t>Header paragraph</w:t></w:r></w:p></w:hdr>''',
  };
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

xml.XmlDocument _part(Uint8List bytes, String name) => xml.XmlDocument.parse(
  utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.content),
);

List<xml.XmlElement> _paragraphs(Uint8List bytes) =>
    _part(bytes, 'word/document.xml')
        .findAllElements('body', namespace: _w)
        .single
        .findElements('p', namespace: _w)
        .toList();

String? _attribute(
  xml.XmlElement paragraph,
  String property,
  String attribute,
) => paragraph
    .findElements('pPr', namespace: _w)
    .single
    .findElements(property, namespace: _w)
    .single
    .getAttribute(attribute, namespace: _w);

void _expectTabs(
  xml.XmlElement paragraph,
  List<(String, String, String)> expected,
) {
  final tabs = paragraph
      .findAllElements('tab', namespace: _w)
      .map(
        (tab) => (
          tab.getAttribute('pos', namespace: _w),
          tab.getAttribute('val', namespace: _w),
          tab.getAttribute('leader', namespace: _w) ?? 'none',
        ),
      )
      .toList();
  expect(tabs, expected);
}

void _expectBody(Uint8List bytes, {bool zeroSpacing = false}) {
  final paragraphs = _paragraphs(bytes);
  expect(paragraphs, hasLength(2));
  expect(_attribute(paragraphs[0], 'ind', 'left'), '247');
  expect(_attribute(paragraphs[0], 'ind', 'right'), '-31');
  expect(_attribute(paragraphs[0], 'ind', 'firstLine'), '15');
  expect(_attribute(paragraphs[1], 'ind', 'left'), '500');
  expect(
    _attribute(paragraphs[0], 'spacing', 'before'),
    zeroSpacing ? '0' : '65',
  );
  expect(
    _attribute(paragraphs[0], 'spacing', 'after'),
    zeroSpacing ? '0' : '145',
  );
  expect(
    _attribute(paragraphs[1], 'spacing', 'before'),
    zeroSpacing ? '0' : '40',
  );
  expect(
    _attribute(paragraphs[1], 'spacing', 'after'),
    zeroSpacing ? '0' : '320',
  );
  expect(_attribute(paragraphs[0], 'spacing', 'line'), '301');
  _expectTabs(paragraphs[0], [
    ('1447', 'decimal', 'dot'),
    ('2893', 'right', 'hyphen'),
  ]);
  _expectTabs(paragraphs[1], [('1447', 'right', 'underscore')]);
}

void _expectLinkedText(Uint8List bytes, List<String> expected) {
  final paragraphs = _paragraphs(bytes);
  expect(paragraphs, hasLength(expected.length));
  final relationships = _part(
    bytes,
    'word/_rels/document.xml.rels',
  ).findAllElements('Relationship', namespace: _pr).toList();
  for (var i = 0; i < expected.length; i++) {
    final links = paragraphs[i]
        .findElements('hyperlink', namespace: _w)
        .toList();
    expect(links, isNotEmpty);
    expect(
      links
          .expand((link) => link.findAllElements('t', namespace: _w))
          .map((text) => text.innerText)
          .join(),
      expected[i],
    );
    for (final link in links) {
      final id = link.getAttribute('id', namespace: _r);
      final relationship = relationships.singleWhere(
        (entry) => entry.getAttribute('Id') == id,
      );
      expect(relationship.getAttribute('Type'), '$_r/hyperlink');
      expect(
        relationship.getAttribute('Target'),
        'https://example.org/reference#part',
      );
      expect(relationship.getAttribute('TargetMode'), 'External');
    }
  }
}

void _expectMargins(Uint8List bytes, {String left = '1453'}) {
  final margins = _part(bytes, 'word/document.xml')
      .findAllElements('sectPr', namespace: _w)
      .single
      .findElements('pgMar', namespace: _w)
      .single;
  for (final expected in {
    'top': '1440',
    'right': '1531',
    'bottom': '1441',
    'left': left,
    'header': '725',
    'footer': '715',
    'gutter': '33',
  }.entries) {
    expect(
      margins.getAttribute(expected.key, namespace: _w),
      expected.value,
      reason: 'Page margin ${expected.key}',
    );
  }
}

void _expectComment(Uint8List bytes) {
  _expectBody(bytes);
  final document = _part(bytes, 'word/document.xml');
  for (final name in [
    'commentRangeStart',
    'commentRangeEnd',
    'commentReference',
  ]) {
    expect(
      document
          .findAllElements(name, namespace: _w)
          .single
          .getAttribute('id', namespace: _w),
      '0',
    );
  }
  final comment = _part(
    bytes,
    'word/comments.xml',
  ).findAllElements('comment', namespace: _w).single;
  expect(comment.getAttribute('id', namespace: _w), '0');
  expect(comment.getAttribute('author', namespace: _w), 'Fidelity reviewer');
  expect(
    comment
        .findAllElements('t', namespace: _w)
        .map((text) => text.innerText)
        .join(),
    'Review this paragraph.',
  );
}

void _expectToc(Uint8List bytes) {
  final document = _part(bytes, 'word/document.xml');
  expect(
    document
        .findAllElements('instrText', namespace: _w)
        .map((instruction) => instruction.innerText.trim())
        .where((instruction) => instruction.startsWith('TOC ')),
    hasLength(1),
  );
  final bookmarks = document
      .findAllElements('bookmarkStart', namespace: _w)
      .map((bookmark) => bookmark.getAttribute('name', namespace: _w))
      .toSet();
  final entries = document
      .findAllElements('hyperlink', namespace: _w)
      .where((link) => link.getAttribute('anchor', namespace: _w) != null)
      .toList();
  expect(entries, isNotEmpty);
  expect(
    entries
        .expand((link) => link.findAllElements('t', namespace: _w))
        .map((text) => text.innerText)
        .join(),
    contains('First paragraph'),
  );
  for (final entry in entries) {
    expect(bookmarks, contains(entry.getAttribute('anchor', namespace: _w)));
  }
}

void _expectTable(Uint8List bytes) {
  final table = _part(
    bytes,
    'word/document.xml',
  ).findAllElements('tbl', namespace: _w).single;
  expect(table.findElements('tr', namespace: _w), hasLength(2));
  for (final row in table.findElements('tr', namespace: _w)) {
    expect(row.findElements('tc', namespace: _w), hasLength(3));
    for (final cell in row.findElements('tc', namespace: _w)) {
      expect(cell.findElements('p', namespace: _w), isNotEmpty);
    }
  }
}

xml.XmlElement _header(Uint8List bytes) {
  final id = _part(bytes, 'word/document.xml')
      .findAllElements('headerReference', namespace: _w)
      .single
      .getAttribute('id', namespace: _r);
  final target = _part(bytes, 'word/_rels/document.xml.rels')
      .findAllElements('Relationship', namespace: _pr)
      .singleWhere((relationship) => relationship.getAttribute('Id') == id)
      .getAttribute('Target')!;
  return _part(
    bytes,
    target.startsWith('/') ? target.substring(1) : 'word/$target',
  ).findAllElements('p', namespace: _w).single;
}

void _cycles(
  WordEditorController controller,
  String name,
  void Function(Uint8List) check,
) {
  var bytes = controller.saveBytes();
  for (var cycle = 1; cycle <= 3; cycle++) {
    check(bytes);
    final output = File('build/fidelity-host/$name-$cycle.docx');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes);
    if (cycle < 3) {
      final reopened = WordEditorController.fromBytes(bytes);
      try {
        bytes = reopened.saveBytes();
      } finally {
        reopened.dispose();
      }
    }
  }
}

Future<(WordEditorController, GlobalKey<OfficeEditorRibbonState>)> _host(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const config = OfficeSurfaceConfig(
    mode: OfficeInteractionMode.editing,
    autofocus: false,
    adaptiveChrome: false,
  );
  final controller = WordEditorController.fromBytes(_fixture(), config: config);
  addTearDown(controller.dispose);
  final key = GlobalKey<OfficeEditorRibbonState>();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: OfficeEditorRibbon(
          key: key,
          controller: controller,
          kind: OfficeEditorKind.word,
          config: config,
          onSave: () {},
          onClose: () {},
          onConfigChanged: (_) {},
          onFind: controller.requestFind,
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, key);
}

Future<void> _dialog(
  WidgetTester tester,
  GlobalKey<OfficeEditorRibbonState> key,
) async {
  key.currentState!.perform(OfficeEditorAction.paragraph);
  await tester.pumpAndSettle();
}

Future<void> _marginsDialog(
  WidgetTester tester,
  GlobalKey<OfficeEditorRibbonState> key,
) async {
  key.currentState!.perform(OfficeEditorAction.pageSetup);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(SimpleDialogOption, 'Margins'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _set(WidgetTester tester, String label, String value) async {
  final field = _field(label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unchanged paragraph dialog preserves fractions, tabs and clean state',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _dialog(tester, key);
      expect(
        tester.widget<TextField>(_field('Left indent (pt)')).controller!.text,
        '12.35',
      );
      expect(
        tester.widget<TextField>(_field('Space after (pt)')).controller!.text,
        '7.25',
      );
      await _apply(tester);
      expect(controller.isDirty, isFalse);
      _cycles(controller, 'paragraph-noop', _expectBody);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selected paragraph spacing edits preserve every other imported property',
    (tester) async {
      final (controller, key) = await _host(tester);
      controller.selectAll();
      await _dialog(tester, key);
      await _set(tester, 'Space before (pt)', '0');
      await _set(tester, 'Space after (pt)', '0');
      await _apply(tester);
      expect(
        controller.document.paragraphs.every(
          (p) =>
              p.properties.explicitSpacingBefore &&
              p.properties.explicitSpacingAfter,
        ),
        isTrue,
      );
      _cycles(
        controller,
        'paragraph-edit',
        (bytes) => _expectBody(bytes, zeroSpacing: true),
      );
      controller.undo();
      _expectBody(controller.saveBytes());
      controller.redo();
      _expectBody(controller.saveBytes(), zeroSpacing: true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('header paragraph dialog reads and edits the active story', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.beginHeaderFooterEdit(0, footer: false);
    await _dialog(tester, key);
    expect(
      tester.widget<TextField>(_field('Left indent (pt)')).controller!.text,
      '36.25',
    );
    expect(
      tester.widget<TextField>(_field('Space after (pt)')).controller!.text,
      '2.5',
    );
    await _set(tester, 'Space after (pt)', '4.75');
    await _apply(tester);
    _cycles(controller, 'header-paragraph-edit', (bytes) {
      _expectBody(bytes);
      final header = _header(bytes);
      expect(_attribute(header, 'ind', 'left'), '725');
      expect(_attribute(header, 'spacing', 'after'), '95');
      _expectTabs(header, [('2205', 'center', 'dot')]);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'invalid numeric input cannot erase tabs or poison paragraph geometry',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _dialog(tester, key);
      await _set(tester, 'Left indent (pt)', 'NaN');
      await _set(tester, 'Space before (pt)', '-10');
      await _set(tester, 'Space after (pt)', 'Infinity');
      await _set(tester, 'Line spacing', '0');
      await _set(tester, 'Tab stops (pt, comma separated)', '72.35, invalid');
      await _apply(tester);
      expect(controller.isDirty, isFalse);
      _expectBody(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'adding a tab preserves the leaders and alignment of existing stops',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _dialog(tester, key);
      await _set(
        tester,
        'Tab stops (pt, comma separated)',
        '72.35, 144.65, 216.25',
      );
      await _apply(tester);
      _expectTabs(_paragraphs(controller.saveBytes()).first, [
        ('1447', 'decimal', 'dot'),
        ('2893', 'right', 'hyphen'),
        ('4325', 'left', 'none'),
      ]);
      controller.undo();
      _expectBody(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ribbon remove-spacing commands retain explicit zero values', (
    tester,
  ) async {
    final (controller, _) = await _host(tester);
    controller.selectAll();
    await tester.tap(find.text('Layout').last);
    await tester.pumpAndSettle();
    for (final action in ['Remove before', 'Remove after']) {
      await tester.tap(find.text('Spacing').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }
    expect(
      controller.document.paragraphs.every(
        (p) =>
            p.properties.explicitSpacingBefore &&
            p.properties.explicitSpacingAfter,
      ),
      isTrue,
    );
    _expectBody(controller.saveBytes(), zeroSpacing: true);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ribbon identifies and applies imported paragraph styles by ID', (
    tester,
  ) async {
    final (controller, _) = await _host(tester);
    final gallery = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButton<String> && widget.value == 'ImportedBody',
    );
    expect(gallery, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: find.text('Imported body')),
      findsOneWidget,
    );
    controller.jumpToParagraph(1);
    await tester.pump();
    final normalGallery = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<String> && widget.value == 'Normal',
    );
    await tester.tap(normalGallery);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Imported body'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Imported body').last);
    await tester.pumpAndSettle();
    final bytes = controller.saveBytes();
    expect(_attribute(_paragraphs(bytes)[1], 'pStyle', 'val'), 'ImportedBody');
    expect(
      _part(bytes, 'word/styles.xml')
          .findAllElements('style', namespace: _w)
          .where(
            (style) =>
                style.getAttribute('styleId', namespace: _w) == 'ImportedBody',
          ),
      hasLength(1),
    );
    controller.undo();
    expect(controller.document.paragraphs.last.properties.styleId, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'host hyperlink action keeps selected text and participates in save history',
    (tester) async {
      final (controller, key) = await _host(tester);
      controller.selectAll();
      key.currentState!.perform(OfficeEditorAction.insertHyperlink);
      await tester.pumpAndSettle();
      await _set(tester, 'Address', 'https://example.org/reference#part');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Insert'));
      await tester.pumpAndSettle();
      expect(controller.isDirty, isTrue);
      _cycles(controller, 'hyperlink-selection', (bytes) {
        _expectBody(bytes);
        _expectLinkedText(bytes, ['First paragraph', 'Second paragraph']);
      });
      controller.undo();
      final undone = controller.saveBytes();
      _expectBody(undone);
      expect(
        _part(
          undone,
          'word/document.xml',
        ).findAllElements('hyperlink', namespace: _w),
        isEmpty,
      );
      controller.redo();
      _expectLinkedText(controller.saveBytes(), [
        'First paragraph',
        'Second paragraph',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('host hyperlink insertion restores both label and link on redo', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    key.currentState!.perform(OfficeEditorAction.insertHyperlink);
    await tester.pumpAndSettle();
    await _set(tester, 'Text', 'Read reference');
    await _set(tester, 'Address', 'https://example.org/reference#part');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Insert'));
    await tester.pumpAndSettle();
    expect(controller.isDirty, isTrue);
    for (var state = 0; state < 2; state++) {
      final linked = _paragraphs(controller.saveBytes()).first
          .findElements('hyperlink', namespace: _w)
          .single;
      expect(
        linked
            .findAllElements('t', namespace: _w)
            .map((text) => text.innerText)
            .join(),
        'Read reference',
      );
      if (state == 0) {
        controller.undo();
        expect(controller.document.paragraphs.first.text, 'First paragraph');
        expect(
          _part(
            controller.saveBytes(),
            'word/document.xml',
          ).findAllElements('hyperlink', namespace: _w),
          isEmpty,
        );
        controller.redo();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'page setup Apply retains exact imported margins and clean state',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _marginsDialog(tester, key);
      await _apply(tester);
      expect(controller.isDirty, isFalse);
      _cycles(controller, 'margins-noop', _expectMargins);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('page setup edits one margin and rejects nonfinite geometry', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    await _marginsDialog(tester, key);
    await _set(tester, 'Top (in)', 'NaN');
    await _set(tester, 'Bottom (in)', 'Infinity');
    await _set(tester, 'Left (in)', '0.875');
    await _apply(tester);
    _cycles(controller, 'margins-edit', (bytes) {
      _expectBody(bytes);
      _expectMargins(bytes, left: '1260');
    });
    controller.undo();
    _expectMargins(controller.saveBytes());
    controller.redo();
    _expectMargins(controller.saveBytes(), left: '1260');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'host comment dialog exports stable ranges and authors across history',
    (tester) async {
      final (controller, key) = await _host(tester);
      controller.jumpToParagraph(1);
      controller.selectParagraphAtCaret();
      key.currentState!.perform(OfficeEditorAction.insertComment);
      await tester.pumpAndSettle();
      await _set(tester, 'Author', 'Fidelity reviewer');
      await _set(tester, 'Comment', 'Review this paragraph.');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(controller.isDirty, isTrue);
      _cycles(controller, 'comment-action', _expectComment);
      controller.undo();
      expect(controller.document.comments, isEmpty);
      expect(
        _part(
          controller.saveBytes(),
          'word/document.xml',
        ).findAllElements('commentReference', namespace: _w),
        isEmpty,
      );
      controller.redo();
      _expectComment(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('host contents action exports a TOC linked to its heading', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    final gallery = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButton<String> && widget.value == 'ImportedBody',
    );
    await tester.tap(gallery);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Heading 1'),
      -100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Heading 1').last);
    await tester.pumpAndSettle();
    key.currentState!.perform(OfficeEditorAction.tableOfContents);
    await tester.pumpAndSettle();
    _cycles(controller, 'toc-action', _expectToc);
    controller.undo();
    expect(
      _part(controller.saveBytes(), 'word/document.xml')
          .findAllElements('instrText', namespace: _w)
          .where(
            (instruction) => instruction.innerText.trim().startsWith('TOC '),
          ),
      isEmpty,
    );
    controller.redo();
    _expectToc(controller.saveBytes());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'host table dialog exports the requested grid with undo and redo',
    (tester) async {
      final (controller, key) = await _host(tester);
      key.currentState!.perform(OfficeEditorAction.insertTable);
      await tester.pumpAndSettle();
      await _set(tester, 'Rows', '2');
      await _set(tester, 'Columns', '3');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Insert'));
      await tester.pumpAndSettle();
      _cycles(controller, 'table-action', _expectTable);
      controller.undo();
      expect(
        _part(
          controller.saveBytes(),
          'word/document.xml',
        ).findAllElements('tbl', namespace: _w),
        isEmpty,
      );
      controller.redo();
      _expectTable(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
