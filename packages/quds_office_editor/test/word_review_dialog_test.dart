import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Finder _key(String value) => find.byKey(ValueKey<String>(value));

WordEditorController _controller([WmlDocument? document]) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'The open document stays.'),
  );
  addTearDown(controller.dispose);
  return controller;
}

WordEditorController _pendingChanges() {
  final document = WmlDocument.empty(text: 'Alpha addition');
  document.sections.single.blocks.addAll([
    WmlParagraph(inlines: [WmlRun(text: 'Obsolete sentence')]),
    WmlParagraph(inlines: [WmlRun(text: 'Beta addition')]),
  ]);
  final paragraphs = document.paragraphs.toList();
  for (var index = 0; index < paragraphs.length; index++) {
    final paragraph = paragraphs[index];
    WordRevisions.record(
      document,
      kind: index == 1 ? WmlRevisionKind.delete : WmlRevisionKind.insert,
      paragraphIndex: index,
      paragraph: paragraph,
      start: 0,
      end: paragraph.text.length,
      text: paragraph.text,
      author: index == 2 ? 'Bob' : 'Alice',
    ).dateIso = '2026-11-01T12:30:00Z';
  }
  document.trackRevisions = false;
  return _controller(document);
}

Future<void> _open(
  WidgetTester tester,
  WordEditorController controller, {
  WordComparisonDocumentPicker? pickDocument,
  WordComparisonReportExporter? onExportReport,
  WordReviewTab initialTab = WordReviewTab.changes,
  Size size = const Size(1280, 1000),
  bool arabic = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWordReviewDialog(
              context,
              controller: controller,
              documentName: 'Current document',
              pickDocument: pickDocument,
              onExportReport: onExportReport,
              initialTab: initialTab,
              arabic: arabic,
            ),
            child: const Text('Open review'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open review'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, _key(key));
  await _tap(tester, find.text(label).last);
}

String _text(WidgetTester tester, String key) {
  final widget = tester.widget(_key(key));
  if (widget is Text) return widget.data ?? widget.textSpan!.toPlainText();
  if (widget is SelectableText) {
    return widget.data ?? widget.textSpan!.toPlainText();
  }
  throw StateError('$key does not identify displayed text');
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

Future<void> _compare(WidgetTester tester) async {
  await tester.ensureVisible(_key('compare-run'));
  // compute() runs on a real isolate. Pump real frames until it completes,
  // rather than advancing only the widget test's fake animation clock.
  await tester.runAsync(() async {
    await tester.tap(_key('compare-run'));
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(_key('compare-summary'), findsOneWidget);
}

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

List<TextSpan> _visibleSpans(WidgetTester tester) => [
  for (final text in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  ))
    if (text.textSpan != null) ..._spans(text.textSpan!),
];

void main() {
  testWidgets('Review opens with the CrispOffice default reviewer', (
    tester,
  ) async {
    final controller = _controller();
    await _open(tester, controller);
    final author = tester.widget<TextField>(_key('review-author'));
    expect(author.controller!.text, 'CrispOffice');
    expect(find.text('Quds Office'), findsNothing);
  });

  testWidgets('tracking and reviewer controls affect future edits with undo', (
    tester,
  ) async {
    final controller = _pendingChanges();
    final existing = List<WmlRevision>.of(controller.document.revisions);
    await _open(tester, controller);

    await _tap(tester, _key('review-track'));
    expect(controller.document.trackRevisions, isTrue);
    await _tap(tester, _key('review-undo'));
    expect(controller.document.trackRevisions, isFalse);
    await _tap(tester, _key('review-redo'));
    expect(controller.document.trackRevisions, isTrue);

    await tester.enterText(_key('review-author'), '  Mira  ');
    await _tap(tester, _key('review-set-author'));
    expect(controller.revisionAuthor, 'Mira');
    controller.insertText('Fresh ');
    await tester.pumpAndSettle();
    expect(controller.document.revisions.last.author, 'Mira');
    expect(existing.map((revision) => revision.author), [
      'Alice',
      'Alice',
      'Bob',
    ]);
    expect(existing.map((revision) => revision.dateIso).toSet(), {
      '2026-11-01T12:30:00Z',
    });

    await tester.enterText(_key('review-author'), '   ');
    await _tap(tester, _key('review-set-author'));
    expect(controller.revisionAuthor, 'Mira');
    expect(_text(tester, 'review-notice'), contains('Must not be empty'));
  });

  testWidgets(
    'author, kind and text filters intersect without changing sources',
    (tester) async {
      final controller = _pendingChanges();
      final snapshot = WordRevisions.capture(controller.document);
      await _open(tester, controller);
      expect(find.text('3 of 3 pending'), findsOneWidget);

      await _choose(tester, 'review-author-filter', 'Alice');
      expect(find.text('2 of 3 pending'), findsOneWidget);
      await _choose(tester, 'review-kind-filter', 'Deletions');
      expect(find.text('1 of 3 pending'), findsOneWidget);
      expect(_key('review-change-2'), findsOneWidget);
      expect(_key('review-change-1'), findsNothing);
      expect(_key('review-change-3'), findsNothing);

      await tester.enterText(_key('review-search'), '  oBsOlEtE  ');
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 pending'), findsOneWidget);
      await tester.enterText(_key('review-search'), 'Alpha');
      await tester.pumpAndSettle();
      expect(find.text('No changes match these filters.'), findsOneWidget);
      expect(_enabled(tester, 'review-accept-shown'), isFalse);
      expect(_enabled(tester, 'review-reject-shown'), isFalse);
      await _tap(tester, _key('review-compare-tab'));
      await _tap(tester, _key('review-changes-tab'));
      expect(
        tester.widget<TextField>(_key('review-search')).controller!.text,
        'Alpha',
      );
      expect(find.text('No changes match these filters.'), findsOneWidget);
      expect(snapshot.matches(controller.document), isTrue);
      expect(controller.canUndo, isFalse);
    },
  );

  for (final accept in [true, false]) {
    testWidgets(
      '${accept ? 'accept' : 'reject'} shown is a filtered undoable batch',
      (tester) async {
        final controller = _pendingChanges();
        final changes = List<WmlRevision>.of(controller.document.revisions);
        final snapshot = WordRevisions.capture(controller.document);
        await _open(tester, controller);
        await _choose(tester, 'review-author-filter', 'Alice');
        await _tap(
          tester,
          _key(accept ? 'review-accept-shown' : 'review-reject-shown'),
        );

        expect(controller.document.revisions, [same(changes[2])]);
        expect(
          controller.document.paragraphs.map((paragraph) => paragraph.text),
          accept
              ? ['Alpha addition', '', 'Beta addition']
              : ['', 'Obsolete sentence', 'Beta addition'],
        );
        await _tap(tester, _key('review-undo'));
        expect(snapshot.matches(controller.document), isTrue);
        expect(
          controller.document.paragraphs.map((paragraph) => paragraph.text),
          ['Alpha addition', 'Obsolete sentence', 'Beta addition'],
        );
        await _tap(tester, _key('review-redo'));
        expect(controller.document.revisions, [same(changes[2])]);
      },
    );
  }

  testWidgets('final and original previews leave tracked changes untouched', (
    tester,
  ) async {
    final controller = _pendingChanges();
    final snapshot = WordRevisions.capture(controller.document);
    await _open(tester, controller);
    await _tap(tester, _key('review-change-2'));
    expect(_text(tester, 'review-preview-text'), 'Obsolete sentence');
    await _choose(tester, 'review-preview-mode', 'Final text');
    expect(_text(tester, 'review-preview-text'), isEmpty);
    await _choose(tester, 'review-preview-mode', 'Original text');
    expect(_text(tester, 'review-preview-text'), 'Obsolete sentence');
    expect(snapshot.matches(controller.document), isTrue);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('viewing mode exposes review but disables document mutations', (
    tester,
  ) async {
    final controller = _pendingChanges()
      ..setMode(OfficeInteractionMode.viewing);
    final snapshot = WordRevisions.capture(controller.document);
    await _open(tester, controller);
    expect(tester.widget<Switch>(_key('review-track')).onChanged, isNull);
    expect(tester.widget<TextField>(_key('review-author')).enabled, isFalse);
    for (final key in [
      'review-set-author',
      'review-accept',
      'review-reject',
      'review-accept-shown',
      'review-reject-shown',
      'review-undo',
      'review-redo',
    ]) {
      expect(_enabled(tester, key), isFalse, reason: key);
    }
    await _choose(tester, 'review-author-filter', 'Bob');
    expect(find.text('1 of 3 pending'), findsOneWidget);
    expect(snapshot.matches(controller.document), isTrue);
  });

  testWidgets(
    'two picked documents compare, display redlines and export without edits',
    (tester) async {
      final controller = _pendingChanges();
      final original = WmlDocument.empty(text: 'Hello old world.');
      final revised = WmlDocument.empty(text: 'Hello new world.');
      for (final document in [original, revised]) {
        WordRevisions.record(
          document,
          kind: WmlRevisionKind.insert,
          paragraphIndex: 0,
          start: 0,
          end: 5,
          text: 'Hello',
          author: 'Source author',
        );
      }
      final snapshots = [
        for (final document in [controller.document, original, revised])
          WordRevisions.capture(document),
      ];
      final choices = [
        WordComparisonDocument(document: original, name: 'Original.docx'),
        WordComparisonDocument(document: revised, name: 'Revised.odt'),
      ];
      var picks = 0;
      String? report;
      String? reportName;
      await _open(
        tester,
        controller,
        initialTab: WordReviewTab.compare,
        pickDocument: () async => choices[picks++],
        onExportReport: (name, json) async {
          reportName = name;
          report = json;
          return true;
        },
      );
      expect(_enabled(tester, 'compare-run'), isFalse);
      await _tap(tester, _key('compare-pick-original'));
      expect(_text(tester, 'compare-original-name'), 'Original.docx');
      expect(_enabled(tester, 'compare-run'), isFalse);
      await _tap(tester, _key('compare-pick-revised'));
      expect(_text(tester, 'compare-revised-name'), 'Revised.odt');
      expect(picks, 2);
      await _compare(tester);

      expect(_text(tester, 'compare-summary'), contains('1 changes'));
      expect(
        tester.widget<ChoiceChip>(_key('compare-side-by-side')).selected,
        isTrue,
      );
      var spans = _visibleSpans(tester);
      expect(
        spans.any(
          (span) =>
              span.toPlainText().contains('old') &&
              span.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );
      expect(
        spans.any(
          (span) =>
              span.toPlainText().contains('new') &&
              span.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      await _tap(tester, _key('compare-inline'));
      expect(
        tester.widget<ChoiceChip>(_key('compare-inline')).selected,
        isTrue,
      );
      spans = _visibleSpans(tester);
      expect(
        spans.any(
          (span) =>
              span.toPlainText().contains('old') &&
              span.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );
      expect(
        spans.any(
          (span) =>
              span.toPlainText().contains('new') &&
              span.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      await _tap(tester, _key('compare-export-report'));
      expect(reportName, 'document-comparison.json');
      final json = jsonDecode(report!) as Map<String, dynamic>;
      expect(json['originalName'], 'Original.docx');
      expect(json['revisedName'], 'Revised.odt');
      expect(json['comparison']['summary']['changes'], 1);
      expect(
        json['comparison']['entries'].single['originalText'],
        'Hello old world.',
      );
      expect(
        json['comparison']['entries'].single['revisedText'],
        'Hello new world.',
      );

      for (final (index, document) in [
        controller.document,
        original,
        revised,
      ].indexed) {
        expect(snapshots[index].matches(document), isTrue);
      }
      expect(original.paragraphs.single.text, 'Hello old world.');
      expect(revised.paragraphs.single.text, 'Hello new world.');
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);

      await _tap(tester, _key('compare-next'));
      expect(_key('compare-focused-result'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      await _tap(tester, _key('compare-show-all'));
      expect(_key('compare-results'), findsOneWidget);

      await _tap(tester, _key('compare-current-original'));
      expect(_text(tester, 'compare-original-name'), 'Current document');
      expect(_text(tester, 'compare-revised-name'), 'Revised.odt');
      expect(_key('compare-summary'), findsNothing);
      await _tap(tester, _key('compare-current-revised'));
      expect(_text(tester, 'compare-revised-name'), 'Current document');
      expect(picks, 2);
    },
  );

  testWidgets('export cancellation and errors preserve the report for retry', (
    tester,
  ) async {
    final controller = _controller();
    var exports = 0;
    final reports = <String>[];
    await _open(
      tester,
      controller,
      initialTab: WordReviewTab.compare,
      pickDocument: () async => WordComparisonDocument(
        document: WmlDocument.empty(text: 'A revised document.'),
        name: 'Revised.docx',
      ),
      onExportReport: (_, json) async {
        reports.add(json);
        exports++;
        if (exports == 1) return false;
        if (exports == 2) throw StateError('Export destination unavailable');
        return true;
      },
    );
    await _tap(tester, _key('compare-pick-revised'));
    await _compare(tester);
    await _tap(tester, _key('compare-export-report'));
    expect(_key('review-notice'), findsNothing);
    expect(_key('compare-summary'), findsOneWidget);
    await _tap(tester, _key('compare-export-report'));
    expect(
      _text(tester, 'review-notice'),
      contains('Export destination unavailable'),
    );
    expect(_key('compare-summary'), findsOneWidget);
    await _tap(tester, _key('compare-export-report'));
    expect(_text(tester, 'review-notice'), 'Comparison report exported.');
    expect(exports, 3);
    expect(reports.toSet(), hasLength(1));
    expect(
      controller.document.paragraphs.single.text,
      'The open document stays.',
    );
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'current-document edits mark comparison stale and disable export',
    (tester) async {
      final controller = _controller();
      var exports = 0;
      await _open(
        tester,
        controller,
        initialTab: WordReviewTab.compare,
        pickDocument: () async => WordComparisonDocument(
          document: WmlDocument.empty(text: 'A revised document.'),
          name: 'Revised.docx',
        ),
        onExportReport: (_, _) async {
          exports++;
          return true;
        },
      );
      await _tap(tester, _key('compare-pick-revised'));
      await _compare(tester);
      expect(_enabled(tester, 'compare-export-report'), isTrue);
      controller.insertText('Updated ');
      await tester.pumpAndSettle();
      expect(_key('compare-stale'), findsOneWidget);
      expect(_enabled(tester, 'compare-export-report'), isFalse);
      expect(_enabled(tester, 'compare-copy-report'), isFalse);
      expect(exports, 0);
      await _compare(tester);
      expect(_key('compare-stale'), findsNothing);
      expect(_enabled(tester, 'compare-export-report'), isTrue);
    },
  );

  testWidgets(
    'picker cancellation and errors preserve selections and recover',
    (tester) async {
      final controller = _controller();
      var picks = 0;
      await _open(
        tester,
        controller,
        initialTab: WordReviewTab.compare,
        pickDocument: () async {
          picks++;
          if (picks == 1) return null;
          if (picks == 2) throw const FormatException('Unsupported file');
          return WordComparisonDocument(
            document: WmlDocument.empty(text: 'Readable document'),
            name: 'Recovered.docx',
          );
        },
      );
      await _tap(tester, _key('compare-pick-original'));
      expect(_text(tester, 'compare-original-name'), 'Current document');
      expect(_key('review-notice'), findsNothing);
      await _tap(tester, _key('compare-pick-revised'));
      expect(
        _text(tester, 'review-notice'),
        contains('Could not open document'),
      );
      expect(_text(tester, 'review-notice'), contains('Unsupported file'));
      expect(_enabled(tester, 'compare-run'), isFalse);
      await _tap(tester, _key('compare-pick-revised'));
      expect(_text(tester, 'compare-revised-name'), 'Recovered.docx');
      expect(_key('review-notice'), findsNothing);
      expect(_enabled(tester, 'compare-run'), isTrue);
      expect(
        controller.document.paragraphs.single.text,
        'The open document stays.',
      );
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('closing during a pending picker ignores its later completion', (
    tester,
  ) async {
    final controller = _controller();
    final pending = Completer<WordComparisonDocument?>();
    await _open(
      tester,
      controller,
      initialTab: WordReviewTab.compare,
      pickDocument: () => pending.future,
    );
    await tester.tap(_key('compare-pick-revised'));
    await tester.pump();
    expect(_enabled(tester, 'compare-pick-original'), isFalse);
    expect(_enabled(tester, 'compare-run'), isFalse);
    await _tap(tester, _key('review-close'));
    pending.complete(
      WordComparisonDocument(
        document: WmlDocument.empty(text: 'Late selection'),
        name: 'Late.docx',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WordReviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      controller.document.paragraphs.single.text,
      'The open document stays.',
    );
  });

  for (final arabic in [false, true]) {
    testWidgets(
      'narrow ${arabic ? 'RTL' : 'LTR'} dialog keeps both workflows usable',
      (tester) async {
        final controller = _pendingChanges();
        await _open(
          tester,
          controller,
          size: const Size(360, 740),
          arabic: arabic,
        );
        expect(
          Directionality.of(tester.element(_key('review-track'))),
          arabic ? TextDirection.rtl : TextDirection.ltr,
        );
        await tester.ensureVisible(_key('review-reject-shown'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, _key('review-compare-tab'));
        await _tap(tester, _key('compare-current-revised'));
        await _compare(tester);
        expect(_key('compare-summary'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
