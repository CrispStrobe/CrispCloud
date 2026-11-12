import 'dart:typed_data';

import 'package:crisp_cloud/services/ebook_annotations.dart';
import 'package:crisp_cloud/widgets/ebook_appearance_dialog.dart';
import 'package:crisp_cloud/widgets/ebook_reading_data_dialog.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _tr(String text) => text;
const _location = EbookLocation(
  cfi: 'epubcfi(/6/2!/4/2:0)',
  fraction: .25,
  chapterTitle: 'Quarter',
);

Future<void> _dialog(
  WidgetTester tester,
  Widget dialog, {
  ValueChanged<Object?>? onResult,
}) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDialog<Object>(
                context: context,
                builder: (_) => dialog,
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'appearance edits retain layout options and honor publisher toggle',
    (tester) async {
      EbookAppearance? result;
      await _dialog(
        tester,
        const EbookAppearanceDialog(
          translate: _tr,
          appearance: EbookAppearance(
            maxColumnCount: 3,
            pageMargin: 48,
            pageWidth: 1200,
          ),
        ),
        onResult: (value) => result = value as EbookAppearance?,
      );
      final size = tester.widget<Slider>(
        find.byKey(const ValueKey('ebook-appearance-Font size')),
      );
      size.onChanged!(26);
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Apply'));
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(result!.fontSize, 26);
      expect(result!.usePublisherStyles, isFalse);
      expect(result!.maxColumnCount, 3);
      expect(result!.pageMargin, 48);
      expect(result!.pageWidth, 1200);
    },
  );

  testWidgets(
    'fixed-layout capability removes ineffective typography and page controls',
    (tester) async {
      await _dialog(
        tester,
        const EbookAppearanceDialog(
          appearance: EbookAppearance(),
          translate: _tr,
          supportsTextAppearance: false,
          supportsLayout: false,
          supportsPublisherStyles: false,
        ),
      );
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.byKey(const ValueKey('ebook-appearance-Theme')),
        findsOneWidget,
      );
      expect(find.textContaining('fixed layout'), findsOneWidget);
    },
  );

  testWidgets(
    'portable appearance keeps saved layout fields without offering them',
    (tester) async {
      EbookAppearance? result;
      await _dialog(
        tester,
        const EbookAppearanceDialog(
          appearance: EbookAppearance(
            maxColumnCount: 3,
            pageWidth: 1100,
            pageMargin: 44,
          ),
          translate: _tr,
          portable: true,
          supportsPublisherStyles: false,
        ),
        onResult: (value) => result = value as EbookAppearance?,
      );
      expect(
        find.byKey(const ValueKey('ebook-appearance-Maximum columns')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(result!.flow, 'scrolled');
      expect(result!.pageWidth, 1100);
      expect(result!.pageMargin, 44);
      expect(result!.maxColumnCount, 3);
    },
  );

  testWidgets('import previews conflicts and returns a plan without writing', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final local = await EbookAnnotations.open('local', bytes);
    local.location = _location;
    local.highlights.add(
      const EbookHighlight(
        id: 'one',
        cfi: 'epubcfi(/6/2!/4/2:0)',
        note: 'Local',
      ),
    );
    final imported = await EbookAnnotations.open('other-device', bytes);
    imported.bookmarks.add(_location);
    imported.highlights.add(
      const EbookHighlight(
        id: 'one',
        cfi: 'epubcfi(/6/2!/4/2:0)',
        note: 'Imported',
      ),
    );
    EbookReadingDataImportPlan? selected;
    await _dialog(
      tester,
      EbookReadingDataDialog(
        annotations: local,
        encoded: imported.exportReadingData(),
        translate: _tr,
      ),
      onResult: (value) => selected = value as EbookReadingDataImportPlan?,
    );
    expect(find.text('Conflicting highlights'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('ebook-reading-data-merge-mode')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge, use imported conflicts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ebook-apply-reading-data')));
    await tester.pumpAndSettle();
    expect(selected!.highlightConflicts, 1);
    expect(selected!.result.highlights.single.note, 'Imported');
    expect(local.highlights.single.note, 'Local');
    expect(
      (await SharedPreferences.getInstance()).getString(local.key),
      isNull,
    );
  });

  testWidgets('incompatible book import cannot be applied', (tester) async {
    final local = await EbookAnnotations.open('local', Uint8List.fromList([1]));
    final other = await EbookAnnotations.open('other', Uint8List.fromList([2]));
    await _dialog(
      tester,
      EbookReadingDataDialog(
        annotations: local,
        encoded: other.exportReadingData(),
        translate: _tr,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('ebook-apply-reading-data')),
          )
          .onPressed,
      isNull,
    );
    expect(local.bookmarks, isEmpty);
  });
}
