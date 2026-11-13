import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_batch_extraction_strings.dart';
import 'package:crisp_cloud/widgets/archive_batch_extraction_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/archive_creation_backend.dart';

List<int> _zip({String member = 'hello.txt', String? password}) =>
    ar.ZipEncoder(password: password).encode(
      ar.Archive()..addFile(ar.ArchiveFile.bytes(member, utf8.encode('hello'))),
    );

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _open(
  WidgetTester tester,
  ArchiveCreationBackend backend,
  String target, {
  List<String> names = const ['first.zip'],
  String language = 'en',
  double scale = 1,
}) async {
  final files = [
    for (final name in names) (await backend.stat('/input/$name'))!,
  ];
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showArchiveBatchExtractionDialog(
              context,
              source: backend,
              files: files,
              targetDirectory: target,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('batch-extraction-widget-');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  testWidgets(
    'preview is separate from extraction and copyable results name published files',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final backend = ArchiveCreationBackend()..put('/input/first.zip', _zip());
      final target = p.join(temp.path, 'out');
      await _open(tester, backend, target);
      expect(
        find.byKey(const ValueKey('batch-extraction-extract')),
        findsNothing,
      );
      expect(Directory(target).existsSync(), isFalse);
      await tester.tap(find.byKey(const ValueKey('batch-extraction-preview')));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('batch-extraction-preview-summary')),
      );
      expect(
        find.text('No destination files have been written.'),
        findsOneWidget,
      );
      expect(Directory(target).existsSync(), isFalse);
      await tester.tap(find.byKey(const ValueKey('batch-extraction-extract')));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('batch-extraction-report-summary')),
      );
      expect(
        File(p.join(target, 'first/hello.txt')).readAsStringSync(),
        'hello',
      );
      expect(
        find.text(
          'Result: 1 completed · 1 files written · 0 skipped · 0 unprocessed',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('copy-batch-extraction-report')),
      );
      await tester.pump();
      expect(copied, contains('first.zip'));
      expect(copied, contains(p.join(target, 'first/hello.txt')));
      expect(copied, contains('SHA-256:'));
      expect(copied, contains('Completed'));
      expect(backend.writes, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('editing the mask invalidates the reviewed plan', (tester) async {
    final backend = ArchiveCreationBackend()..put('/input/first.zip', _zip());
    final target = p.join(temp.path, 'out');
    await _open(tester, backend, target);
    await tester.tap(find.byKey(const ValueKey('batch-extraction-preview')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey('batch-extraction-preview-summary')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('batch-extraction-mask')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('batch-extraction-mask')),
      '*.png',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('batch-extraction-preview-summary')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('batch-extraction-extract')),
      findsNothing,
    );
    expect(Directory(target).existsSync(), isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  });

  testWidgets(
    'existing-file collision remains a preview error with no extract action',
    (tester) async {
      final backend = ArchiveCreationBackend()..put('/input/first.zip', _zip());
      final target = p.join(temp.path, 'out');
      final existing = File(p.join(target, 'first/hello.txt'));
      existing.parent.createSync(recursive: true);
      existing.writeAsStringSync('keep');
      await _open(tester, backend, target);
      await tester.tap(find.byKey(const ValueKey('batch-extraction-preview')));
      await _waitFor(tester, find.textContaining('Destination exists:'));
      expect(
        find.byKey(const ValueKey('batch-extraction-extract')),
        findsNothing,
      );
      expect(existing.readAsStringSync(), 'keep');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('protected archive can retry its password before preview', (
    tester,
  ) async {
    final backend = ArchiveCreationBackend()
      ..put('/input/first.zip', _zip(password: 'secret'));
    await _open(tester, backend, p.join(temp.path, 'out'));
    await tester.tap(find.byKey(const ValueKey('batch-extraction-preview')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey('batch-extraction-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('batch-extraction-password')),
      'wrong',
    );
    await tester.tap(find.text('Unlock'));
    await _waitFor(
      tester,
      find.text('The password was rejected or the protected data is damaged.'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('batch-extraction-password')),
      'secret',
    );
    await tester.tap(find.text('Unlock'));
    await _waitFor(
      tester,
      find.byKey(const ValueKey('batch-extraction-preview-summary')),
    );
    expect(
      find.byKey(const ValueKey('batch-extraction-password')),
      findsNothing,
    );
    expect(find.text('secret'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  });

  for (final language in [
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  ]) {
    testWidgets('$language dialog fits a narrow window with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = ArchiveCreationBackend()..put('/input/first.zip', _zip());
      await _open(
        tester,
        backend,
        p.join(temp.path, 'out'),
        language: language,
        scale: 1.6,
      );
      final context = tester.element(find.byType(ArchiveBatchExtractionDialog));
      expect(
        find.text(
          archiveBatchExtractionText(context, 'Batch archive extraction'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(archiveBatchExtractionText(context, 'Preview')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('batch-extraction-flatten')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(archiveBatchExtractionText(context, 'Close')));
      await tester.pumpAndSettle();
    });
  }
}
