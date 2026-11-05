import 'package:crisp_cloud/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup error uses supported system language and retains details',
      (tester) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('es')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const StartupFailureApp(error: 'config unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo iniciar CrispCloud:'), findsOneWidget);
    expect(find.textContaining('config unavailable'), findsOneWidget);
  });

  testWidgets('unsupported startup locale falls back to English', (tester) async {
    await tester.pumpWidget(const StartupFailureApp(
      error: 'config unavailable', locale: Locale('it'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to start CrispCloud:'), findsOneWidget);
  });
}
