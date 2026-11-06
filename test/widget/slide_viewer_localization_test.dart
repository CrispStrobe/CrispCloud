import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/widgets/pptx_slide_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('slide navigation follows the selected language', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: PptxSlideViewer(deck: SlideDeck(
        widthEmu: 160, heightEmu: 90,
        slides: [SlidePage(shapes: []), SlidePage(shapes: [])],
      ))),
    ));
    expect(find.byTooltip('Diapositiva siguiente'), findsOneWidget);
    await tester.tap(find.byTooltip('Diapositiva siguiente'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
