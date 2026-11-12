import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _fixture =
    '../quds_office_engine/test/fixtures/fidelity/slide-sections.pptx';
const _p14 = 'http://schemas.microsoft.com/office/powerpoint/2010/main';
const _names = [
  'Leading empty',
  'Intro & agenda',
  'Gap empty',
  'Body',
  'Conclusion',
  'Trailing empty',
];
const _ids = [701, 503, 907, 509, 1201, 803];
const _starts = [0, 0, 2, 2, 4, 6];

SlideEditorController _controller({OfficeInteractionMode? mode}) {
  final editor = SlideEditorController.fromBytes(
    File(_fixture).readAsBytesSync(),
    config: OfficeSurfaceConfig(mode: mode ?? OfficeInteractionMode.editing),
  );
  addTearDown(editor.dispose);
  return editor;
}

void _expectDeck(PmlPresentation deck, List<int> ids, List<int> starts) {
  expect(deck.sectionSource?.issue, isNull);
  expect(deck.slides.map((slide) => slide.id), ids);
  expect(deck.sections.map((section) => section.name), _names);
  expect(deck.sections.map((section) => section.startIndex), starts);
  expect(deck.sections.map((section) => section.id), [
    for (int id = 1; id <= 6; id++)
      '{A71D8B00-3E2F-4A20-9F10-${id.toString().padLeft(12, '0')}}',
  ]);
}

