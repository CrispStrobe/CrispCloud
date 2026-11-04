import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/transfer_error_strings.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OperationProgress operation() => OperationProgress(
      id: 'one',
      type: OperationType.download,
      sourcePath: '/a',
      targetPath: '/b',
      fileName: 'a',
    );

void main() {
  testWidgets('transfer errors preserve old messages and localize counts',
      (tester) async {
    final op = operation();
    op.fail('1 of 2 files failed',
        code: TransferErrorCode.someFilesFailed,
        arguments: {'failed': 1, 'total': 2});
    expect(op.errorMessage, '1 of 2 files failed');
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
      final strings = TransferErrorStrings(context);
      expect(strings.error(op), contains('1'));
      expect(strings.error(op), contains('2'));
      expect(strings.text('batchFiles', {'count': 12}), contains('12'));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unknown provider errors remain unchanged', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    final op = operation()..fail('external provider detail');
    expect(TransferErrorStrings(context).error(op), 'external provider detail');
    final cancelled = operation()..cancel();
    expect(cancelled.errorMessage, 'Cancelled by user');
    expect(cancelled.errorCode, TransferErrorCode.cancelled);
  });
}
