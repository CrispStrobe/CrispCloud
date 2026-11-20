import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/widgets/pdf_open_settings.dart';
import 'package:crisp_cloud/services/pdf_open_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'settings expose defaults, secondary engines and Shift+F4 behavior',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: PdfOpenSettings())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF viewers and editors'));
      await tester.pumpAndSettle();
      expect(find.text('Default PDF viewer (F3)'), findsOneWidget);
      expect(find.text('Default PDF editor (F4)'), findsOneWidget);
      expect(find.text('Secondary PDF viewer'), findsOneWidget);
      expect(find.text('Secondary PDF editor'), findsOneWidget);
      final drop = find.byType(DropdownButtonFormField<PdfAlternateEditAction>);
      await tester.ensureVisible(drop);
      await tester.tap(drop);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open secondary PDF editor').last);
      await tester.pumpAndSettle();
      expect(
        (await PdfOpenPreferences.load()).shiftF4,
        PdfAlternateEditAction.secondary,
      );
    },
  );
}
