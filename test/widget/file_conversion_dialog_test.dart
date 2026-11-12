import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_conversion_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_conversion_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/file_conversion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/file_conversion_backend.dart';

class _PendingConversion extends FileConversionService {
  final pending = Completer<FileConversionResult>();
  FileOperationControl? control;
  FileConversionOptions? options;
  void Function(FileConversionProgress)? progress;
  @override
  Future<FileConversionResult> convert({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String destinationDirectory,
    required FileConversionOptions options,
    FileOperationControl? control,
    void Function(FileConversionProgress)? onProgress,
  }) {
    this.options = options;
    this.control = control;
    progress = onProgress;
    return pending.future;
  }
}

class _ObservedConversion extends FileConversionService {
  final completed = Completer<Object?>();

  @override
  Future<FileConversionResult> convert({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String destinationDirectory,
    required FileConversionOptions options,
    FileOperationControl? control,
    void Function(FileConversionProgress)? onProgress,
  }) async {
    try {
      final result = await super.convert(
        source: source,
        file: file,
        destination: destination,
        destinationDirectory: destinationDirectory,
        options: options,
        control: control,
        onProgress: onProgress,
      );
      completed.complete(null);
      return result;
    } catch (error) {
      completed.complete(error);
      rethrow;
    }
  }
}

