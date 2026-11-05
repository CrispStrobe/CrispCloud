import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/ftp_operation_strings.dart';
import 'package:crisp_cloud/services/ftp_operation_failure.dart';

void main() {
  testWidgets('FTP errors translate and retain paths and external details',
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
        for (final code in FtpOperationCode.values)
          localizedFtpError(
              context,
              FtpOperationFailure(code, 'legacy', {
                'path': '/user/{error}',
                'error': 'server {path}',
              })),
      ];
      expect(results[language]!.every((text) => text != 'legacy'), isTrue);
      expect(results[language]![FtpOperationCode.list.index],
          contains('/user/{error}'));
      expect(results[language]![FtpOperationCode.list.index],
          contains('server {path}'));
      expect(localizedFtpError(context, Exception('external')),
          'Exception: external');
      final nested = FtpOperationFailure(FtpOperationCode.connectionError,
          'Connection failed: Exception: FTP connection failed', {
        'error': FtpOperationFailure(
            FtpOperationCode.connectionFailed, 'FTP connection failed'),
      });
      expect(
          localizedFtpError(context, nested),
          contains(
              results[language]![FtpOperationCode.connectionFailed.index]));
    }
    for (final language in languages.skip(1)) {
      for (var i = 0; i < FtpOperationCode.values.length; i++) {
        expect(results[language]![i], isNot(results['en']![i]),
            reason: '$language ${FtpOperationCode.values[i]}');
      }
    }
  });

  test('legacy text, unsupported type and argument snapshot are preserved', () {
    final arguments = <String, Object>{'path': '/original'};
    final error = FtpOperationFailure(FtpOperationCode.download,
        'FTP download failed for /original', arguments);
    arguments['path'] = '/changed';
    expect(error.toString(), 'Exception: FTP download failed for /original');
    expect(error.arguments['path'], '/original');
    expect(FtpWebUnsupportedFailure(), isA<UnsupportedError>());
    expect(FtpWebUnsupportedFailure().toString(),
        'Unsupported operation: FTP is not supported on Web');
  });
}
