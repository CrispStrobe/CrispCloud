import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const messages = <String, String>{
    'en': 'Server request failed (HTTP 503).',
    'de': 'Serveranfrage fehlgeschlagen (HTTP 503).',
    'fr': 'Échec de la requête serveur (HTTP 503).',
    'es': 'Falló la solicitud al servidor (HTTP 503).',
    'pt': 'Falha no pedido ao servidor (HTTP 503).',
    'zh': '服务器请求失败（HTTP 503）。',
    'ja': 'サーバーへの要求に失敗しました（HTTP 503）。',
    'ko': '서버 요청 실패 (HTTP 503).',
    'ar': 'فشل طلب الخادم (HTTP 503).',
  };
  const transport = RemoteException(
    'Server request failed (HTTP 503).',
    code: RemoteErrorCode.httpStatus,
    arguments: {'status': 503},
  );

  for (final entry in messages.entries) {
    testWidgets('startup transport failure follows ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        StartupFailureApp(error: transport, locale: Locale(entry.key)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.value), findsOneWidget);
      if (entry.key != 'en') {
        expect(find.textContaining(messages['en']!), findsNothing);
      }
      if (entry.key == 'ar') {
        expect(
          Directionality.of(tester.element(find.textContaining(entry.value))),
          TextDirection.rtl,
        );
      }
    });

    testWidgets('startup nested provider details follow ${entry.key}', (
      tester,
    ) async {
      final nested = SftpOperationException(
        SftpOperationCode.listFailed,
        'legacy provider failure',
        {'path': '/旅行/{status}/data', 'error': transport},
      );
      await tester.pumpWidget(
        StartupFailureApp(error: nested, locale: Locale(entry.key)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.textContaining('/旅行/{status}/data'), findsOneWidget);
      expect(find.textContaining('legacy provider failure'), findsNothing);
    });
  }

  testWidgets('unknown startup exceptions retain diagnostic details', (
    tester,
  ) async {
    final error = StateError('unexpected initialization detail');
    await tester.pumpWidget(
      StartupFailureApp(error: error, locale: const Locale('ko')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(error.toString()), findsOneWidget);
  });

  testWidgets(
    'startup error uses supported system language and retains details',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [const Locale('es')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        const StartupFailureApp(error: 'config unavailable'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No se pudo iniciar CrispCloud:'),
        findsOneWidget,
      );
      expect(find.textContaining('config unavailable'), findsOneWidget);
    },
  );

  testWidgets('unsupported startup locale falls back to English', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StartupFailureApp(
        error: 'config unavailable',
        locale: Locale('it'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to start CrispCloud:'), findsOneWidget);
  });
}
