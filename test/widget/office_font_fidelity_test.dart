// Exercise actual host font controls with independently authored OOXML inputs.
// Expectations read the exported ZIP/XML directly, without using Quds import.
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
const _config = OfficeSurfaceConfig(
  mode: OfficeInteractionMode.editing,
  autofocus: false,
  adaptiveChrome: false,
);

Uint8List _fixture({int halfPoints = 21}) {
  final parts = <String, String>{
    '[Content_Types].xml': '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
</Types>''',
    '_rels/.rels':
        '<Relationships xmlns="$_pr"><Relationship Id="office" Type="$_r/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels':
        '<Relationships xmlns="$_pr"><Relationship Id="header" Type="$_r/header" Target="header1.xml"/></Relationships>',
    'word/document.xml':
        '''<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body><w:p>
<w:r><w:rPr><w:rFonts w:ascii="Garamond" w:hAnsi="Garamond" w:cs="Amiri"/><w:b/><w:i/><w:strike/><w:color w:val="204060"/><w:sz w:val="$halfPoints"/><w:highlight w:val="yellow"/><w:u w:val="double"/><w:vertAlign w:val="superscript"/></w:rPr><w:t xml:space="preserve">First run </w:t></w:r>
<w:r><w:rPr><w:rFonts w:ascii="Cambria" w:hAnsi="Cambria" w:cs="Noto Naskh Arabic"/><w:b w:val="0"/><w:i w:val="0"/><w:strike w:val="0"/><w:color w:val="AA4444"/><w:sz w:val="29"/><w:u w:val="dotted"/><w:vertAlign w:val="subscript"/></w:rPr><w:t>Second run</w:t></w:r>
</w:p><w:sectPr><w:headerReference w:type="default" r:id="header"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>''',
    'word/header1.xml':
        '''<w:hdr xmlns:w="$_w"><w:p><w:r><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Aref Ruqaa"/><w:color w:val="123456"/><w:sz w:val="19"/></w:rPr><w:t>Header run</w:t></w:r></w:p></w:hdr>''',
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

String? _value(xml.XmlElement properties, String property) => properties
    .findElements(property, namespace: _w)
    .firstOrNull
    ?.getAttribute('val', namespace: _w);

bool _on(xml.XmlElement properties, String property) {
  final element = properties.findElements(property, namespace: _w).firstOrNull;
  return element != null &&
      !{
        '0',
        'false',
        'off',
      }.contains(element.getAttribute('val', namespace: _w));
}

void _expectBody(
  Uint8List bytes, {
  int halfPoints = 21,
  int? sizeOverride,
  bool? italicOverride,
  String? familyOverride,
  String? underlineOverride,
}) {
  final body = _part(
    bytes,
    'word/document.xml',
  ).findAllElements('body', namespace: _w).single;
  final runs = body.findAllElements('r', namespace: _w).toList();
  expect(runs, hasLength(2));
  const texts = ['First run ', 'Second run'];
  const latinFonts = ['Garamond', 'Cambria'];
  const csFonts = ['Amiri', 'Noto Naskh Arabic'];
  const colors = ['204060', 'AA4444'];
  const underlines = ['double', 'dotted'];
  const vertical = ['superscript', 'subscript'];
  for (var index = 0; index < runs.length; index++) {
    final run = runs[index];
    expect(run.findElements('t', namespace: _w).single.innerText, texts[index]);
    final properties = run.findElements('rPr', namespace: _w).single;
    final fonts = properties.findElements('rFonts', namespace: _w).single;
    expect(
      fonts.getAttribute('ascii', namespace: _w),
      familyOverride ?? latinFonts[index],
    );
    expect(
      fonts.getAttribute('cs', namespace: _w),
      familyOverride ?? csFonts[index],
    );
    expect(
      _value(properties, 'sz'),
      '${sizeOverride ?? (index == 0 ? halfPoints : 29)}',
    );
    expect(_on(properties, 'b'), index == 0);
    expect(_on(properties, 'i'), italicOverride ?? index == 0);
    expect(_on(properties, 'strike'), index == 0);
    expect(_value(properties, 'color'), colors[index]);
    expect(_value(properties, 'highlight'), index == 0 ? 'yellow' : null);
    expect(_value(properties, 'u'), underlineOverride ?? underlines[index]);
    expect(_value(properties, 'vertAlign'), vertical[index]);
  }
}

void _expectHeader(Uint8List bytes, {bool italic = false}) {
  final document = _part(bytes, 'word/document.xml');
  final id = document
      .findAllElements('headerReference', namespace: _w)
      .single
      .getAttribute('id', namespace: _r);
  final target = _part(bytes, 'word/_rels/document.xml.rels')
      .findAllElements('Relationship', namespace: _pr)
      .singleWhere((relationship) => relationship.getAttribute('Id') == id)
      .getAttribute('Target')!;
  final header = _part(
    bytes,
    target.startsWith('/') ? target.substring(1) : 'word/$target',
  );
  final run = header.findAllElements('r', namespace: _w).single;
  expect(run.findElements('t', namespace: _w).single.innerText, 'Header run');
  final properties = run.findElements('rPr', namespace: _w).single;
  final fonts = properties.findElements('rFonts', namespace: _w).single;
  expect(fonts.getAttribute('ascii', namespace: _w), 'Georgia');
  expect(fonts.getAttribute('cs', namespace: _w), 'Aref Ruqaa');
  expect(_value(properties, 'sz'), '19');
  expect(_value(properties, 'color'), '123456');
  expect(_on(properties, 'i'), italic);
}

void _cycles(
  WordEditorController controller,
  String name,
  void Function(Uint8List bytes) check,
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

Widget _widget(
  WordEditorController controller,
  GlobalKey<OfficeEditorRibbonState> key,
) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: OfficeEditorRibbon(
      key: key,
      controller: controller,
      kind: OfficeEditorKind.word,
      config: controller.config,
      onSave: () {},
      onClose: () {},
      onConfigChanged: (_) {},
      onFind: controller.requestFind,
    ),
  ),
);

Future<(WordEditorController, GlobalKey<OfficeEditorRibbonState>)> _host(
  WidgetTester tester, {
  int halfPoints = 21,
}) async {
  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController.fromBytes(
    _fixture(halfPoints: halfPoints),
    config: _config,
  );
  addTearDown(controller.dispose);
  final key = GlobalKey<OfficeEditorRibbonState>();
  await tester.pumpWidget(_widget(controller, key));
  await tester.pump();
  return (controller, key);
}

Future<void> _dialog(
  WidgetTester tester,
  GlobalKey<OfficeEditorRibbonState> key,
) async {
  key.currentState!.perform(OfficeEditorAction.font);
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
  await tester.pumpAndSettle();
}

Finder _dialogText(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  for (final halfPoints in [21, 14, 288]) {
    testWidgets('font Apply preserves imported $halfPoints half-points', (
      tester,
    ) async {
      final (controller, key) = await _host(tester, halfPoints: halfPoints);
      final size = halfPoints / 2;
      final label = size == size.roundToDouble()
          ? size.toInt().toString()
          : size.toString();
      // The ribbon and dialog both report the authored size, including sizes
      // outside the preset range. Merely opening and applying is not an edit.
      expect(find.text(label), findsOneWidget);
      await _dialog(tester, key);
      final field = tester.widget<DropdownButtonFormField<double>>(
        find.byType(DropdownButtonFormField<double>),
      );
      expect(field.initialValue, size);
      await _apply(tester);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      _cycles(controller, 'font-noop-$halfPoints', (bytes) {
        _expectBody(bytes, halfPoints: halfPoints);
        _expectHeader(bytes);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('font italic edit preserves mixed run properties and undo', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    await tester.tap(_dialogText('I'));
    await _apply(tester);
    expect(controller.isDirty, isTrue);
    _expectBody(controller.saveBytes(), italicOverride: true);
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _cycles(controller, 'font-italic', (bytes) {
      _expectBody(bytes, italicOverride: true);
      _expectHeader(bytes);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('untouched font Apply preserves a mixed selection', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    await _apply(tester);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    _expectBody(controller.saveBytes());
    _expectHeader(controller.saveBytes());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit current font family normalizes a mixed selection', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    expect(_dialogText('Cambria'), findsOneWidget);
    await tester.tap(find.byTooltip('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambria').last);
    await tester.pumpAndSettle();
    await _apply(tester);
    expect(controller.isDirty, isTrue);
    _cycles(controller, 'font-family-current', (bytes) {
      _expectBody(bytes, familyOverride: 'Cambria');
      _expectHeader(bytes);
    });
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _expectBody(controller.saveBytes(), familyOverride: 'Cambria');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit current half-point size normalizes a mixed selection', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    final sizeField = find.byType(DropdownButtonFormField<double>);
    expect(
      tester.widget<DropdownButtonFormField<double>>(sizeField).initialValue,
      14.5,
    );
    await tester.tap(sizeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('14.5').last);
    await tester.pumpAndSettle();
    await _apply(tester);
    expect(controller.isDirty, isTrue);
    _cycles(controller, 'font-size-current', (bytes) {
      _expectBody(bytes, sizeOverride: 29);
      _expectHeader(bytes);
    });
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _expectBody(controller.saveBytes(), sizeOverride: 29);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit current underline normalizes only that property', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    await tester.tap(find.byType(DropdownButtonFormField<WmlUnderline>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dotted').last);
    await tester.pumpAndSettle();
    await _apply(tester);
    _cycles(controller, 'font-underline-current', (bytes) {
      _expectBody(bytes, underlineOverride: 'dotted');
      _expectHeader(bytes);
    });
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _expectBody(controller.saveBytes(), underlineOverride: 'dotted');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('font size edit changes only size across selected runs', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18').last);
    await tester.pumpAndSettle();
    await _apply(tester);
    _cycles(controller, 'font-size', (bytes) {
      _expectBody(bytes, sizeOverride: 36);
      _expectHeader(bytes);
    });
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _expectBody(controller.saveBytes(), sizeOverride: 36);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('font family edit preserves all unrelated run properties', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.selectAll();
    await _dialog(tester, key);
    await tester.tap(find.byTooltip('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arial').last);
    await tester.pumpAndSettle();
    await _apply(tester);
    _cycles(controller, 'font-family', (bytes) {
      _expectBody(bytes, familyOverride: 'Arial');
      _expectHeader(bytes);
    });
    controller.undo();
    _expectBody(controller.saveBytes());
    controller.redo();
    _expectBody(controller.saveBytes(), familyOverride: 'Arial');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('font dialog edits only the active header story', (tester) async {
    final (controller, key) = await _host(tester);
    controller.beginHeaderFooterEdit(0, footer: false);
    await _dialog(tester, key);
    expect(_dialogText('Georgia'), findsOneWidget);
    await tester.tap(_dialogText('I'));
    await _apply(tester);
    _cycles(controller, 'header-font', (bytes) {
      _expectBody(bytes);
      _expectHeader(bytes, italic: true);
    });
    controller.undo();
    _expectHeader(controller.saveBytes());
    controller.redo();
    _expectHeader(controller.saveBytes(), italic: true);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'font result cannot move from an open header dialog to the body',
    (tester) async {
      final (controller, key) = await _host(tester);
      controller.beginHeaderFooterEdit(0, footer: false);
      await _dialog(tester, key);
      await tester.tap(_dialogText('I'));
      controller.endHeaderFooterEdit();
      await _apply(tester);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      _expectBody(controller.saveBytes());
      _expectHeader(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('font result cannot follow a changed selection in one document', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    await _dialog(tester, key);
    await tester.tap(_dialogText('I'));
    controller.selectAll();
    await _apply(tester);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    _expectBody(controller.saveBytes());
    _expectHeader(controller.saveBytes());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'font result cannot overwrite a newer revision at the same caret',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _dialog(tester, key);
      await tester.tap(_dialogText('I'));
      controller.applyRunFormat((properties) => properties.color = '556677');
      final revision = controller.contentRevision;
      final before = _part(
        controller.saveBytes(),
        'word/document.xml',
      ).toXmlString();
      await _apply(tester);
      expect(controller.contentRevision, revision);
      expect(
        _part(controller.saveBytes(), 'word/document.xml').toXmlString(),
        before,
      );
      // The external color edit is still the only undo entry.
      controller.undo();
      _expectBody(controller.saveBytes());
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'font result survives paint-only refreshes at its original target',
    (tester) async {
      final (controller, key) = await _host(tester);
      await _dialog(tester, key);
      await tester.tap(_dialogText('I'));
      controller.refreshMetrics();
      await _apply(tester);
      expect(controller.isDirty, isTrue);
      _expectBody(controller.saveBytes(), italicOverride: false);
      _expectHeader(controller.saveBytes());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('font cancel and controller replacement leave documents clean', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    await _dialog(tester, key);
    await tester.tap(_dialogText('I'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.isDirty, isFalse);
    _expectBody(controller.saveBytes());

    await _dialog(tester, key);
    await tester.tap(_dialogText('I'));
    final replacement = WordEditorController.fromBytes(
      _fixture(),
      config: _config,
    );
    addTearDown(replacement.dispose);
    // Reuse the ribbon's State while the dialog is still open. A result
    // collected for an old document must not modify the replacement.
    await tester.pumpWidget(_widget(replacement, key));
    await _apply(tester);
    expect(controller.isDirty, isFalse);
    expect(replacement.isDirty, isFalse);
    _expectBody(controller.saveBytes());
    _expectBody(replacement.saveBytes());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('viewing mode does not open the native-menu font editor', (
    tester,
  ) async {
    final (controller, key) = await _host(tester);
    controller.config = const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.viewing,
    );
    key.currentState!.perform(OfficeEditorAction.font);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.isDirty, isFalse);
    _expectBody(controller.saveBytes());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
