import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_batch_integrity_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_batch_integrity_service.dart';
import 'package:crisp_cloud/widgets/archive_batch_integrity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

List<int> _zip({String? password}) => ar.ZipEncoder(password: password).encode(
  ar.Archive()
    ..addFile(ar.ArchiveFile.bytes('hello.txt', utf8.encode('hello'))),
);

class _Backend extends ArchiveCreationBackend {
  Completer<void>? gate;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (gate != null) await gate!.future;
    yield* super.readFile(file);
  }
}

Future<void> _open(
  WidgetTester tester,
  _Backend backend,
  List<String> names, {
  String locale = 'en',
  double textScale = 1,
}) async {
  final run = ArchiveBatchIntegrityRun(
    source: backend,
    files: [for (final name in names) (await backend.stat('/input/$name'))!],
    spoolToDisk: false,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => ArchiveBatchIntegrityDialog(run: run),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'copies individual and batch reports with full member and snapshot hashes',
    (tester) async {
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final backend = _Backend()
        ..put('/input/first.zip', _zip())
        ..put('/input/second.zip', _zip());
      await _open(tester, backend, ['first.zip', 'second.zip']);
      expect(
        find.text(
          'Archives: 2 checked · 0 with issues · 0 skipped · 0 unchecked',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('copy-archive-report-0')));
      await tester.pump();
      final hash = sha256.convert(utf8.encode('hello')).toString();
      expect(clipboard, contains(hash));
      expect(
        clipboard,
        contains(
          sha256.convert(backend.contents['/input/first.zip']!).toString(),
        ),
      );
      expect(clipboard, contains('first.zip'));
      expect(clipboard, isNot(contains('second.zip')));
      expect(clipboard, contains('do not authenticate its publisher'));
      await tester.tap(find.byKey(const ValueKey('copy-batch-report')));
      await tester.pump();
      expect(clipboard, contains('first.zip'));
      expect(clipboard, contains('second.zip'));
      await tester.tap(find.text('View results').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('hello.txt'));
      await tester.pumpAndSettle();
      expect(find.text('SHA-256: $hash'), findsOneWidget);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveBatchIntegrityDialog), findsNothing);
      expect(backend.writes, isEmpty);
    },
  );

  testWidgets('invalid archive does not hide a later healthy result', (
    tester,
  ) async {
    final backend = _Backend()
      ..put('/input/bad.zip', [1, 2, 3])
      ..put('/input/good.zip', _zip());
    await _open(tester, backend, ['bad.zip', 'good.zip']);
    expect(
      find.text(
        'Archives: 1 checked · 1 with issues · 0 skipped · 0 unchecked',
      ),
      findsOneWidget,
    );
    expect(find.text('bad.zip'), findsOneWidget);
    expect(find.text('good.zip'), findsOneWidget);
    expect(find.text('Check incomplete or issues found'), findsOneWidget);
    expect(find.text('All regular files checked'), findsOneWidget);
  });

  testWidgets(
    'wrong password can be retried and route-owned controller survives dismissal',
    (tester) async {
      final backend = _Backend()
        ..put('/input/protected.zip', _zip(password: 'secret'));
      await _open(tester, backend, ['protected.zip']);
      expect(find.text('Password for protected.zip'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(
        find.text('The password was rejected. Try again or skip.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Archives: 1 checked · 0 with issues · 0 skipped · 0 unchecked',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'skipping a password leaves encrypted content explicitly unchecked',
    (tester) async {
      final backend = _Backend()
        ..put('/input/protected.zip', _zip(password: 'secret'));
      await _open(tester, backend, ['protected.zip']);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(
        find.text('Checked 0 · Failed 0 · Skipped 1 · Unchecked 0'),
        findsOneWidget,
      );
      expect(find.text('All regular files checked'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a pending source read waits for snapshot cleanup and reports unchecked',
    (tester) async {
      final backend = _Backend()..put('/input/pending.zip', _zip());
      final gate = Completer<void>();
      backend.gate = gate;
      await _open(tester, backend, ['pending.zip']);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text(
          'Archives: 0 checked · 0 with issues · 0 skipped · 1 unchecked',
        ),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveBatchIntegrityDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('$locale summary and long names fit a narrow enlarged dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final name = '${'long archive name 雪 ' * 8}.zip';
      final backend = _Backend()..put('/input/$name', _zip());
      await _open(tester, backend, [name], locale: locale, textScale: 1.8);
      final context = tester.element(find.byType(ArchiveBatchIntegrityDialog));
      expect(
        find.text(
          archiveBatchIntegrityText(context, 'Batch archive integrity'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(archiveBatchIntegrityText(context, 'Close')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(archiveBatchIntegrityText(context, 'Close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
