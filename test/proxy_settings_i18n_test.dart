import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/proxy_settings_strings.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/proxy_service.dart';
import 'package:crisp_cloud/widgets/proxy_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proxy translations preserve keys and parameters in all languages', () {
    final translations = ProxySettingsStrings.translations;
    expect(translations.keys.toSet(), {
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    expect(
      ProxySettingsStrings.forLanguage('de').proxy('http', 'example', 80),
      'Proxy: http example:80',
    );
  });

  final expectedLabels = {
    'en': 'Proxy Type',
    'de': 'Proxy-Typ',
    'fr': 'Type de proxy',
    'es': 'Tipo de proxy',
    'pt': 'Tipo de proxy',
    'zh': '代理类型',
    'ja': 'プロキシの種類',
    'ko': '프록시 유형',
    'ar': 'نوع الوكيل',
  };
  for (final entry in expectedLabels.entries) {
    testWidgets('proxy settings render in ${entry.key}', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(entry.key),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const Scaffold(body: ProxySettingsDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 'ar') {
        expect(
          Directionality.of(tester.element(find.text(entry.value))),
          TextDirection.rtl,
        );
      }
    });
  }

  testWidgets('SOCKS4 modes explain DNS and remove password credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyServiceProvider.overrideWithValue(
            ProxyService(
              const ProxyConfig(
                type: ProxyType.socks5,
                host: '127.0.0.1',
                port: 1080,
                username: 'user',
                password: 'secret',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: ProxySettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final password = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Password (optional)',
    );
    expect(tester.widget<TextField>(password).controller!.text, 'secret');
    await tester.tap(find.text('SOCKS5 Proxy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOCKS4 Proxy (local DNS)').last);
    await tester.pumpAndSettle();
    expect(password, findsNothing);
    expect(find.text('User ID (optional)'), findsOneWidget);
    expect(
      find.text(
        'SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('SOCKS4 Proxy (local DNS)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOCKS4a Proxy (remote DNS)').last);
    await tester.pumpAndSettle();
    expect(password, findsNothing);
    expect(
      find.text(
        'SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('SOCKS4a Proxy (remote DNS)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOCKS5 Proxy').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).controller!.text, isEmpty);
  });
}
