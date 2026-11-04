import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/smb_operation_strings.dart';
import 'package:crisp_cloud/services/smb_operation_failure.dart';

void main() {
  testWidgets('all app-owned SMB errors translate in supported locales',
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
        for (final code in SmbOperationCode.values)
          localizedSmbError(context, SmbStateFailure(code, 'legacy')),
      ];
      expect(results[language]!.every((text) => text != 'legacy'), isTrue);
      expect(localizedSmbError(context, Exception('external')),
          'Exception: external');
    }
    for (final language in languages.skip(1)) {
      for (var i = 0; i < SmbOperationCode.values.length; i++) {
        expect(results[language]![i], isNot(results['en']![i]),
            reason: '$language ${SmbOperationCode.values[i]}');
      }
    }
  });

  test('error types and legacy text remain unchanged', () {
    final unsupported = SmbUnsupportedFailure(
        SmbOperationCode.unsupported, 'SMB requires the installed app.');
    final state = SmbStateFailure(
        SmbOperationCode.notConnected, 'Connect to an SMB share first.');
    const format = SmbFormatFailure(
        SmbOperationCode.invalidLogin, 'Use username@smb://host/share/.');
    expect(unsupported, isA<UnsupportedError>());
    expect(unsupported.toString(),
        UnsupportedError('SMB requires the installed app.').toString());
    expect(state, isA<StateError>());
    expect(state.toString(),
        StateError('Connect to an SMB share first.').toString());
    expect(format, isA<FormatException>());
    expect(format.toString(),
        const FormatException('Use username@smb://host/share/.').toString());
  });
}
