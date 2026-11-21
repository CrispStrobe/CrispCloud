import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'support/review_fonts.dart';

class _NotesProvider extends OfficeProofingProvider {
  _NotesProvider({
    this.providerId = 'notes-widget',
    this.status = OfficeProofingStatus.success,
  });

  final String providerId;
  final OfficeProofingStatus status;
  final requests = <OfficeProofingRequest>[];

  @override
  String get id => providerId;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    final findings = <OfficeProofingFinding>[];
    if (status == OfficeProofingStatus.success) {
      for (final (needle, category, replacement) in [
        ('Feler', OfficeProofingCategory.spelling, 'Fehler'),
        ('are is', OfficeProofingCategory.grammar, 'is'),
        ('very very', OfficeProofingCategory.style, 'very'),
      ]) {
        for (final match in RegExp(
          RegExp.escape(needle),
        ).allMatches(request.text)) {
          findings.add(
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'notes.${category.name}',
              message: 'Review $needle.',
              category: category,
              replacements: [replacement],
            ),
          );
        }
      }
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : 'The configured Notes checker is unavailable.',
      findings: findings,
    );
  }
}

typedef _Fixture = ({
  WordEditorController controller,
  WmlNote note,
  _NotesProvider provider,
});

String _id(WmlNote note) => '${note.endnote ? 'E' : ''}${note.id}';
Finder _field(WmlNote note) =>
    find.byKey(ValueKey<String>('notes-edit-${_id(note)}'));
Finder _replacement(WmlNote note) =>
    find.byKey(ValueKey<String>('notes-replacement-${_id(note)}-0'));

Future<void> _pump(WidgetTester tester, {int frames = 6}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _check(
  WidgetTester tester,
  WordEditorController controller,
) async {
  await tester.runAsync(controller.checkDocumentProofing);
  await _pump(tester);
}

Future<void> _historyKey(
  WidgetTester tester, {
  bool redo = false,
  bool useY = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo && !useY) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(
    useY ? LogicalKeyboardKey.keyY : LogicalKeyboardKey.keyZ,
  );
  if (redo && !useY) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _pump(tester);
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  String text = 'Feler are is very very useful.',
  bool endnote = false,
  bool live = true,
  bool arabic = false,
  double textScale = 1,
  Size size = const Size(1100, 820),
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
  _NotesProvider? provider,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final document = WmlDocument.empty(
    text: arabic
        ? 'نص المستند مع حاشية للمراجعة'
        : 'Document body with a note.',
  )..proofingLanguage = 'en-US';
  final note = WordNotes.insert(
    document,
    document.paragraphs.single,
    endnote: endnote,
    text: text,
  );
  final checker = provider ?? _NotesProvider();
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(
      mode: mode,
      showNotesPane: true,
      showRulers: false,
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
    ),
    proofingService: OfficeProofingService(providers: [checker]),
  );
  controller.proofing.enabled = live;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: 'Liberation Sans',
        fontFamilyFallback: const ['Noto Naskh Arabic'],
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey<String>('notes-review-capture'),
            child: QudsWordEditor(
              controller: controller,
              notesPaneBuilder: (context, current) =>
                  WordNotesPane(controller: current, arabic: arabic),
            ),
          ),
        ),
      ),
    ),
  );
  await _check(tester, controller);
  return (controller: controller, note: note, provider: checker);
}

