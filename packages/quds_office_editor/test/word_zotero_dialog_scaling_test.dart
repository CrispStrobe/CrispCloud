import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _CountingController extends WordEditorController {
  _CountingController({required super.document});

  int fieldScans = 0;

  @override
  List<WmlZoteroField> get zoteroFields {
    fieldScans++;
    return super.zoteroFields;
  }
}

WmlDocument _citationDocument(int count) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (var index = 0; index < count; index++) _citationParagraph(index),
      ],
    ),
  ],
);

WmlParagraph _citationParagraph(int index) {
  final paragraph = WmlParagraph();
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation(
      citationId: 'citation-$index',
      plainCitation: '(Source $index)',
      items: [
        ZoteroCitationItem.fromJson({
          'id': index,
          'itemData': {'id': index, 'type': 'book', 'title': 'Source $index'},
        }),
      ],
    ),
  );
  return paragraph;
}

Future<void> _open(WidgetTester tester, _CountingController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: ZoteroSession(),
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open references'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening references scans a 1000-citation document once', (
    tester,
  ) async {
    final controller = _CountingController(document: _citationDocument(1000));
    await _open(tester, controller);
    // The initial Library view constructs Document actions too. Opening the
    // workspace must not repeatedly parse all citation JSON for these buttons.
    expect(controller.fieldScans, 1);
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Basic bibliography'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Copy embedded CSL JSON'),
          )
          .onPressed,
      isNotNull,
    );
    expect(controller.contentRevision, 0);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bibliography-only documents keep source actions disabled', (
    tester,
  ) async {
    final controller = _CountingController(
      document: WmlDocument(
        sections: [
          WmlSection(
            blocks: [WordZotero.bibliography(text: 'Existing bibliography')],
          ),
        ],
      ),
    );
    await _open(tester, controller);
    expect(controller.fieldScans, 1);
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Basic bibliography'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Copy embedded CSL JSON'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