void main() {
  late ConversionMemoryBackend backend;
  late FileItem file;
  late int remembered;
  setUp(() {
    backend = ConversionMemoryBackend();
    file = backend.put('example.bin', [1, 2, 3]);
    remembered = 0;
  });
  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    double width = 1000,
    double scale = 1,
    FileConversionService service = const FileConversionService(),
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        home: Scaffold(
          body: FileConversionDialog(
            source: backend,
            destination: backend,
            file: file,
            destinationDirectory: '/files',
            service: service,
            onCreated: () => remembered++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Finder getName() => find.byKey(const ValueKey('file-conversion-name'));
  Finder getStart() => find.byKey(const ValueKey('file-conversion-start'));

  testWidgets(
    'review is read-only, names output explicitly, and creates verified new file',
    (tester) async {
      await show(tester);
      expect(backend.readCounts, isEmpty);
      expect(backend.writes, 0);
      expect(
        tester.widget<TextField>(getName()).controller!.text,
        'example.bin.mime',
      );
      await tester.enterText(getName(), 'encoded.mime');
      await tester.tap(getStart());
      await tester.pumpAndSettle();
      expect(backend.commits, 1);
      expect(backend.contents['/files/example.bin'], [1, 2, 3]);
      expect(
        ascii.decode(backend.contents['/files/encoded.mime']!),
        contains('Content-Transfer-Encoding: base64'),
      );
      expect(find.textContaining('SHA-256:'), findsOneWidget);
      expect(remembered, 1);
      await finish(tester);
    },
  );
  testWidgets(
    'invalid output name and existing destination are actionable without overwrites',
    (tester) async {
      await show(tester);
      await tester.enterText(getName(), '../escape');
      await tester.tap(getStart());
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid new filename without a path.'),
        findsOneWidget,
      );
      expect(backend.writes, 0);
      await tester.enterText(getName(), 'occupied.mime');
      backend.put('occupied.mime', [42]);
      await tester.tap(getStart());
      await tester.pumpAndSettle();
      expect(
        find.text('That filename already exists. Enter a different name.'),
        findsOneWidget,
      );
      expect(backend.contents['/files/occupied.mime'], [42]);
      expect(remembered, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'legacy decode defaults remain independent of safe embedded name and mode',
    (tester) async {
      file = backend.put(
        'input.uue',
        ascii.encode('begin 777 embedded-name.bin\n#0V%T\n`\nend\n'),
      );
      await show(tester);
      expect(
        tester.widget<TextField>(getName()).controller!.text,
        'input.decoded',
      );
      expect(find.text('Decode to file'), findsOneWidget);
      await tester.tap(getStart());
      await tester.pumpAndSettle();
      expect(backend.contents['/files/input.decoded'], ascii.encode('Cat'));
      expect(backend.nodes.containsKey('/files/embedded-name.bin'), isFalse);
      await finish(tester);
    },
  );
  testWidgets(
    'unsafe embedded name is rejected without output or selection memory',
    (tester) async {
      final original = ascii.encode('begin 600 ../../outside\n#0V%T\n`\nend\n');
      file = backend.put('input.uue', original);
      // The observer and conversion must use real asynchronous scheduling.
      // Awaiting a fake-zone Completer inside runAsync can itself deadlock,
      // even after the underlying conversion has already rejected its input.
      final service = (await tester.runAsync(
        () async => _ObservedConversion(),
      ))!;
      await show(tester, service: service);
      expect(
        tester.widget<TextField>(getName()).controller!.text,
        'input.decoded',
      );
      expect(find.text('Decode to file'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(getStart());
        final failure = await service.completed.future.timeout(
          const Duration(seconds: 10),
        );
        expect(
          failure,
          isA<FileConversionCodecException>().having(
            (error) => error.problem,
            'problem',
            FileConversionCodecProblem.malformed,
          ),
        );
      });
      await tester.pumpAndSettle();
      final error = find.byKey(const ValueKey('file-conversion-error'));
      expect(backend.writes, 0);
      expect(backend.commits, 0);
      expect(remembered, 0);
      expect(backend.contents['/files/input.uue'], original);
      expect(error, findsOneWidget);
      expect(
        tester.widget<Text>(error).data,
        'The input is incomplete or invalid for the selected format.',
      );
      await finish(tester);
    },
  );
  testWidgets('custom output name survives format and direction changes', (
    tester,
  ) async {
    final service = _PendingConversion();
    await show(tester, service: service);
    await tester.enterText(getName(), 'chosen.out');
    await tester.tap(find.byKey(const ValueKey('file-conversion-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('XXE').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(getName()).controller!.text, 'chosen.out');
    await tester.tap(getStart());
    await tester.pump();
    expect(service.options!.format, FileConversionFormat.xxe);
    expect(service.options!.outputName, 'chosen.out');
    await finish(tester);
    service.pending.completeError(
      const FileConversionException(FileConversionProblem.cancelled),
    );
    await tester.pump();
  });
  testWidgets('unsupported destination cannot start or read data', (
    tester,
  ) async {
    backend.exclusive = false;
    await show(tester);
    expect(tester.widget<FilledButton>(getStart()).onPressed, isNull);
    expect(
      find.textContaining('cannot stream and exclusively'),
      findsOneWidget,
    );
    expect(backend.stats, 0);
    expect(backend.readCounts, isEmpty);
    await finish(tester);
  });
  testWidgets('storage replacement invalidates review before any reads', (
    tester,
  ) async {
    await show(tester);
    backend.session = Object();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.text(
        'The original storage is unavailable. Close this dialog and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(getStart()).onPressed, isNull);
    expect(backend.readCounts, isEmpty);
    await finish(tester);
  });
  testWidgets(
    'captured row metadata cannot be silently updated during review',
    (tester) async {
      await show(tester);
      file.metadata!['revision'] = 'new-version';
      await tester.tap(getStart());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The original file changed. Close this dialog and review it again.',
        ),
        findsOneWidget,
      );
      expect(backend.readCounts, isEmpty);
      expect(remembered, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'cancel and disposal stop active work and late callbacks cannot update UI',
    (tester) async {
      final service = _PendingConversion();
      await show(tester, service: service);
      await tester.tap(getStart());
      await tester.pump();
      expect(service.control!.isCancelled, isFalse);
      await tester.tap(find.byKey(const ValueKey('file-conversion-cancel')));
      expect(service.control!.isCancelled, isTrue);
      await finish(tester);
      service.progress!(
        const FileConversionProgress(FileConversionPhase.writing, 1, 3),
      );
      service.pending.completeError(
        const FileConversionException(FileConversionProblem.cancelled),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(remembered, 0);
    },
  );
  testWidgets('raw provider failure details are never rendered', (
    tester,
  ) async {
    final service = _PendingConversion();
    await show(tester, service: service);
    await tester.tap(getStart());
    await tester.pump();
    service.pending.completeError(StateError('credential=private-value'));
    await tester.pumpAndSettle();
    expect(
      find.text('Conversion failed. Check storage access and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private-value'), findsNothing);
    await finish(tester);
  });
  testWidgets('narrow Arabic review supports scaled text without overflow', (
    tester,
  ) async {
    await show(tester, language: 'ar', width: 360, scale: 1.2);
    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(getName())), TextDirection.rtl);
    final strings = FileConversionStrings(tester.element(getName()));
    expect(strings.text('Encode / decode file'), isNot('Encode / decode file'));
    await finish(tester);
  });
  for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('$language provides translated actions and all typed errors', (
      tester,
    ) async {
      await show(tester, language: language);
      final strings = FileConversionStrings(tester.element(getName()));
      expect(strings.text('Convert'), isNot('Convert'));
      for (final problem in FileConversionProblem.values) {
        expect(strings.error(FileConversionException(problem)), isNotEmpty);
      }
      for (final problem in FileConversionCodecProblem.values) {
        expect(
          strings.error(FileConversionCodecException(problem)),
          isNotEmpty,
        );
      }
      await finish(tester);
    });
  }
}
