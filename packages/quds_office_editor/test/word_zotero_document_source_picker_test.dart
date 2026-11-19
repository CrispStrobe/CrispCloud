import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_document_sources.dart';
import 'package:quds_office_editor/src/embed/word_zotero_sources.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

ZoteroCitationItem _item(String id, String? title) =>
    ZoteroCitationItem.fromJson({
      'id': id,
      if (title != null)
        'itemData': {
          'id': id,
          'type': 'book',
          'title': title,
          'author': [
            {'given': 'Amal', 'family': 'Hassan'},
          ],
          'issued': {
            'date-parts': [
              [2026],
            ],
          },
          'DOI': '10.1234/$id',
          'abstract': 'Stored abstract with القدس and A < B.',
        },
    });

class _Result {
  bool completed = false;
  List<String>? keys;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'Visible target $finder',
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After tapping $finder');
}

Future<_Result> _open(
  WidgetTester tester,
  List<ZoteroDocumentReference> references, {
  Set<String> selected = const {},
  int otherCount = 0,
  Size size = const Size(1200, 1000),
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.keys = await showDialog<List<String>>(
                context: context,
                builder: (_) => ZoteroDocumentSourcesDialog(
                  references: references,
                  selectedKeys: selected,
                  otherSelectionCount: otherCount,
                ),
              );
              result.completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open'));
  return result;
}

Finder _list() => find.byKey(const ValueKey('zotero-document-source-list'));
Finder _scrollable() => find.descendant(
  of: _list(),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);
Finder _row(int index) => find.byKey(ValueKey('zotero-document-source-$index'));
Finder _search() => find.byKey(const ValueKey('zotero-document-source-search'));

Future<void> _showRow(WidgetTester tester, int index) async {
  await tester.ensureVisible(_list());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_search(), -160, scrollable: _scrollable());
  await tester.scrollUntilVisible(_row(index), 120, scrollable: _scrollable());
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, int index) async {
  await _showRow(tester, index);
  await _tap(
    tester,
    find.descendant(of: _row(index), matching: find.byType(Checkbox)),
  );
}

Future<void> _filter(WidgetTester tester, String query) async {
  await tester.ensureVisible(_list());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_search(), -160, scrollable: _scrollable());
  await tester.ensureVisible(_search());
  await tester.pumpAndSettle();
  await tester.enterText(_search(), query);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _apply(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('zotero-document-sources-apply')));