Uint8List _ambiguousFixture() {
  final package = OpcPackage.openBytes(File(_fixture).readAsBytesSync());
  final part = package.getPart('/ppt/presentation.xml')!;
  final document = XmlDocument.parse(part.readText());
  final sections = document.root!
      .firstChild('extLst', namespaceUri: OfficeNamespaces.p)!
      .childElements
      .firstWhere(
        (extension) =>
            extension.getAttribute('uri') ==
            '{521415D9-36F7-43E2-AB2F-B90AF26B5E84}',
      )
      .firstChild('sectionLst', namespaceUri: _p14)!
      .childElements
      .toList();
  sections[3]
      .firstChild('sldIdLst', namespaceUri: _p14)!
      .childElements
      .first
      .setAttribute('id', '701');
  part.writeText(document.toXmlString());
  return package.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases =
      <
        String,
        ({
          int from,
          int to,
          int active,
          int nextActive,
          List<int> ids,
          List<int> starts,
        })
      >{
        'forward moved active': (
          from: 0,
          to: 3,
          active: 0,
          nextActive: 3,
          ids: [503, 907, 509, 701, 1201, 803],
          starts: [0, 0, 1, 1, 4, 6],
        ),
        'forward unaffected active': (
          from: 0,
          to: 3,
          active: 2,
          nextActive: 1,
          ids: [503, 907, 509, 701, 1201, 803],
          starts: [0, 0, 1, 1, 4, 6],
        ),
        'backward moved active': (
          from: 5,
          to: 1,
          active: 5,
          nextActive: 1,
          ids: [701, 803, 503, 907, 509, 1201],
          starts: [0, 0, 3, 3, 5, 6],
        ),
        'backward unaffected active': (
          from: 5,
          to: 1,
          active: 3,
          nextActive: 4,
          ids: [701, 803, 503, 907, 509, 1201],
          starts: [0, 0, 3, 3, 5, 6],
        ),
        'within section': (
          from: 1,
          to: 0,
          active: 4,
          nextActive: 4,
          ids: [503, 701, 907, 509, 1201, 803],
          starts: _starts,
        ),
      };

  for (final entry in cases.entries) {
    test('${entry.key} keeps memberships and exact undo/redo state', () {
      final editor = _controller();
      final change = entry.value;
      final originalSlides = [...editor.presentation.slides];
      final originalSections = [...editor.presentation.sections];
      editor.setActiveSlide(change.active);
      final active = editor.slide;
      editor.selectShape(active.shapes.first);
      expect(editor.isDirty, isFalse);
      expect(editor.canUndo, isFalse);
      final revision = editor.contentRevision;
      var commands = 0;
      editor.commands.addListener(() => commands++);

      editor.reorderSlide(change.from, change.to);
      _expectDeck(editor.presentation, change.ids, change.starts);
      expect(editor.slide, same(active));
      expect(editor.activeSlideIndex, change.nextActive);
      expect(editor.selected, isNull);
      expect(editor.isDirty, isTrue);
      expect(editor.canUndo, isTrue);
      expect(editor.contentRevision, revision + 1);
      expect(commands, 1);

      editor.undo();
      _expectDeck(editor.presentation, _ids, _starts);
      expect(editor.presentation.slides, originalSlides);
      expect(editor.presentation.sections, originalSections);
      expect(editor.slide, same(active));
      expect(editor.activeSlideIndex, change.active);
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isTrue);
      expect(editor.contentRevision, revision + 2);
      expect(commands, 2);

      editor.redo();
      _expectDeck(editor.presentation, change.ids, change.starts);
      expect(editor.slide, same(active));
      expect(editor.activeSlideIndex, change.nextActive);
      expect(editor.canUndo, isTrue);
      expect(editor.canRedo, isFalse);
      expect(editor.contentRevision, revision + 3);
      expect(commands, 3);
    });
  }

  test('emptying a source section preserves it across two undo/redo steps', () {
    final editor = _controller();
    editor.reorderSlide(1, 2);
    _expectDeck(
      editor.presentation,
      [701, 907, 503, 509, 1201, 803],
      [0, 0, 1, 1, 4, 6],
    );
    editor.reorderSlide(0, 1);
    _expectDeck(
      editor.presentation,
      [907, 701, 503, 509, 1201, 803],
      [0, 0, 0, 0, 4, 6],
    );
    editor.undo();
    _expectDeck(
      editor.presentation,
      [701, 907, 503, 509, 1201, 803],
      [0, 0, 1, 1, 4, 6],
    );
    editor.undo();
    _expectDeck(editor.presentation, _ids, _starts);
    editor.redo();
    editor.redo();
    _expectDeck(
      editor.presentation,
      [907, 701, 503, 509, 1201, 803],
      [0, 0, 0, 0, 4, 6],
    );
  });

  for (final asynchronous in [false, true]) {
    test('controller ${asynchronous ? 'isolate' : 'direct'} save retains the '
        'redone move through three reopen cycles', () async {
      var editor = _controller();
      editor.reorderSlide(0, 3);
      editor.undo();
      editor.redo();
      for (int cycle = 0; cycle < 3; cycle++) {
        final revision = editor.contentRevision;
        final bytes = asynchronous
            ? await editor.saveBytesAsync()
            : editor.saveBytes();
        expect(editor.contentRevision, revision);
        final reopened = SlideEditorController();
        addTearDown(reopened.dispose);
        if (asynchronous) {
          await reopened.loadBytesAsync(bytes);
        } else {
          reopened.loadBytes(bytes);
        }
        _expectDeck(
          reopened.presentation,
          [503, 907, 509, 701, 1201, 803],
          [0, 0, 1, 1, 4, 6],
        );
        expect(reopened.isDirty, isFalse);
        for (int index = 0; index < 6; index++) {
          final native = reopened.presentation.sections[index].nativeXml!;
          final opaque = native
              .firstChild('extLst', namespaceUri: _p14)!
              .childElements
              .single
              .childElements
              .single;
          expect(opaque.getAttribute('token'), 'keep-$index');
          expect(opaque.text, 'Unchanged property $index');
        }
        editor = reopened;
      }
    });
  }

  test('ambiguous native membership fails before any editor state changes', () {
    final editor = SlideEditorController.fromBytes(_ambiguousFixture());
    addTearDown(editor.dispose);
    expect(editor.presentation.sectionSource?.issue, isNotNull);
    editor.setActiveSlide(2);
    editor.selectShape(editor.slide.shapes.first);
    final selected = editor.selected;
    final slides = [...editor.presentation.slides];
    final revision = editor.contentRevision;
    final package = {
      for (final part in editor.presentation.package!.parts)
        part.uri: Uint8List.fromList(part.readBytes()),
    };
    var notifications = 0;
    editor.addListener(() => notifications++);
    expect(() => editor.reorderSlide(0, 3), throwsStateError);
    expect(editor.presentation.slides, slides);
    expect(editor.presentation.sections, isEmpty);
    expect(editor.activeSlideIndex, 2);
    expect(editor.selected, same(selected));
    expect(editor.contentRevision, revision);
    expect(editor.canUndo, isFalse);
    expect(editor.canRedo, isFalse);
    expect(editor.isDirty, isFalse);
    expect(notifications, 0);
    expect({
      for (final part in editor.presentation.package!.parts)
        part.uri: part.readBytes(),
    }, package);
  });

  test('no-op and invalid indexes leave sections and history unchanged', () {
    final editor = _controller();
    final revision = editor.contentRevision;
    for (final indexes in [(-1, 0), (0, -1), (6, 0), (0, 6), (2, 2)]) {
      editor.reorderSlide(indexes.$1, indexes.$2);
    }
    _expectDeck(editor.presentation, _ids, _starts);
    expect(editor.contentRevision, revision);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode does not mutate section order or create history', () {
      final editor = _controller(mode: mode);
      final revision = editor.contentRevision;
      editor.reorderSlide(0, 3);
      _expectDeck(editor.presentation, _ids, _starts);
      expect(editor.contentRevision, revision);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
    });
  }
}
