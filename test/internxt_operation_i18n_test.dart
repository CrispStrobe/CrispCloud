import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/internxt_operation_strings.dart';
import 'package:crisp_cloud/services/internxt_operation_failure.dart';

void main() {
  testWidgets('all app-owned Internxt errors translate in supported locales',
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
        for (final code in InternxtOperationCode.values)
          localizedInternxtError(context, InternxtStateFailure(code, 'legacy')),
      ];
      expect(results[language]!.every((text) => text != 'Bad state: legacy'),
          isTrue);
      expect(localizedInternxtError(context, Exception('external')),
          'Exception: external');
    }
    for (final language in languages.skip(1)) {
      for (var i = 0; i < InternxtOperationCode.values.length; i++) {
        expect(results[language]![i], isNot(results['en']![i]),
            reason: '$language ${InternxtOperationCode.values[i]}');
      }
    }
  });

  test('error types and legacy messages remain unchanged', () {
    final unsupported = InternxtUnsupportedFailure(
        InternxtOperationCode.webDownload, 'Use browser downloads on the web.');
    final state = InternxtStateFailure(
        InternxtOperationCode.notFile, 'The selected path is not a file.');
    const format = InternxtFormatFailure(
        InternxtOperationCode.invalidName, 'Invalid remote filename.');
    expect(unsupported, isA<UnsupportedError>());
    expect(unsupported.toString(),
        UnsupportedError('Use browser downloads on the web.').toString());
    expect(state, isA<StateError>());
    expect(state.toString(),
        StateError('The selected path is not a file.').toString());
    expect(format, isA<FormatException>());
    expect(format.toString(),
        const FormatException('Invalid remote filename.').toString());
  });
}
