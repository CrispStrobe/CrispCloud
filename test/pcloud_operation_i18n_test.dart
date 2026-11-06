import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/pcloud_operation_strings.dart';
import 'package:crisp_cloud/services/pcloud_operation_failure.dart';

void main() {
  testWidgets('every pCloud error is translated and preserves remote details',
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
        for (final code in PCloudOperationCode.values)
          localizedPCloudError(
              context,
              PCloudOperationFailure(code, 'legacy', {
                'status': 418,
                'result': 2001,
                'body': 'remote {path}',
                'path': '/user/{status}',
                'endpoint': 'listfolder',
              })),
      ];
      expect(results[language]!.every((text) => text != 'legacy'), isTrue);
      expect(results[language]![PCloudOperationCode.endpointHttp.index],
          contains('418'));
      expect(results[language]![PCloudOperationCode.endpointHttp.index],
          contains('listfolder'));
      expect(results[language]![PCloudOperationCode.endpointHttp.index],
          contains('remote {path}'));
      expect(results[language]![PCloudOperationCode.fileNotFound.index],
          contains('/user/{status}'));
      expect(localizedPCloudError(context, Exception('external')),
          'Exception: external');
    }
    for (final language in languages.skip(1)) {
      for (var i = 0; i < PCloudOperationCode.values.length; i++) {
        expect(results[language]![i], isNot(results['en']![i]),
            reason: '$language ${PCloudOperationCode.values[i]}');
      }
    }
  });

  test('legacy text and argument snapshot are preserved', () {
    final arguments = <String, Object>{'path': '/original'};
    final error = PCloudOperationFailure(PCloudOperationCode.fileNotFound,
        'pCloud file not found: /original', arguments);
    arguments['path'] = '/changed';
    expect(error.toString(), 'Exception: pCloud file not found: /original');
    expect(error.arguments['path'], '/original');
  });
}