void main() {
  testWidgets('stages selection changes and returns their selection order', (
    tester,
  ) async {
    final references = zoteroDocumentReferences([
      _item('alpha', 'Alpha source'),
      _item('beta', 'Beta source'),
      _item('gamma', 'Gamma source'),
    ]);
    final original = {references[0].selectionKey};
    final before = jsonEncode(references.map((r) => r.item.toJson()).toList());
    final result = await _open(tester, references, selected: original);

    await _select(tester, 2);
    await _select(tester, 0);
    await _select(tester, 1);
    expect(result.completed, isFalse);
    expect(original, {references[0].selectionKey});
    await _apply(tester);

    expect(result.completed, isTrue);
    expect(result.keys, [
      references[2].selectionKey,
      references[1].selectionKey,
    ]);
    expect(original, {references[0].selectionKey});
    expect(jsonEncode(references.map((r) => r.item.toJson()).toList()), before);
  });

  testWidgets(
    'search keeps hidden selections and retains original source keys',
    (tester) async {
      final references = zoteroDocumentReferences([
        _item('same', 'First duplicate'),
        _item('same', 'Second duplicate'),
      ]);
      final result = await _open(tester, references);

      await _select(tester, 1);
      await _filter(tester, 'First Hassan 2026');
      expect(
        find.text('1 selected reference(s) outside these results.'),
        findsOneWidget,
      );
      expect(find.text('1 of 2 shown · 1 selected here'), findsOneWidget);
      await _select(tester, 0);
      await _filter(tester, 'no matching record');
      expect(
        find.text('No cited references match this search.'),
        findsOneWidget,
      );
      expect(
        find.text('2 selected reference(s) outside these results.'),
        findsOneWidget,
      );
      await _apply(tester);

      expect(result.keys, [
        references[1].selectionKey,
        references[0].selectionKey,
      ]);
    },
  );

  testWidgets(
    'global limit includes other tabs and still permits deselection',
    (tester) async {
      final references = zoteroDocumentReferences([
        _item('alpha', 'Alpha source'),
        _item('beta', 'Beta source'),
      ]);
      final result = await _open(
        tester,
        references,
        selected: {references[0].selectionKey},
        otherCount: 19,
      );

      await _select(tester, 1);
      expect(
        find.text('Select at most 20 sources per citation across all tabs.'),
        findsOneWidget,
      );
      expect(tester.widget<CheckboxListTile>(_row(1)).value, isFalse);
      await _select(tester, 0);
      expect(
        find.byKey(const ValueKey('zotero-document-source-error')),
        findsNothing,
      );
      await _select(tester, 1);
      await _apply(tester);

      expect(result.keys, [references[1].selectionKey]);
    },
  );

  testWidgets('nested details preserve filtered draft and cancellation', (
    tester,
  ) async {
    final references = zoteroDocumentReferences([
      _item('alpha', 'Alpha source'),
      _item('beta', 'Beta source'),
    ]);
    final selected = {references[0].selectionKey};
    final result = await _open(tester, references, selected: selected);

    await _select(tester, 0);
    await _filter(tester, '10.1234/beta');
    await _select(tester, 1);
    await _tap(
      tester,
      find.byKey(const ValueKey('zotero-document-source-details-1')),
    );
    expect(
      find.byKey(const ValueKey('zotero-stored-reference-details-dialog')),
      findsOneWidget,
    );
    expect(
      find.text('Metadata stored with this reference. No updates are fetched.'),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('zotero-stored-details-close')),
    );
    expect(
      tester.widget<TextField>(_search()).controller!.text,
      '10.1234/beta',
    );
    expect(tester.widget<CheckboxListTile>(_row(1)).value, isTrue);
    expect(selected, {references[0].selectionKey});
    await _tap(
      tester,
      find.byKey(const ValueKey('zotero-document-sources-cancel')),
    );

    expect(result.completed, isTrue);
    expect(result.keys, isNull);
    expect(selected, {references[0].selectionKey});
  });

  testWidgets('missing metadata and occurrence count remain explicit', (
    tester,
  ) async {
    final source = _item('identity-only', null);
    final result = await _open(
      tester,
      zoteroDocumentReferences([source, source]),
    );

    await _showRow(tester, 0);
    expect(find.text('identity-only'), findsOneWidget);
    expect(
      find.text(
        '2 citation occurrence(s)\nNo stored bibliographic details; retained source identity only',
      ),
      findsOneWidget,
    );
    await _select(tester, 0);
    await _apply(tester);

    expect(result.keys, hasLength(1));
    expect(source.itemData, isNull);
  });

  testWidgets('empty document offers a harmless empty selection', (
    tester,
  ) async {
    final result = await _open(tester, zoteroDocumentReferences([]));

    expect(find.text('No cited references in this document.'), findsOneWidget);
    await _apply(tester);

    expect(result.completed, isTrue);
    expect(result.keys, isEmpty);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'narrow doubled-text picker and details remain usable in $direction',
      (tester) async {
        final references = zoteroDocumentReferences([
          _item(
            'alpha',
            'A long cited source with القدس and identifying words',
          ),
          _item('beta', 'Another source'),
        ]);
        final result = await _open(
          tester,
          references,
          size: const Size(320, 480),
          textScale: 2,
          direction: direction,
        );

        await _filter(tester, 'القدس');
        await _select(tester, 0);
        await _tap(
          tester,
          find.byKey(const ValueKey('zotero-document-source-details-0')),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('zotero-stored-details-close')),
        );
        await _filter(tester, 'no matching source');
        await _tap(tester, find.byTooltip('Clear cited reference search'));
        await _apply(tester);

        expect(result.completed, isTrue);
        expect(result.keys, [references[0].selectionKey]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
