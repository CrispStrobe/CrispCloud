import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_bytes_error_strings.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('German byte-loading errors retain paths and OS details',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    final error = FileBytesLoadException(
      'Could not read "/a": denied',
      code: FileBytesErrorCode.couldNotRead,
      arguments: const {'path': '/a', 'error': 'denied'},
    );
    expect(error.toString(), 'Could not read "/a": denied');
    expect(localizedFileBytesError(context, error),
        '„/a“ konnte nicht gelesen werden: denied');
    expect(
        localizedFileBytesError(
            context, const FileBytesLoadException('external detail')),
        'external detail');
  });

  testWidgets('file size limits are presented in all nine locales',
      (tester) async {
    final error = FileBytesTooLargeException(2048, 1024);
    expect(error, isA<FileBytesLoadException>());
    expect(error.message, 'File is 2 KB — larger than the 1 KB view limit.');
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      final text = localizedFileBytesError(context, error);
      expect(text, contains('2 KB'));
      expect(text, contains('1 KB'));
      expect(text, isNot(contains('{')));
      expect(tester.takeException(), isNull);
    }
  });
}
