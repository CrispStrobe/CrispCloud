import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_conflict_preview_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/file_operation_conflict_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../support/conflict_preview_backend.dart';

class _Previews extends FileConflictPreviewService {
  _Previews(this.png);
  final Uint8List png;
  final targets = <FileConflictPreviewTarget>[];
  final controls = <FileOperationControl>[];
  Future<FileConflictImagePreview> Function(FileConflictPreviewTarget)? handler;

  FileConflictImagePreview get result => FileConflictImagePreview(
    png: png,
    width: 24,
    height: 12,
    animated: false,
  );

  @override
  Future<FileConflictImagePreview> load(
    FileConflictPreviewTarget target, {
    FileOperationControl? control,
    Duration timeout = FileConflictPreviewService.defaultTimeout,
  }) async {
    targets.add(target);
    controls.add(control!);
    return handler == null ? result : handler!(target);
  }
}

class _Review {
  _Review(this.result, this.context);
  final Future<FileConflictResolution> result;
  final BuildContext context;
  void close() => Navigator.of(context).pop();
}

void main() {
  late ConflictPreviewBackend source;
  late ConflictPreviewBackend destination;
  late _Previews previews;

  setUp(() {
    final png = Uint8List.fromList(
      image.encodePng(image.Image(width: 24, height: 12)),
    );
    source = ConflictPreviewBackend(
      storageLabel: 'Incoming account',
      bytes: png,
      file: FileItem(
        name: 'image.png',
        path: '/incoming/image.png',
        isFolder: false,
        uuid: 'source-id',
        size: png.length,
        updatedAt: DateTime.utc(2026, 1, 2),
        metadata: {
          'eTag': 'incoming-v1',
          'mimeType': 'image/png',
          'password': 'hidden-password',
        },
      ),
    );
    destination = ConflictPreviewBackend(
      storageLabel: 'Existing account',
      bytes: png,
      file: FileItem(
        name: 'image.png',
        path: '/existing/image.png',
        isFolder: false,
        uuid: 'destination-id',
        size: png.length,
        updatedAt: DateTime.utc(2026, 1, 1),
        metadata: {
          'eTag': 'existing-v1',
          'storageClass': 'STANDARD',
          'accessToken': 'hidden-token',
        },
      ),
    );
    previews = _Previews(png);
  });
  tearDown(() {
    expect(source.writes, 0);
    expect(destination.writes, 0);
  });

  Future<_Review> show(
    WidgetTester tester, {
    String language = 'en',
    double width = 1000,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Future<FileConflictResolution> pending;
    late BuildContext host;
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
          builder: (context) {
            host = context;
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  pending = showFileOperationConflict(
                    context,
                    entry: FileOperationEntry(
                      source.file,
                      destination.file.path!,
                    ),
                    existing: destination.file,
                    source: source,
                    destination: destination,
                    previewService: previews,
                  );
                },
                child: const Text('Open review'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    return _Review(pending, host);
  }

  Future<void> press(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'paired previews retain the original sources and allowlisted details',
    (tester) async {
      final review = await show(tester);
      await tester.pumpAndSettle();
      expect(previews.targets.map((target) => target.backend), [
        source,
        destination,
      ]);
      expect(previews.targets.map((target) => target.file.path), [
        '/incoming/image.png',
        '/existing/image.png',
      ]);
      expect(
        find.byKey(const ValueKey('file-conflict-incoming-image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file-conflict-existing-image')),
        findsOneWidget,
      );
      expect(find.text('24 × 12 pixels'), findsNWidgets(2));
      final more = find.byKey(const ValueKey('file-conflict-incoming-details'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      final details = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan!.toPlainText())
          .join('\n');
      expect(details, contains('Content type: image/png'));
      expect(details, contains('Version: incoming-v1'));
      expect(details, contains('Storage: Incoming account'));
      expect(details, isNot(contains('hidden-password')));
      expect(details, isNot(contains('hidden-token')));
      await press(tester, 'Keep both');
      expect((await review.result).decision, FileConflictDecision.keepBoth);
      expect(previews.controls.every((control) => control.isCancelled), isTrue);
    },
  );

  testWidgets('oversize previews remain explicit and never choose a decision', (
    tester,
  ) async {
    previews.handler = (_) => Future.error(
      const FileConflictPreviewException(FileConflictPreviewProblem.tooLarge),
    );
    final review = await show(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Image previews are limited to 4 MiB per file.'),
      findsNWidgets(2),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    await press(tester, 'Replace file');
    expect((await review.result).decision, FileConflictDecision.replace);
  });

  testWidgets(
    'a source-session change clears previews and blocks stale decisions',
    (tester) async {
      final review = await show(tester);
      await tester.pumpAndSettle();
      source.current = false;
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('file-conflict-incoming-image')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('file-conflict-existing-image')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('file-conflict-review-error')),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await press(tester, 'Cancel operation');
      expect((await review.result).decision, FileConflictDecision.cancel);
    },
  );

  testWidgets(
    'choice cancels pending reads and ignores a late completed preview',
    (tester) async {
      final pending = Completer<FileConflictImagePreview>();
      previews.handler = (_) => pending.future;
      final review = await show(tester);
      expect(previews.targets, hasLength(1));
      await press(tester, 'Skip');
      expect((await review.result).decision, FileConflictDecision.skip);
      expect(previews.controls.single.isCancelled, isTrue);
      pending.complete(previews.result);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(previews.targets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late callback from a replaced session never displays old image data',
    (tester) async {
      final pending = Completer<FileConflictImagePreview>();
      previews.handler = (_) => pending.future;
      final review = await show(tester);
      source.session = Object();
      pending.complete(previews.result);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('file-conflict-incoming-image')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('file-conflict-review-error')),
        findsOneWidget,
      );
      expect(previews.targets, hasLength(1));
      await press(tester, 'Cancel operation');
      expect((await review.result).decision, FileConflictDecision.cancel);
    },
  );

  testWidgets(
    'changed file versions invalidate the review instead of enabling replacement',
    (tester) async {
      previews.handler = (_) => Future.error(
        const FileConflictPreviewException(
          FileConflictPreviewProblem.sourceChanged,
        ),
      );
      final review = await show(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.byKey(const ValueKey('file-conflict-review-error')),
        findsOneWidget,
      );
      await press(tester, 'Cancel operation');
      expect((await review.result).decision, FileConflictDecision.cancel);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets(
      '$language cards stack and controls fit a narrow enlarged layout',
      (tester) async {
        previews.handler = (_) => Future.error(
          const FileConflictPreviewException(
            FileConflictPreviewProblem.dimensionsTooLarge,
          ),
        );
        final review = await show(
          tester,
          language: language,
          width: 390,
          scale: 1.3,
        );
        await tester.pumpAndSettle();
        final left = tester.getRect(
          find.byKey(const ValueKey('file-conflict-incoming-card')),
        );
        final right = tester.getRect(
          find.byKey(const ValueKey('file-conflict-existing-card')),
        );
        expect(left.left, right.left);
        expect(right.top, greaterThan(left.bottom));
        expect(tester.takeException(), isNull);
        review.close();
        await tester.pumpAndSettle();
        expect((await review.result).decision, FileConflictDecision.cancel);
      },
    );
  }
}
