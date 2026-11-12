import 'dart:async';

import 'package:crisp_cloud/widgets/ebook_kindle_metadata_editor.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _info = EbookBookInfo(
  title: 'Original title',
  authors: ['Original author'],
  language: 'de',
  toc: [],
  sectionCount: 1,
  sourceFormat: 'mobi',
);

Future<void> _open(
  WidgetTester tester, {
  required Future<bool> Function(KindleMetadataDraft) onApply,
  EbookBookInfo? info,
  VoidCallback? onCancel,
  Size size = const Size(1100, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => EbookKindleMetadataEditor(
                info: info,
                translate: (text) => text,
                exportLabel: 'Export a copy',
                onApply: onApply,
                onCancel: onCancel,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _mode(WidgetTester tester, String field, String mode) async {
  final finder = find.byKey(ValueKey('kindle-metadata-mode-$field'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pumpAndSettle();
}

Finder _value(String field) =>
    find.byKey(ValueKey('kindle-metadata-value-$field'));
Finder get _export => find.byKey(const ValueKey('kindle-metadata-export'));

void main() {
  testWidgets('unloaded fields default to Keep and cannot erase metadata', (
    tester,
  ) async {
    var called = false;
    await _open(
      tester,
      onApply: (_) async {
        called = true;
        return true;
      },
    );
    expect(tester.widget<FilledButton>(_export).onPressed, isNull);
    expect(find.byType(TextFormField), findsNothing);
    expect(called, isFalse);
    expect(find.text('Replace cover'), findsNothing);
  });

  testWidgets('editing one field leaves all unselected metadata unchanged', (
    tester,
  ) async {
    KindleMetadataDraft? sent;
    await _open(
      tester,
      info: _info,
      onApply: (draft) async {
        sent = draft;
        return true;
      },
    );
    await _mode(tester, 'publisher', 'Set');
    await tester.enterText(_value('publisher'), 'Éditions du Nord');
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(sent!.patch.toJson(), {'publisher': 'Éditions du Nord'});
    expect(sent!.cover, isNull);
    expect(find.byType(EbookKindleMetadataEditor), findsNothing);
  });

  testWidgets('Clear is explicit and multiple subject values retain Unicode', (
    tester,
  ) async {
    KindleMetadataDraft? sent;
    await _open(
      tester,
      info: _info,
      onApply: (draft) async {
        sent = draft;
        return true;
      },
    );
    await _mode(tester, 'authors', 'Clear');
    await _mode(tester, 'subjects', 'Set');
    await tester.enterText(
      _value('subjects'),
      '  Österreich\n日本語\n\nScience  ',
    );
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(sent!.patch.toJson(), {
      'authors': <String>[],
      'subjects': ['Österreich', '日本語', 'Science'],
    });
  });

  testWidgets('blank Set must be changed to Clear before removing a field', (
    tester,
  ) async {
    KindleMetadataDraft? sent;
    await _open(
      tester,
      onApply: (draft) async {
        sent = draft;
        return true;
      },
    );
    await _mode(tester, 'title', 'Set');
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(sent, isNull);
    expect(
      find.text('Enter a value, or choose Clear to remove it.'),
      findsOneWidget,
    );
    await _mode(tester, 'title', 'Clear');
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(sent!.patch.toJson(), {'title': ''});
  });

  testWidgets('failed export retains entered values for retry', (tester) async {
    var attempts = 0;
    final patches = <Map<String, Object?>>[];
    await _open(
      tester,
      onApply: (draft) async {
        patches.add(draft.patch.toJson());
        if (++attempts == 1) throw StateError('Destination is offline');
        return true;
      },
    );
    await _mode(tester, 'title', 'Set');
    await tester.enterText(_value('title'), 'Keep my draft');
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(find.byType(EbookKindleMetadataEditor), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_value('title')).controller!.text,
      'Keep my draft',
    );
    expect(find.textContaining('Destination is offline'), findsOneWidget);
    await tester.tap(_export);
    await tester.pumpAndSettle();
    expect(patches, [
      {'title': 'Keep my draft'},
      {'title': 'Keep my draft'},
    ]);
    expect(find.byType(EbookKindleMetadataEditor), findsNothing);
  });

  testWidgets('canceling an active export keeps the draft and allows retry', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var cancelled = false;
    await _open(
      tester,
      onApply: (_) => pending.future,
      onCancel: () {
        cancelled = true;
        pending.complete(false);
      },
    );
    await _mode(tester, 'title', 'Set');
    await tester.enterText(_value('title'), 'Still here');
    await tester.tap(_export);
    await tester.pump();
    expect(tester.widget<FilledButton>(_export).onPressed, isNull);
    await tester.tap(find.text('Cancel operation'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(find.byType(EbookKindleMetadataEditor), findsOneWidget);
    expect(
      tester.widget<TextFormField>(_value('title')).controller!.text,
      'Still here',
    );
    expect(tester.widget<FilledButton>(_export).onPressed, isNotNull);
  });

  testWidgets('metadata controls fit a narrow window', (tester) async {
    await _open(
      tester,
      size: const Size(360, 640),
      onApply: (_) async => false,
    );
    await _mode(tester, 'subjects', 'Set');
    await tester.enterText(_value('subjects'), 'History\nMaps');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<FilledButton>(_export).onPressed, isNotNull);
  });
}
