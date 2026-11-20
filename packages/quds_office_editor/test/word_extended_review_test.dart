import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const meta =
    'w:id="13" w:author="Original reviewer" w:date="2026-11-19T10:00:00Z"';
WmlDocument read(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

WmlDocument formatting() => read(
  '<w:p><w:pPr><w:jc w:val="center"/><w:pPrChange $meta><w:pPr><w:jc w:val="right"/></w:pPr></w:pPrChange></w:pPr><w:r><w:rPr><w:b/><w:rPrChange $meta><w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr><w:t>Formatted text</w:t></w:r></w:p>',
);
WmlDocument moves() => read(
  '<w:p><w:moveFromRangeStart w:id="2" w:name="paired"/><w:moveFrom $meta><w:r><w:t>Original place</w:t></w:r></w:moveFrom><w:moveFromRangeEnd w:id="2"/></w:p><w:p><w:moveToRangeStart w:id="4" w:name="paired"/><w:moveTo $meta><w:r><w:t>New place</w:t></w:r></w:moveTo><w:moveToRangeEnd w:id="4"/></w:p>',
);
WordEditorController controller(WmlDocument d) {
  final c = WordEditorController(document: d);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reject formatting and Undo/Redo restore both properties and attribution',
    () {
      final c = controller(formatting());
      final change = c.document.revisions.firstWhere(
        (r) => r.kind == WmlRevisionKind.runFormat,
      );
      c.rejectRevision(change);
      WmlRun current() =>
          c.document.paragraphs.first.inlines.whereType<WmlRun>().first;
      expect(current().properties.italic, isTrue);
      expect(current().properties.bold, isFalse);
      c.undo();
      expect(current().properties.bold, isTrue);
      expect(c.document.revisions, contains(same(change)));
      c.redo();
      expect(current().properties.italic, isTrue);
      expect(c.document.revisions, hasLength(1));
    },
  );
  test('paragraph formatting decision Undo restores paragraph properties', () {
    final c = controller(formatting());
    final change = c.document.revisions.firstWhere(
      (r) => r.kind == WmlRevisionKind.paragraphFormat,
    );
    c.rejectRevision(change);
    expect(
      c.document.paragraphs.first.properties.justification,
      WmlJustification.right,
    );
    c.undo();
    expect(
      c.document.paragraphs.first.properties.justification,
      WmlJustification.center,
    );
    expect(c.document.revisions, contains(same(change)));
    c.redo();
    expect(
      c.document.paragraphs.first.properties.justification,
      WmlJustification.right,
    );
  });
  for (final accept in [true, false]) {
    test(
      'one ${accept ? 'accept' : 'reject'} move decision and Undo restore both paragraphs',
      () {
        final c = controller(moves());
        final changes = List<WmlRevision>.of(c.document.revisions);
        c.selectRevision(changes.last);
        if (accept) {
          c.acceptRevision(changes.last);
        } else {
          c.rejectRevision(changes.last);
        }
        expect(c.document.revisions, isEmpty);
        expect(
          c.document.paragraphs.map((p) => p.text),
          accept ? ['', 'New place'] : ['Original place', ''],
        );
        c.undo();
        expect(c.document.paragraphs.map((p) => p.text), [
          'Original place',
          'New place',
        ]);
        expect(c.document.revisions, orderedEquals(changes));
        c.redo();
        expect(c.document.revisions, isEmpty);
      },
    );
  }
  testWidgets(
    'live pane labels formatting separately and does not strike it out',
    (tester) async {
      final c = controller(formatting());
      c.selectRevision(
        c.document.revisions.firstWhere(
          (r) => r.kind == WmlRevisionKind.runFormat,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordReviewPane(
              controller: c,
              initialTab: WordReviewPaneTab.changes,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Text formatting · Original reviewer'), findsOneWidget);
      final detail = tester.widget<Text>(
        find.byKey(const ValueKey('live-review-selected-text')),
      );
      expect(detail.style?.decoration, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'live pane shows named move destination and paired accept works',
    (tester) async {
      final c = controller(moves());
      c.selectRevision(c.document.revisions.last);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordReviewPane(
              controller: c,
              initialTab: WordReviewPaneTab.changes,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Moved to · Original reviewer'), findsOneWidget);
      c.acceptRevision(c.document.revisions.last);
      await tester.pump();
      expect(c.document.revisions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
