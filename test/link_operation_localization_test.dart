import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/link_operation_strings.dart';
import 'package:crisp_cloud/services/link_operation_failure.dart';
import 'package:crisp_cloud/services/link_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote permission failure retains legacy text and server detail', () async {
    await expectLater(LinkService.createRemoteSymlink('/target', '/link',
        (_) async => 'Permission denied: server detail'), throwsA(
      isA<LinkOperationException>()
          .having((e) => e.toString(), 'legacy', 'Exception: Permission denied creating symlink')
          .having((e) => e.arguments['detail'], 'detail', 'Permission denied: server detail'),
    ));
    expect(LinkUnsupportedError(LinkOperationCode.webUnsupported,
        'Link creation not supported on Web'), isA<UnsupportedError>());
  });
  testWidgets('link errors preserve external details in every locale', (tester) async {
    final failure = LinkOperationException(LinkOperationCode.hardlinkFailed,
        'Failed to create hard link: disk detail', {'detail': 'disk detail'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedLinkError(context, failure))),
      ));
      expect(find.textContaining('disk detail'), findsOneWidget);
      expect(find.textContaining('{detail}'), findsNothing);
    }
  });
}
