import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/rename_names_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['de', 'ar']) {
    testWidgets(
      'name editing works at large text in $language without changing filenames',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<String>? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<List<String>>(
                      context: context,
                      builder: (_) => const RenameNamesDialog(
                        names: ['Cancel.txt', '{1}.txt'],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            language == 'de'
                ? 'Vorgeschlagene Namen bearbeiten'
                : 'تحرير الأسماء المقترحة',
          ),
          findsOneWidget,
        );
        final input = find.byKey(const ValueKey('rename-names-input'));
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Cancel.txt\n{1}.txt',
        );
        final direction = Directionality.of(tester.element(input));
        expect(
          direction,
          language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('rename-names-apply')),
        );
        await tester.tap(find.byKey(const ValueKey('rename-names-apply')));
        await tester.pumpAndSettle();
        expect(result, ['Cancel.txt', '{1}.txt']);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(RenameNamesDialog), findsNothing);
      },
    );
  }
}
