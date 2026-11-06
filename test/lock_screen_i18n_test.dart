import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lock screen shows translated labels and verification errors',
      (tester) async {
    final service = AppLockService(InMemorySecureStorage());
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: LockScreen(lockService: service, onUnlocked: () {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('CrispCloud está bloqueado'), findsOneWidget);
    expect(find.text('Introduce tu PIN o contraseña para continuar'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    expect(find.text('PIN o contraseña incorrectos'), findsOneWidget);
    expect(find.text('Quedan 4 intentos'), findsOneWidget);
  });
}
