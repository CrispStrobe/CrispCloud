import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _imported = <WmlTabStop>[
  WmlTabStop(
    position: 72.35,
    alignment: WmlTabAlignment.decimal,
    leader: WmlTabLeader.dot,
  ),
  WmlTabStop(
    position: 144.65,
    alignment: WmlTabAlignment.right,
    leader: WmlTabLeader.hyphen,
  ),
];

Finder _key(String name) => find.byKey(ValueKey<String>('word-tab-$name'));

List<(double, WmlTabAlignment, WmlTabLeader)> _values(List<WmlTabStop> tabs) =>
    [for (final tab in tabs) (tab.position, tab.alignment, tab.leader)];

Future<void> _mount(
  WidgetTester tester, {
  List<WmlTabStop> initial = _imported,
  required ValueChanged<List<WmlTabStop>?> changed,
  VoidCallback? apply,
  bool enabled = true,
  double width = 500,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  String Function(String)? translate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: direction,
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      WordTabStopsEditor(
                        initialValue: initial,
                        onChanged: changed,
                        enabled: enabled,
                        translate: translate,
                      ),
                      if (apply != null)
                        TextButton(
                          onPressed: apply,
                          child: const Text('Apply'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _enter(WidgetTester tester, int index, String value) async {
  final field = _key('position-$index');
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String field, String value) async {
  await _tap(tester, _key(field));
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

WordEditorController _controller() {
  final document = WmlDocument.empty(text: 'Name\tValue');
  document.paragraphs.first.properties.tabs = List<WmlTabStop>.of(_imported);
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

List<(String?, String?, String?)> _native(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final paragraph = root.firstChild('body')!.firstChild('p')!;
  return <(String?, String?, String?)>[
    for (final tab
        in paragraph
            .firstChild('pPr')!
            .firstChild('tabs')!
            .childrenNamed('tab'))
      (
        tab.getAttribute('pos'),
        tab.getAttribute('val'),
        tab.getAttribute('leader') ?? 'none',
      ),
  ];
}

void main() {
  testWidgets(
    'opening and discarding typed tab drafts never mutates imported stops',
    (tester) async {
      final controller = _controller();
      var callbacks = 0;
      List<WmlTabStop>? draft;
      await _mount(
        tester,
        changed: (value) {
          callbacks++;
          draft = value;
        },
      );
      expect(callbacks, 0);
      expect(
        tester.widget<TextField>(_key('position-0')).controller!.text,
        '72.35',
      );
      await _choose(tester, 'alignment-0', 'Center');
      expect(draft!.first.alignment, WmlTabAlignment.center);
      expect(
        () => draft!.add(const WmlTabStop(position: 12)),
        throwsUnsupportedError,
      );
      expect(
        _values(controller.document.paragraphs.first.properties.tabs),
        _values(_imported),
      );
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'alignment and leader controls export native values through history and three saves',
    (tester) async {
      final controller = _controller();
      List<WmlTabStop>? draft = _imported;
      await _mount(
        tester,
        changed: (value) => draft = value,
        apply: () {
          if (draft != null) {
            final saved = draft!;
            controller.applyParagraphFormat(
              (props) => props.tabs = List<WmlTabStop>.of(saved),
            );
          }
        },
      );
      await _choose(tester, 'alignment-0', 'Left');
      await _choose(tester, 'leader-0', 'None');
      await _choose(tester, 'alignment-1', 'Decimal');
      await _choose(tester, 'leader-1', 'Dots');
      await _tap(tester, _key('add'));
      await _enter(tester, 2, '216.25');
      await _choose(tester, 'alignment-2', 'Center');
      await _choose(tester, 'leader-2', 'Dashes');
      await _tap(tester, _key('add'));
      await _enter(tester, 3, '288.25');
      await _choose(tester, 'alignment-3', 'Right');
      await _choose(tester, 'leader-3', 'Underline');
      expect(controller.isDirty, isFalse);
      await _tap(tester, find.text('Apply'));
      const expected = [
        ('1447', 'left', 'none'),
        ('2893', 'decimal', 'dot'),
        ('4325', 'center', 'hyphen'),
        ('5765', 'right', 'underscore'),
      ];
      expect(_native(controller.saveBytes()), expected);
      controller.undo();
      expect(_native(controller.saveBytes()), [
        ('1447', 'decimal', 'dot'),
        ('2893', 'right', 'hyphen'),
      ]);
      controller.redo();
      expect(_native(controller.saveBytes()), expected);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await tester.runAsync(controller.saveBytesAsync);
        expect(_native(bytes!), expected);
        final output = File(
          'build/fidelity-custom-tabs/editor-tabs-$cycle.docx',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        controller.loadBytes(bytes);
        expect(
          _values(controller.document.paragraphs.first.properties.tabs),
          _values(draft!),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'invalid and duplicate native positions retain draft text and prevent apply',
    (tester) async {
      final controller = _controller();
      List<WmlTabStop>? draft = _imported;
      await _mount(
        tester,
        changed: (value) => draft = value,
        apply: () {
          if (draft != null) {
            controller.applyParagraphFormat(
              (props) => props.tabs = List<WmlTabStop>.of(draft!),
            );
          }
        },
      );
      for (final invalid in [
        '',
        'bad',
        'NaN',
        'Infinity',
        '-1',
        '107374182.4',
      ]) {
        await _enter(tester, 0, invalid);
        expect(draft, isNull, reason: invalid);
        await _tap(tester, find.text('Apply'));
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        expect(
          tester.widget<TextField>(_key('position-0')).controller!.text,
          invalid,
        );
      }
      await _enter(tester, 0, '144.651');
      expect(draft, isNull);
      expect(find.text('Tab positions must be distinct.'), findsNWidgets(2));
      await _enter(tester, 0, '36,25');
      expect(draft!.first.position, 36.25);
      expect(draft!.first.alignment, WmlTabAlignment.decimal);
      expect(draft!.first.leader, WmlTabLeader.dot);
      await _tap(tester, find.text('Apply'));
      expect(_native(controller.saveBytes()).first, ('725', 'decimal', 'dot'));
    },
  );

  testWidgets('removing invalid or final rows yields valid immutable drafts', (
    tester,
  ) async {
    List<WmlTabStop>? draft = _imported;
    await _mount(tester, changed: (value) => draft = value);
    await _enter(tester, 0, 'bad');
    expect(draft, isNull);
    await _tap(tester, _key('remove-0'));
    expect(_values(draft!), _values([_imported.last]));
    expect(
      tester.widget<TextField>(_key('position-0')).controller!.text,
      '144.65',
    );
    await _tap(tester, _key('remove-0'));
    expect(draft, isEmpty);
    await _tap(tester, _key('add'));
    expect(_values(draft!), [(36.0, WmlTabAlignment.left, WmlTabLeader.none)]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabled controls and a controller made read-only cannot change tabs',
    (tester) async {
      var changes = 0;
      await _mount(tester, enabled: false, changed: (_) => changes++);
      expect(tester.widget<TextField>(_key('position-0')).enabled, isFalse);
      expect(tester.widget<TextButton>(_key('add')).onPressed, isNull);
      expect(tester.widget<IconButton>(_key('remove-0')).onPressed, isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<WmlTabAlignment>>(
              _key('alignment-0'),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<WmlTabLeader>>(_key('leader-0'))
            .onChanged,
        isNull,
      );
      expect(changes, 0);
      await tester.pumpWidget(const SizedBox.shrink());

      final controller = _controller();
      List<WmlTabStop>? draft = _imported;
      await _mount(
        tester,
        changed: (value) => draft = value,
        apply: () {
          if (draft != null) {
            controller.applyParagraphFormat(
              (props) => props.tabs = List<WmlTabStop>.of(draft!),
            );
          }
        },
      );
      await _choose(tester, 'leader-0', 'Underline');
      controller.setMode(OfficeInteractionMode.viewing);
      await _tap(tester, find.text('Apply'));
      expect(
        _values(controller.document.paragraphs.first.properties.tabs),
        _values(_imported),
      );
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'invalid tab drafts do not commit or discard an unrelated pending note',
    (tester) async {
      final controller = _controller();
      controller.insertFootnote(text: 'Original note');
      final note = controller.document.footnotes.single;
      controller.setNoteText(note, 'Pending note');
      var commands = 0;
      controller.commands.addListener(() => commands++);
      final revision = controller.contentRevision;
      List<WmlTabStop>? draft = _imported;
      await _mount(
        tester,
        changed: (value) => draft = value,
        apply: () {
          if (draft != null) {
            controller.applyParagraphFormat(
              (props) => props.tabs = List<WmlTabStop>.of(draft!),
            );
          }
        },
      );
      await _enter(tester, 0, 'NaN');
      await _tap(tester, find.text('Apply'));
      expect(commands, 0);
      expect(controller.contentRevision, revision);
      expect(controller.noteEditText(note), 'Pending note');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.setNoteText(note, 'Continued note');
      controller.undo();
      expect(controller.noteEditText(note), 'Original note');
      expect(
        _values(controller.document.paragraphs.first.properties.tabs),
        _values(_imported),
      );
    },
  );

  testWidgets('translated controls fit narrow RTL layouts with enlarged text', (
    tester,
  ) async {
    List<WmlTabStop>? draft = _imported;
    await _mount(
      tester,
      width: 280,
      direction: TextDirection.rtl,
      scale: 2,
      translate: (value) =>
          {
            'Custom tab stops': 'علامات الجدولة المخصصة',
            'Add tab stop': 'إضافة علامة جدولة',
            'Tab alignment': 'محاذاة الجدولة',
            'Tab leader': 'الحرف القائد',
            'Tab position (pt)': 'موضع الجدولة (نقطة)',
          }[value] ??
          value,
      changed: (value) => draft = value,
    );
    expect(find.text('علامات الجدولة المخصصة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _enter(tester, 0, '36.25');
    expect(draft!.first.position, 36.25);
    expect(tester.takeException(), isNull);
  });
}
