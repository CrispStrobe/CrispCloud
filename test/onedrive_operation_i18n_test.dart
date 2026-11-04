import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/onedrive_operation_strings.dart';
import 'package:crisp_cloud/services/onedrive_operation_failure.dart';

void main() {
  testWidgets('every OneDrive operation is translated and preserves details',
      (tester) async {
    const languages = ['en', 'ar', 'de', 'es', 'fr', 'ja', 'ko', 'pt', 'zh'];
    final results = <String, List<String>>{};
    for (final language in languages) {
      late BuildContext context;
      await tester.pumpWidget(Localizations(
        locale: Locale(language),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      results[language] = [
        for (final code in OneDriveOperationCode.values)
          localizedOneDriveError(
              context,
              OneDriveOperationFailure(code, 'legacy', {
                'status': 418,
                'body': 'remote {path}',
                'path': '/user/{status}',
              })),
      ];
      expect(results[language]!.every((text) => text != 'legacy'), isTrue);
      expect(results[language]![OneDriveOperationCode.list.index],
          contains('418'));
      expect(results[language]![OneDriveOperationCode.list.index],
          contains('remote {path}'));
      expect(results[language]![OneDriveOperationCode.downloadUrl.index],
          contains('/user/{status}'));
      expect(localizedOneDriveError(context, Exception('external')),
          'Exception: external');
    }
    for (final language in languages.skip(1)) {
      for (var i = 0; i < OneDriveOperationCode.values.length; i++) {
        expect(results[language]![i], isNot(results['en']![i]),
            reason: '$language ${OneDriveOperationCode.values[i]}');
      }
    }
  });

  test('legacy exception and argument snapshot are preserved', () {
    final arguments = <String, Object>{'path': '/original'};
    final error = OneDriveOperationFailure(OneDriveOperationCode.downloadUrl,
        'No download URL for: /original', arguments);
    arguments['path'] = '/changed';
    expect(error.toString(), 'Exception: No download URL for: /original');
    expect(error.arguments['path'], '/original');
  });
}
