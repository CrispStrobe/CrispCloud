import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_library.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<void> _inspect(WidgetTester tester, Widget details) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => details,
            ),
            child: const Text('Inspect'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Inspect'));
  await tester.pumpAndSettle();
}

ZoteroItem _catalog(ZoteroLibrary library) => ZoteroItem(
  library: library,
  key: 'ABCD1234',
  title: 'Research details',
  itemType: 'book',
);

ZoteroCitationItem _stored(List<String> uris) => ZoteroCitationItem.fromJson({
  'id': 'original-reference',
  'uris': uris,
  'itemData': {'type': 'book', 'title': 'Cited work'},
});

void main() {
  final openButton = find.byKey(const ValueKey('zotero-open-in-desktop'));

  testWidgets('local catalog details open Zotero without mutating metadata', (
    tester,
  ) async {
    final calls = <Uri>[];
    final item = _catalog(ZoteroLibrary.localUser());
    await _inspect(
      tester,
      ZoteroItemDetailsDialog(
        item: item,
        activeTags: const [],
        onOpenInZotero: (uri) async {
          calls.add(uri);
          return true;
        },
      ),
    );
    expect(openButton, findsOneWidget);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    expect(calls.map((uri) => uri.toString()).toList(), [
      'zotero://select/library/items/ABCD1234',
    ]);
    expect(item.citationUri, isNull);
    expect(find.byKey(const ValueKey('zotero-item-details-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web personal item has no unsafe desktop selection action', (
    tester,
  ) async {
    await _inspect(
      tester,
      ZoteroItemDetailsDialog(
        item: _catalog(ZoteroLibrary.user(42)),
        activeTags: const [],
        onOpenInZotero: (_) async {
          fail('A remote personal ID is not the active desktop profile.');
        },
      ),
    );
    expect(openButton, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group catalog item forwards the stable group selection URI', (
    tester,
  ) async {
    Uri? launched;
    await _inspect(
      tester,
      ZoteroItemDetailsDialog(
        item: _catalog(ZoteroLibrary.group(731)),
        activeTags: const [],
        onOpenInZotero: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    expect(launched.toString(), 'zotero://select/groups/731/items/ABCD1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored source navigation preserves citation metadata', (
    tester,
  ) async {
    final item = _stored([
      'http://zotero.org/users/local/LOCALKEY/items/ABCD1234',
    ]);
    final original = jsonEncode(item.toJson());
    Uri? launched;
    await _inspect(
      tester,
      ZoteroStoredReferenceDetailsDialog(
        item: item,
        onOpenInZotero: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    expect(launched.toString(), 'zotero://select/library/items/ABCD1234');
    expect(jsonEncode(item.toJson()), original);
    expect(find.byKey(const ValueKey('zotero-stored-reference-details-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed desktop launch reports failure without closing details', (
    tester,
  ) async {
    final item = _stored([
      'http://zotero.org/groups/731/items/ABCD1234',
    ]);
    var attempts = 0;
    await _inspect(
      tester,
      ZoteroStoredReferenceDetailsDialog(
        item: item,
        onOpenInZotero: (_) async {
          attempts++;
          return false;
        },
      ),
    );
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Zotero could not be opened on this device.'), findsOneWidget);
    expect(find.byKey(const ValueKey('zotero-stored-reference-details-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline and conflicting stored identities cannot open a URI', (
    tester,
  ) async {
    for (final item in [
      _stored([]),
      _stored(['https://zotero.org/users/42/items/ABCD1234']),
      _stored([
        'http://zotero.org/groups/731/items/ABCD1234',
        'http://zotero.org/groups/732/items/ABCD1234',
      ]),
    ]) {
      await _inspect(
        tester,
        ZoteroStoredReferenceDetailsDialog(item: item),
      );
      expect(openButton, findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
