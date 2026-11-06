// test/widget/office_editor_dialog_test.dart
//
// Tests the F4 Office editor host: routing, slide editor loading and the safe
// rejection of legacy/ODF formats.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';

void main() {
  test('Office extensions are routed to the Office editor', () {
    expect(isOfficeFileName('report.docx'), isTrue);
    expect(isOfficeFileName('budget.xlsx'), isTrue);
    expect(isOfficeFileName('deck.pptx'), isTrue);
    expect(isOfficeFileName('legacy.ppt'), isTrue);
    expect(isOfficeFileName('notes.odt'), isTrue);
    expect(isOfficeFileName('notes.txt'), isFalse);
    expect(isOfficeFileName('README'), isFalse);
  });

  testWidgets('office load translates an oversized file error',
      (tester) async {
    const path = '/large.docx';
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OfficeEditorDialog(
          file: FileItem(name: 'large.docx', path: path, size: 65 * 1024 * 1024, isFolder: false),
          side: PanelSide.local,
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('überschreitet das Anzeigelimit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PPTX opens in the slide editor', (tester) async {
    final deck = (PptxDeckBuilder()
          ..addCoverSlide(title: 'Editable deck', subtitle: 'F4'))
        .build();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'deck.pptx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: deck,
          ),
        ),
      ),
    );

    // Font registration + controller creation are async.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(QudsSlideEditor), findsOneWidget);
    expect(find.textContaining('deck.pptx'), findsWidgets);

    // Dispose the editor surface cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DOCX opens in the Word editor with the ribbon', (tester) async {
    final bytes = (DocxDocumentBuilder()
          ..heading('Editable document')
          ..paragraph('This is a paragraph that can be formatted.'))
        .build();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'report.docx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(QudsWordEditor), findsOneWidget);
    expect(find.text('Home'), findsWidgets);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OfficeEditorDialog)),
    );
    expect(
      container.read(officeEditorMenuProvider)?.kind,
      OfficeEditorKind.word,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the editor clears the native-menu bridge safely',
      (tester) async {
    final deck = (PptxDeckBuilder()..addCoverSlide(title: 'Close me')).build();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'close.pptx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: deck,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(officeEditorMenuProvider), isNotNull);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    expect(container.read(officeEditorMenuProvider), isNull);
  });

  testWidgets('ODF/legacy files show a safe editing message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'notes.odt', isFolder: false),
            side: PanelSide.local,
            bytesOverride: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('cannot be edited safely'),
      findsOneWidget,
    );
  });
}
