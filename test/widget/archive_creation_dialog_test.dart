import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/archive_creation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

class _RecordingService extends ArchiveCreationService {
  final List<ArchiveCreationOptions> requests = [];
  String? destinationPath;
  @override
  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async {
    requests.add(options);
    destinationPath = destinationDirectory;
    return ArchiveCreationResult(
      '$destinationDirectory/${options.name}',
      files.length,
      100,
    );
  }
}

void main() {
  late _RecordingService service;
  late ArchiveCreationBackend backend;

  setUp(() {
    service = _RecordingService();
    backend = ArchiveCreationBackend()..put('/input/report.txt', [1, 2, 3]);
  });

  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = (await backend.stat('/input/report.txt'))!;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ArchiveCreationDialog(
            source: backend,
            destination: backend,
            files: [file],
            destinationDirectory: '/output',
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('archive-create-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('archive-create-submit')));
    await tester.pumpAndSettle();
  }

  Future<void> format(WidgetTester tester, String label) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('archive-create-format')),
    );
    await tester.tap(find.byKey(const ValueKey('archive-create-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'format changes update the filename and show only real codec choices',
    (tester) async {
      await show(tester);
      await format(tester, '7z');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('archive-create-name')),
            )
            .controller!
            .text,
        'report.7z',
      );
      final compression = tester
          .widget<DropdownButtonFormField<ArchiveCreationCompression>>(
            find.byKey(const ValueKey('archive-create-compression-sevenZip')),
          );
      expect(compression.initialValue, ArchiveCreationCompression.lzma2);
      await format(tester, 'TAR');
      expect(
        find.byKey(const ValueKey('archive-create-protect')),
        findsNothing,
      );
      await submit(tester);
      expect(service.requests.single.format, ArchiveCreationFormat.tar);
      expect(
        service.requests.single.compression,
        ArchiveCreationCompression.none,
      );
      expect(service.requests.single.password, isNull);
      expect(service.destinationPath, '/output');
      expect(
        find.byKey(const ValueKey('archive-create-success')),
        findsOneWidget,
      );
    },
  );

  testWidgets('password confirmation and filename validation block writes', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
    await tester.pumpAndSettle();
    await submit(tester);
    expect(find.text('Enter a password.'), findsOneWidget);
    expect(service.requests, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('archive-create-password')),
      'secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey('archive-create-confirmation')),
      'different',
    );
    await submit(tester);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(service.requests, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('archive-create-confirmation')),
      'secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey('archive-create-name')),
      '../bad.zip',
    );
    await submit(tester);
    expect(
      find.text(
        'Enter a filename with the selected archive extension and no path separators.',
      ),
      findsOneWidget,
    );
    expect(service.requests, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('archive-create-name')),
      'protected.zip',
    );
    await submit(tester);
    expect(service.requests.single.password, 'secret');
    expect(service.requests.single.encryptNames, isFalse);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('archive-create-password')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'changing to TAR clears passwords instead of silently discarding protection on create',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-password')),
        'secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-confirmation')),
        'secret',
      );
      await format(tester, 'TAR');
      await format(tester, 'ZIP');
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('archive-create-protect')),
            )
            .value,
        isFalse,
      );
      await submit(tester);
      expect(service.requests.single.password, isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets('$language controls fit a narrow dialog with password fields', (
      tester,
    ) async {
      await show(tester, language: language, width: 390);
      await tester.ensureVisible(
        find.byKey(const ValueKey('archive-create-protect')),
      );
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      await submit(tester);
      expect(service.requests, isEmpty);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('archive-create-error')),
        findsOneWidget,
      );
    });
  }
}
