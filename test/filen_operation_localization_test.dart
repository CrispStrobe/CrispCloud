import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/filen_operation_strings.dart';
import 'package:crisp_cloud/services/filen_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Filen failures preserve the legacy exception text', () {
    final failure = FilenOperationFailure(FilenOperationCode.unresolvedPath,
        'Could not resolve path: /docs', {'path': '/docs'});
    expect(failure, isA<Exception>());
    expect(failure.toString(), 'Exception: Could not resolve path: /docs');
  });
  testWidgets('path errors retain the original path in every locale', (tester) async {
    final failure = FilenOperationFailure(FilenOperationCode.unresolvedSource,
        'Could not resolve source path: /docs', {'path': '/docs'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedFilenError(context, failure))),
      ));
      expect(find.textContaining('/docs'), findsOneWidget);
      expect(find.textContaining('{path}'), findsNothing);
    }
  });
}
