import 'dart:typed_data';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_viewer_error_strings.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('archive error retains legacy message and exception type', () {
    expect(() => decompressSingleFile(Uint8List(0), 'plain.txt'), throwsA(
      isA<ArchiveViewException>()
          .having((e) => e.code, 'code', ArchiveMessageCode.singleFormat)
          .having((e) => e.toString(), 'legacy', 'Not a single-file compressed format: plain.txt'),
    ));
  });
  testWidgets('archive error retains safety limit and external detail in each locale', (tester) async {
    const error = ArchiveViewException('legacy', code: ArchiveMessageCode.archiveLimit,
        arguments: {'limit': '64 MB', 'detail': 'remote detail'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedArchiveViewerError(context, error))),
      ));
      expect(find.textContaining('64 MB'), findsOneWidget);
      expect(find.textContaining('remote detail'), findsOneWidget);
      expect(find.textContaining('{limit}'), findsNothing);
    }
  });
}