Map<String, Color?> _underlines(WidgetTester tester, WmlNote note) {
  final field = tester.widget<TextField>(_field(note));
  final span = field.controller!.buildTextSpan(
    context: tester.element(_field(note)),
    style: const TextStyle(fontSize: 11),
    withComposing: true,
  );
  final result = <String, Color?>{};
  void visit(TextSpan current) {
    if (current.style?.decorationStyle == TextDecorationStyle.wavy &&
        current.text != null) {
      result[current.text!] = current.style?.decorationColor;
    }
    for (final child in current.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) visit(child);
    }
  }

  visit(span);
  return result;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['QUDS_NOTES_REVIEW_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('notes-review-capture')),
    );
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _finish(
  WidgetTester tester,
  WordEditorController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);

  testWidgets('Notes paints all finding categories without changing source', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(tester);
    final before = controller.noteEditText(note);
    expect(_underlines(tester, note), {
      'Feler': const Color(0xFFC62828),
      'are is': const Color(0xFF1565C0),
      'very very': const Color(0xFFAD6800),
    });
    expect(tester.widget<TextField>(_field(note)).controller!.text, before);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(provider.requests, isNotEmpty);
    await _capture(tester, 'notes-inline-desktop');
    await _finish(tester, controller);
  });

  for (final endnote in [false, true]) {
    testWidgets('live note correction retains focus and separates typing Undo: '
        '${endnote ? 'endnote' : 'footnote'}', (tester) async {
      final (:controller, :note, :provider) = await _mount(
        tester,
        endnote: endnote,
        text: 'Original note',
      );
      final manual = _NotesProvider(providerId: 'manual-notes');
      controller.proofing.configureManual(
        OfficeProofingService(providers: [manual]),
      );
      await tester.enterText(_field(note), 'Lead\nFeler note');
      // The pause before checking (WordProofingTiming.idle) plus frames.
      await _pump(tester, frames: 20);
      expect(
        provider.requests.any((request) => request.text.contains('Feler')),
        isTrue,
      );
      expect(manual.requests, isEmpty);
      expect(_underlines(tester, note)['Feler'], const Color(0xFFC62828));

      await tester.ensureVisible(_replacement(note));
      await tester.tap(_replacement(note));
      await _pump(tester);
      expect(controller.noteEditText(note), 'Lead\nFehler note');
      final field = tester.widget<TextField>(_field(note));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 11),
      );

      await _historyKey(tester);
      expect(controller.noteEditText(note), 'Lead\nFeler note');
      await _historyKey(tester);
      expect(controller.noteEditText(note), 'Original note');
      expect(controller.canUndo, isFalse);
      await _historyKey(tester, redo: true);
      expect(controller.noteEditText(note), 'Lead\nFeler note');
      await _historyKey(tester, redo: true, useY: true);
      expect(controller.noteEditText(note), 'Lead\nFehler note');
      expect(
        tester.widget<TextField>(_field(note)).focusNode!.hasFocus,
        isTrue,
      );
      await _finish(tester, controller);
    });
  }

  testWidgets('Notes keyboard undo restores tracked correction revisions', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'Feler note',
    );
    controller.document.trackRevisions = true;
    await _check(tester, controller);
    await tester.ensureVisible(_replacement(note));
    await tester.tap(_replacement(note));
    await _pump(tester);
    expect(controller.noteEditText(note), 'FelerFehler note');
    final revisions = List<WmlRevision>.of(controller.document.revisions);
    expect(revisions.map((revision) => revision.kind), [
      WmlRevisionKind.delete,
      WmlRevisionKind.insert,
    ]);
    await _historyKey(tester);
    expect(controller.noteEditText(note), 'Feler note');
    expect(controller.document.revisions, isEmpty);
    expect(controller.canUndo, isFalse);
    await _historyKey(tester, redo: true);
    expect(controller.noteEditText(note), 'FelerFehler note');
    expect(controller.document.revisions, orderedEquals(revisions));
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets('redo never overwrites a new Notes draft after undo', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'Original note',
    );
    await tester.enterText(_field(note), 'First draft');
    await _pump(tester);
    await _historyKey(tester);
    expect(controller.noteEditText(note), 'Original note');
    expect(controller.canRedo, isTrue);
    await tester.enterText(_field(note), 'A new draft to keep');
    await _pump(tester);
    await _historyKey(tester, redo: true, useY: true);
    expect(controller.noteEditText(note), 'A new draft to keep');
    expect(controller.canRedo, isFalse);
    await _historyKey(tester);
    expect(controller.noteEditText(note), 'Original note');
    await _historyKey(tester, redo: true);
    expect(controller.noteEditText(note), 'A new draft to keep');
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets('Notes keyboard history leaves an active composition untouched', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'Original note',
    );
    await tester.enterText(_field(note), 'Composing note');
    await _pump(tester);
    final edit = tester.widget<TextField>(_field(note)).controller!;
    edit.value = edit.value.copyWith(
      selection: const TextSelection.collapsed(offset: 9),
      composing: const TextRange(start: 0, end: 9),
    );
    await _pump(tester);
    final before = edit.value;
    final revision = controller.contentRevision;
    await _historyKey(tester);
    await _historyKey(tester, redo: true, useY: true);
    expect(edit.value, before);
    expect(controller.noteEditText(note), 'Composing note');
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    edit.value = edit.value.copyWith(composing: TextRange.empty);
    await _pump(tester);
    await _historyKey(tester);
    expect(controller.noteEditText(note), 'Original note');
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  for (final endnote in [false, true]) {
    testWidgets('language and checking controls follow the focused '
        '${endnote ? 'endnote' : 'footnote'}', (tester) async {
      final (:controller, :note, :provider) = await _mount(
        tester,
        endnote: endnote,
        text: 'Feler note',
      );
      final body = controller.document.paragraphs.single;
      final bodyText = body.text;
      final field = _field(note);
      await tester.ensureVisible(field);
      await tester.pump();
      expect(field.hitTestable(), findsOneWidget);
      await tester.tap(field);
      await tester.pump();
      final edit = tester.widget<TextField>(field).controller!;
      final focus = tester.widget<TextField>(field).focusNode!;
      expect(focus.hasFocus, isTrue);
      const selection = TextSelection(baseOffset: 0, extentOffset: 5);
      edit.selection = selection;
      await _pump(tester);
      expect(controller.noteEditingTarget?.note, same(note));
      expect(controller.noteEditingTarget?.selection, selection);
      await tester.tap(
        find.byKey(const ValueKey<String>('word-review-language-status')),
      );
      await _pump(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<TextField>(field).controller, same(edit));
      expect(tester.widget<TextField>(field).focusNode, same(focus));
      expect(controller.noteEditingTarget?.note, same(note));
      expect(controller.noteEditingTarget?.selection, selection);
      // Check the source range before controls run at either Review position.
      for (final width in [720.0, 1100.0]) {
        await tester.binding.setSurfaceSize(Size(width, 820));
        await _pump(tester);
        expect(tester.widget<TextField>(field).controller, same(edit));
        expect(tester.widget<TextField>(field).focusNode, same(focus));
        expect(controller.noteEditingTarget?.note, same(note));
        expect(controller.noteEditingTarget?.selection, selection);
      }
      final language = find.byKey(
        const ValueKey<String>('live-proofing-text-language'),
      );
      await tester.ensureVisible(language);
      await tester.pump();
      expect(language.hitTestable(), findsOneWidget);
      expect(
        tester.widget<DropdownButton<String>>(language).onChanged,
        isNotNull,
      );
      await tester.tap(language);
      await _pump(tester);
      await tester.tap(find.text('Deutsch (Deutschland)').last);
      await _pump(tester);
      final runs = note.paragraphs.single.inlines.whereType<WmlRun>().toList();
      expect(runs.map((run) => run.text), ['Feler', ' note']);
      expect(runs.map((run) => run.properties.proofingLanguage), [
        'de-DE',
        null,
      ]);
      final checking = find.byKey(
        const ValueKey<String>('live-proofing-text-enabled'),
      );
      await tester.ensureVisible(checking);
      await tester.tap(checking);
      await _pump(tester);
      expect(
        note.paragraphs.single.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .noProof,
        isTrue,
      );
      expect(controller.noteEditingTarget?.note, same(note));
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(body.text, bodyText);
      expect(
        body.inlines.whereType<WmlRun>().every(
          (run) =>
              run.properties.proofingLanguage == null &&
              run.properties.noProof == null,
        ),
        isTrue,
      );
      expect(provider.requests, isNotEmpty);
      for (final size in [const Size(650, 820), const Size(1100, 820)]) {
        await tester.binding.setSurfaceSize(size);
        await _pump(tester);
        expect(tester.widget<TextField>(field).controller, same(edit));
        expect(tester.widget<TextField>(field).focusNode, same(focus));
        expect(controller.noteEditingTarget?.note, same(note));
        expect(controller.noteEditingTarget?.selection, selection);
      }
      await tester.tap(find.byKey(const ValueKey<String>('live-review-close')));
      await _pump(tester);
      expect(controller.reviewPaneVisible, isFalse);
      expect(tester.widget<TextField>(field).controller, same(edit));
      expect(tester.widget<TextField>(field).focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(controller.noteEditingTarget?.note, same(note));
      expect(controller.noteEditingTarget?.selection, selection);
      await _finish(tester, controller);
    });
  }

  testWidgets('keyboard finding navigation selects the actual Notes ranges', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(tester);
    final first = controller.proofingIssuesForNote(note).first.issue;
    expect(controller.selectProofingIssue(first), isTrue);
    await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await _pump(tester);
    expect(
      tester.widget<TextField>(_field(note)).controller!.selection,
      const TextSelection(baseOffset: 6, extentOffset: 12),
    );
    expect(controller.selectedProofingIssue!.finding.originalText, 'are is');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await _pump(tester);
    expect(controller.selectedProofingIssue!.finding.originalText, 'Feler');

    final manual = _NotesProvider(providerId: 'manual-keyboard-notes');
    controller.proofing.configureManual(
      OfficeProofingService(providers: [manual]),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await _pump(tester, frames: 10);
    expect(manual.requests, isNotEmpty);
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets(
    'composition suppresses underlines and correction until finished',
    (tester) async {
      final (:controller, :note, :provider) = await _mount(
        tester,
        text: 'Feler note',
      );
      await tester.tap(_field(note));
      await _pump(tester);
      final edit = tester.widget<TextField>(_field(note)).controller!;
      edit.value = const TextEditingValue(
        text: 'Feler note',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      await _pump(tester);
      expect(
        controller.noteEditingTarget!.composing,
        const TextRange(start: 0, end: 5),
      );
      expect(_underlines(tester, note), isEmpty);
      expect(tester.widget<TextButton>(_replacement(note)).onPressed, isNull);

      edit.value = edit.value.copyWith(composing: TextRange.empty);
      await _pump(tester);
      expect(_underlines(tester, note)['Feler'], const Color(0xFFC62828));
      expect(
        tester.widget<TextButton>(_replacement(note)).onPressed,
        isNotNull,
      );
      expect(provider.requests, isNotEmpty);
      await _finish(tester, controller);
    },
  );

  testWidgets('retained correction rejects changed source and new documents', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'Feler note',
    );
    final action = tester.widget<TextButton>(_replacement(note)).onPressed!;
    controller.setNoteText(note, 'New correct note');
    action();
    expect(controller.noteEditText(note), 'New correct note');
    controller.loadBytes(
      WordSerializer().writeBytes(
        WmlDocument.empty(text: 'Replacement document'),
      ),
    );
    action();
    expect(controller.document.paragraphs.single.text, 'Replacement document');
    expect(controller.document.footnotes, isEmpty);
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets(
    'select-only and protected Notes remain inspectable without correction',
    (tester) async {
      final (:controller, :note, :provider) = await _mount(
        tester,
        text: 'Feler note',
        mode: OfficeInteractionMode.selecting,
      );
      expect(tester.widget<TextField>(_field(note)).readOnly, isTrue);
      expect(_underlines(tester, note), isNotEmpty);
      expect(tester.widget<TextButton>(_replacement(note)).onPressed, isNull);
      controller.setMode(OfficeInteractionMode.editing);
      controller.document
        ..restrictEditing = true
        ..restrictMode = WmlRestrictMode.readOnly;
      controller.refreshView();
      await _pump(tester);
      expect(tester.widget<TextButton>(_replacement(note)).onPressed, isNull);
      expect(controller.noteEditText(note), 'Feler note');
      expect(provider.requests, isNotEmpty);
      await _finish(tester, controller);
    },
  );

  testWidgets('Notes review action opens persistent Changes without a dialog', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'A clean note',
    );
    final button = find.byKey(const ValueKey<String>('notes-review-changes'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _pump(tester);
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.changes);
    expect(
      find.byKey(const ValueKey<String>('word-review-pane')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.noteEditText(note), 'A clean note');
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets('unavailable checks are not reported as a clean Notes result', (
    tester,
  ) async {
    final checker = _NotesProvider(status: OfficeProofingStatus.unavailable);
    final (:controller, :note, :provider) = await _mount(
      tester,
      provider: checker,
    );
    final status = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('notes-proofing-status')),
        )
        .data!;
    expect(status, contains('unavailable'));
    expect(status, isNot(contains('No issues found')));
    expect(_underlines(tester, note), isEmpty);
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });

  testWidgets('narrow Arabic scaled Notes controls stay reachable', (
    tester,
  ) async {
    final (:controller, :note, :provider) = await _mount(
      tester,
      text: 'ملاحظة Feler للمراجعة',
      arabic: true,
      textScale: 1.4,
      size: const Size(650, 1000),
    );
    await tester.ensureVisible(_replacement(note));
    await _pump(tester);
    expect(_replacement(note).hitTestable(), findsOneWidget);
    await _capture(tester, 'notes-inline-arabic-narrow');
    await tester.tap(_replacement(note));
    await _pump(tester);
    expect(controller.noteEditText(note), 'ملاحظة Fehler للمراجعة');
    expect(provider.requests, isNotEmpty);
    await _finish(tester, controller);
  });
}
