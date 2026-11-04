import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/audit_log_strings.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/audit_service.dart';
import 'package:crisp_cloud/widgets/audit_log_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuditFixture extends AuditService {
  @override
  Future<List<AuditEntry>> getRecent(int count) async => [
        AuditEntry(
          timestamp: DateTime(2026, 11, 4),
          operation: AuditOperation.createFolder,
          sourcePath: '/folder',
          success: true,
        )
      ];
}

void main() {
  test('audit log messages cover all supported languages', () {
    final translations = AuditLogStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    expect(keys, containsAll(['Create folder', 'Sync', 'Clear Audit Log']));
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), keys, reason: entry.key);
      expect(entry.value.values.every((s) => s.isNotEmpty), isTrue,
          reason: entry.key);
    }
  });

  testWidgets('audit dialog localizes both controls and operations',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [auditServiceProvider.overrideWithValue(_AuditFixture())],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showAuditLogDialog(context),
            child: const Text('Open'),
          );
        })),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Audit-Protokoll'), findsOneWidget);
    expect(find.text('Ordner erstellen'), findsOneWidget);
    expect(find.text('/folder'), findsOneWidget);
  });
}
