import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_creation_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_creation_batch.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/widgets/archive_creation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

const _dataImageHelp =
    'Create a data image from local files and folders. Up to 2 GiB of image output. Existing files are never replaced.';
const _streamedDataImageHelp =
    'Create a data image up to 8 GiB from local files and folders. Temporary disk space is required. Existing files are never replaced.';
const _streamedIsoHelp =
    'Create a data image up to 8 GiB. Each ISO file must be smaller than 4 GiB. Temporary disk space is required. Existing files are never replaced.';
const _singleFileHelp =
    'Select one local file, up to 64 MiB. Its name after decompression comes from the output filename.';
const _flatFilesHelp =
    'Select regular local files without folders. Up to 64 MiB per file and 256 MiB total.';
const _compressedTarHelp =
    'Compressed TAR is limited to 64 MiB after decompression, including archive headers.';
const _streamedTarHelp =
    'Stream local files into a new TAR or CBT archive up to 2 GiB, including headers. Existing files are never replaced.';
const _streamedCommonHelp =
    'Create an archive up to 8 GiB, including headers, with up to 8 GiB of expanded contents. Temporary disk space is required. Existing files are never replaced.';
const _encodedHelp =
    'Single-file compressors and compressed TAR are limited to 64 MiB of encoded output.';
const _ordinaryHelp =
    'Local files only. Up to 64 MiB per file and 256 MiB total. Existing files are never replaced.';
const _hfsHelp =
    'Creates a case-sensitive HFSX data volume. Names use HFS Unicode normalization. Resource forks, extended attributes and symbolic links are not copied.';
const _isoHelp =
    'Creates a data-only ISO with Rock Ridge and Joliet names. Boot records and UDF filesystems are not created.';
const _lz4Help =
    'LZ4 offers fast compression or storage without compression. Both modes include content checksums.';
const _lzmaHelp =
    'LZMA uses a 64 KiB dictionary for Fast, 8 MiB for Normal and 64 MiB for Maximum. The format has no content checksum.';
const _compressHelp =
    'UNIX compress uses 12-bit dictionaries for Fast, 14-bit for Normal and 16-bit for Maximum. The format has no content checksum or decoded length.';
const _legacyCpioHelp =
    'Use legacy CPIO for compatibility. These profiles have no content checksum or encryption; names, sizes and metadata must fit their older fields.';

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
    ArchiveCreationWriter? writer,
    Future<void> Function(ArchiveCreationPrepared)? onPrepared,
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

class _StreamingCreationBackend extends ArchiveCreationBackend {
  @override
  StorageReference get storageReference => const StorageReference(
    kind: 'local',
    provider: 'native',
    accountKey: 'creation-guidance',
  );
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(
        boundedDownload: true,
        boundedUpload: true,
      );
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
    double textScale = 1,
    String selectedPath = '/input/report.txt',
    List<String>? selectedPaths,
    Future<void> Function(ArchiveCreationOptions)? onQueue,
    Future<void> Function(List<ArchiveCreationBatchItem>)? onQueueBatch,
    Future<void> Function()? onViewJobs,
    Future<ArchiveCreationResult?> Function()? onExternalPacker,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = [
      for (final path in selectedPaths ?? [selectedPath])
        (await backend.stat(path))!,
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ArchiveCreationDialog(
            source: backend,
            destination: backend,
            files: files,
            destinationDirectory: '/output',
            service: service,
            onQueue: onQueue,
            onQueueBatch: onQueueBatch,
            onViewJobs: onViewJobs,
            onExternalPacker: onExternalPacker,
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
    final field = find.byKey(const ValueKey('archive-create-format'));
    final current = tester
        .widget<DropdownButtonFormField<ArchiveCreationFormat>>(field)
        .initialValue!;
    final target = ArchiveCreationFormat.values.singleWhere(
      (value) =>
          archiveCreationText(tester.element(field), value.label) == label,
    );
    if (target == current) return;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    final menu = find.byType(ListView);
    expect(menu, findsOneWidget);
    final scrollable = find.descendant(
      of: menu,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    // Wrapped labels have variable heights. Flutter estimates the menu's
    // initial offset using minimum-height rows, so enum order does not tell us
    // whether a target is above or below the actual viewport. Start at its
    // real beginning and search the popup, independently of the form scroller.
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
    final option = find.descendant(of: menu, matching: find.text(label));
    await tester.scrollUntilVisible(option, 180, scrollable: scrollable);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<ArchiveCreationFormat>>(field)
          .initialValue,
      target,
    );
  }

  String name(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('archive-create-name')))
      .controller!
      .text;

  String tr(WidgetTester tester, String key) => archiveCreationText(
    tester.element(find.byType(ArchiveCreationDialog)),
    key,
  );

  DropdownButtonFormField<ArchiveCreationCompression> compression(
    WidgetTester tester,
    ArchiveCreationFormat value,
  ) => tester.widget<DropdownButtonFormField<ArchiveCreationCompression>>(
    find.byKey(ValueKey('archive-create-compression-${value.name}')),
  );

  Iterable<ArchiveCreationCompression?> compressionChoices(
    WidgetTester tester,
    ArchiveCreationFormat value,
  ) => tester
      .widget<DropdownButton<ArchiveCreationCompression>>(
        find.descendant(
          of: find.byKey(ValueKey('archive-create-compression-${value.name}')),
          matching: find.byType(DropdownButton<ArchiveCreationCompression>),
        ),
      )
      .items!
      .map((item) => item.value);

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

  for (final (value, label, extension) in [
    (ArchiveCreationFormat.rar, 'RAR5 Store', '.rar'),
    (ArchiveCreationFormat.cbr, 'CBR (RAR5 Store)', '.cbr'),
  ]) {
    testWidgets(
      '$label selects native Store creation and clears ZIP protection',
      (tester) async {
        backend = _StreamingCreationBackend()
          ..put('/input/report.txt', [1, 2, 3]);
        await show(tester);
        final protection = find.byKey(const ValueKey('archive-create-protect'));
        await tester.tap(protection);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('archive-create-password')),
          'previous ZIP password',
        );
        await tester.enterText(
          find.byKey(const ValueKey('archive-create-confirmation')),
          'previous ZIP password',
        );
        await format(tester, label);
        expect(find.text(label), findsOneWidget);
        expect(name(tester), 'report$extension');
        expect(compressionChoices(tester, value), [
          ArchiveCreationCompression.none,
        ]);
        expect(
          compression(tester, value).initialValue,
          ArchiveCreationCompression.none,
        );
        expect(compression(tester, value).onChanged, isNull);
        expect(find.text(_streamedCommonHelp), findsOneWidget);
        expect(find.text(_ordinaryHelp), findsNothing);
        expect(protection, findsNothing);
        expect(
          find.byKey(const ValueKey('archive-create-password')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('archive-create-confirmation')),
          findsNothing,
        );
        expect(find.byType(CheckboxListTile), findsNothing);

        // Returning to ZIP exposes whether the previous credentials were cleared,
        // rather than merely being hidden while Store is selected.
        await format(tester, 'ZIP');
        expect(tester.widget<SwitchListTile>(protection).value, isFalse);
        await tester.ensureVisible(protection);
        await tester.tap(protection);
        await tester.pumpAndSettle();
        for (final key in [
          'archive-create-password',
          'archive-create-confirmation',
        ]) {
          expect(
            tester
                .widget<TextField>(find.byKey(ValueKey(key)))
                .controller!
                .text,
            isEmpty,
          );
        }
        await format(tester, label);
        await submit(tester);
        final options = service.requests.single;
        expect(options.format, value);
        expect(options.name, 'report$extension');
        expect(options.compression, ArchiveCreationCompression.none);
        expect(options.password, isNull);
        expect(options.encryptNames, isFalse);
        expect(service.destinationPath, '/output');
        expect(
          find.byKey(const ValueKey('archive-create-success')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final value in [
    ArchiveCreationFormat.iso,
    ArchiveCreationFormat.hfsx,
    ArchiveCreationFormat.dmg,
  ]) {
    testWidgets(
      '${value.name} selects its data image options and helper text',
      (tester) async {
        await show(tester);
        await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('archive-create-password')),
          'temporary password',
        );
        await format(tester, value.label);
        expect(name(tester), 'report${value.extension}');
        expect(
          find.byKey(const ValueKey('archive-create-protect')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('archive-create-password')),
          findsNothing,
        );
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.text(_dataImageHelp), findsOneWidget);
        expect(
          find.text(value == ArchiveCreationFormat.iso ? _isoHelp : _hfsHelp),
          findsOneWidget,
        );
        expect(find.text(_singleFileHelp), findsNothing);
        expect(find.text(_compressedTarHelp), findsNothing);
        final control = compression(tester, value);
        expect(compressionChoices(tester, value), [
          ArchiveCreationCompression.none,
          if (value == ArchiveCreationFormat.dmg)
            ArchiveCreationCompression.normal,
        ]);
        if (value == ArchiveCreationFormat.dmg) {
          expect(control.initialValue, ArchiveCreationCompression.normal);
          expect(control.onChanged, isNotNull);
          final field = find.byKey(
            ValueKey('archive-create-compression-${value.name}'),
          );
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
          final store = find.text('Store (no compression)').last;
          await tester.ensureVisible(store);
          await tester.tap(store);
          await tester.pumpAndSettle();
        } else {
          expect(control.initialValue, ArchiveCreationCompression.none);
          expect(control.onChanged, isNull);
        }
        await submit(tester);
        final options = service.requests.single;
        expect(options.format, value);
        expect(options.name, 'report${value.extension}');
        expect(options.compression, ArchiveCreationCompression.none);
        expect(options.password, isNull);
        expect(options.encryptNames, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'single XZ keeps the full original basename including extensions',
    (tester) async {
      backend.put('/input/report.final.csv', [4, 5, 6]);
      await show(tester, selectedPath: '/input/report.final.csv');
      expect(name(tester), 'report.final.zip');
      await format(tester, 'XZ — one file');
      expect(name(tester), 'report.final.csv.xz');
      await format(tester, 'gzip — one file');
      expect(name(tester), 'report.final.csv.gz');
      await format(tester, 'XZ — one file');
      expect(name(tester), 'report.final.csv.xz');
      expect(find.text(_singleFileHelp), findsOneWidget);
      expect(find.text(_compressedTarHelp), findsNothing);
      expect(
        find.byKey(const ValueKey('archive-create-protect')),
        findsNothing,
      );
      expect(compressionChoices(tester, ArchiveCreationFormat.xz), [
        ArchiveCreationCompression.fast,
        ArchiveCreationCompression.normal,
        ArchiveCreationCompression.maximum,
      ]);
      await submit(tester);
      final options = service.requests.single;
      expect(options.format, ArchiveCreationFormat.xz);
      expect(options.name, 'report.final.csv.xz');
      expect(options.compression, ArchiveCreationCompression.normal);
      expect(options.password, isNull);
      expect(options.encryptNames, isFalse);
    },
  );

  for (final value in [
    ArchiveCreationFormat.cpioOdc,
    ArchiveCreationFormat.cpioBinaryLittleEndian,
    ArchiveCreationFormat.cpioBinaryBigEndian,
  ]) {
    testWidgets('${value.label} creates the selected uncompressed profile', (
      tester,
    ) async {
      await show(tester, width: 390);
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-password')),
        'discarded password',
      );
      await format(tester, value.label);
      expect(name(tester), 'report.cpio');
      expect(find.text(_legacyCpioHelp), findsOneWidget);
      expect(
        find.byKey(const ValueKey('archive-create-protect')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('archive-create-password')),
        findsNothing,
      );
      expect(compressionChoices(tester, value), [
        ArchiveCreationCompression.none,
      ]);
      await submit(tester);
      final request = service.requests.single;
      expect(request.format, value);
      expect(request.name, 'report.cpio');
      expect(request.compression, ArchiveCreationCompression.none);
      expect(request.password, isNull);
      expect(request.encryptNames, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final value in [
    ArchiveCreationFormat.lz4,
    ArchiveCreationFormat.tarLz4,
    ArchiveCreationFormat.lzma,
    ArchiveCreationFormat.tarLzma,
    ArchiveCreationFormat.compress,
    ArchiveCreationFormat.tarCompress,
  ]) {
    testWidgets('${value.label} exposes accurate controls and format guidance', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-password')),
        'discarded password',
      );
      await format(tester, value.label);
      final lz4 =
          value == ArchiveCreationFormat.lz4 ||
          value == ArchiveCreationFormat.tarLz4;
      final compress =
          value == ArchiveCreationFormat.compress ||
          value == ArchiveCreationFormat.tarCompress;
      final expectedName =
          '${value.singlePayload ? 'report.txt' : 'report'}${value.extension}';
      expect(name(tester), expectedName);
      expect(
        find.byKey(const ValueKey('archive-create-protect')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('archive-create-password')),
        findsNothing,
      );
      final detail = compress ? _compressHelp : (lz4 ? _lz4Help : _lzmaHelp);
      expect(find.text(detail), findsOneWidget);
      for (final other in [_lz4Help, _lzmaHelp, _compressHelp]) {
        if (other != detail) expect(find.text(other), findsNothing);
      }
      expect(
        find.text(value.singlePayload ? _singleFileHelp : _compressedTarHelp),
        findsOneWidget,
      );
      expect(
        compressionChoices(tester, value),
        lz4
            ? [
                ArchiveCreationCompression.none,
                ArchiveCreationCompression.normal,
              ]
            : [
                ArchiveCreationCompression.fast,
                ArchiveCreationCompression.normal,
                ArchiveCreationCompression.maximum,
              ],
      );
      expect(
        compression(tester, value).initialValue,
        ArchiveCreationCompression.normal,
      );
      final field = find.byKey(
        ValueKey('archive-create-compression-${value.name}'),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final choice = find.text(lz4 ? 'Store (no compression)' : 'Maximum').last;
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await submit(tester);
      final request = service.requests.single;
      expect(request.format, value);
      expect(request.name, expectedName);
      expect(
        request.compression,
        lz4
            ? ArchiveCreationCompression.none
            : ArchiveCreationCompression.maximum,
      );
      expect(request.password, isNull);
      expect(request.encryptNames, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final hidden in [true, false]) {
    testWidgets('CB7 carries the selected hidden-filenames policy: $hidden', (
      tester,
    ) async {
      await show(tester);
      await format(tester, 'CB7');
      expect(name(tester), 'report.cb7');
      expect(
        compression(tester, ArchiveCreationFormat.cb7).initialValue,
        ArchiveCreationCompression.lzma2,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('archive-create-protect')),
      );
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(find.text('AES-256. Passwords are not saved.'), findsOneWidget);
      expect(find.text('AES-256. ZIP filenames remain visible.'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-password')),
        'secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-confirmation')),
        'secret',
      );
      if (!hidden) {
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
      }
      await submit(tester);
      final options = service.requests.single;
      expect(options.format, ArchiveCreationFormat.cb7);
      expect(options.name, 'report.cb7');
      expect(options.compression, ArchiveCreationCompression.lzma2);
      expect(options.password, 'secret');
      expect(options.encryptNames, hidden);
    });
  }

  for (final value in [
    ArchiveCreationFormat.tarGzip,
    ArchiveCreationFormat.tarBzip2,
    ArchiveCreationFormat.tarXz,
    ArchiveCreationFormat.tarZstd,
    ArchiveCreationFormat.tarLz4,
    ArchiveCreationFormat.tarLzma,
    ArchiveCreationFormat.tarCompress,
  ]) {
    testWidgets('${value.label} displays the shared decompression limit', (
      tester,
    ) async {
      await show(tester);
      await format(tester, value.label);
      expect(find.text(_compressedTarHelp), findsOneWidget);
      expect(find.text(_encodedHelp), findsOneWidget);
      expect(
        find.text(
          'TAR.GZ is limited to 64 MiB after decompression, including archive headers.',
        ),
        findsNothing,
      );
      expect(find.text(_singleFileHelp), findsNothing);
      expect(
        find.byKey(const ValueKey('archive-create-protect')),
        findsNothing,
      );
      await submit(tester);
      expect(service.requests.single.format, value);
      expect(service.requests.single.name, 'report${value.extension}');
    });
  }

  for (final locale in [
    ('de', 'ISO-Datenabbild'),
    ('fr', 'Image de données ISO'),
    ('es', 'Imagen de datos ISO'),
    ('pt', 'Imagem de dados ISO'),
    ('zh', 'ISO 数据映像'),
    ('ja', 'ISOデータイメージ'),
    ('ko', 'ISO 데이터 이미지'),
    ('ar', 'صورة بيانات ISO'),
  ]) {
    testWidgets('${locale.$1} localizes the new formats in a narrow dialog', (
      tester,
    ) async {
      await show(tester, language: locale.$1, width: 390);
      expect(tr(tester, 'ISO data image'), locale.$2);
      for (final key in [
        'RAR5 Store',
        'CBR (RAR5 Store)',
        'gzip — one file',
        'bzip2 — one file',
        'XZ — one file',
        'Zstandard — one file',
        'LZ4 — one file',
        'LZMA — one file',
        'UNIX compress — one file',
        'ISO data image',
        'HFSX data image',
        'DMG (HFSX data volume)',
        'AR — flat files',
        'CPIO (binary, little-endian)',
        'CPIO (binary, big-endian)',
        'JAR (unsigned)',
        'WAR (unsigned)',
        'EAR (unsigned)',
        _dataImageHelp,
        _streamedDataImageHelp,
        _streamedIsoHelp,
        _singleFileHelp,
        _flatFilesHelp,
        _compressedTarHelp,
        _streamedTarHelp,
        _streamedCommonHelp,
        _encodedHelp,
        _hfsHelp,
        _isoHelp,
        _lz4Help,
        _lzmaHelp,
        _compressHelp,
        _legacyCpioHelp,
      ]) {
        expect(tr(tester, key), isNot(key), reason: '${locale.$1}: $key');
      }
      for (final value in [
        ArchiveCreationFormat.iso,
        ArchiveCreationFormat.hfsx,
        ArchiveCreationFormat.dmg,
        ArchiveCreationFormat.tarBzip2,
        ArchiveCreationFormat.tarLz4,
        ArchiveCreationFormat.tarLzma,
        ArchiveCreationFormat.tarCompress,
        ArchiveCreationFormat.lz4,
        ArchiveCreationFormat.lzma,
        ArchiveCreationFormat.compress,
        ArchiveCreationFormat.cpioOdc,
        ArchiveCreationFormat.cpioBinaryLittleEndian,
        ArchiveCreationFormat.cpioBinaryBigEndian,
        ArchiveCreationFormat.xz,
      ]) {
        await format(tester, tr(tester, value.label));
        expect(find.text(tr(tester, value.label)), findsOneWidget);
        final help = value.diskImage
            ? _dataImageHelp
            : value.legacyCpio
            ? _legacyCpioHelp
            : value.singlePayload
            ? _singleFileHelp
            : _compressedTarHelp;
        expect(find.text(tr(tester, help)), findsOneWidget);
        expect(find.text(help), findsNothing);
        if (value.diskImage) {
          final detail = value == ArchiveCreationFormat.iso
              ? _isoHelp
              : _hfsHelp;
          expect(find.text(tr(tester, detail)), findsOneWidget);
          expect(find.text(detail), findsNothing);
        }
        if (value == ArchiveCreationFormat.lz4 ||
            value == ArchiveCreationFormat.tarLz4 ||
            value == ArchiveCreationFormat.lzma ||
            value == ArchiveCreationFormat.tarLzma ||
            value == ArchiveCreationFormat.compress ||
            value == ArchiveCreationFormat.tarCompress) {
          final detail =
              value == ArchiveCreationFormat.lz4 ||
                  value == ArchiveCreationFormat.tarLz4
              ? _lz4Help
              : value == ArchiveCreationFormat.compress ||
                    value == ArchiveCreationFormat.tarCompress
              ? _compressHelp
              : _lzmaHelp;
          expect(find.text(tr(tester, detail)), findsOneWidget);
          expect(find.text(detail), findsNothing);
        }
        expect(
          find.byKey(const ValueKey('archive-create-protect')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await submit(tester);
      expect(service.requests.single.format, ArchiveCreationFormat.xz);
      expect(service.requests.single.name, 'report.txt.xz');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('buffered TAR and CBT keep the ordinary creation limits', (
    tester,
  ) async {
    await show(tester);
    for (final value in [
      ArchiveCreationFormat.tar,
      ArchiveCreationFormat.cbt,
    ]) {
      await format(tester, value.label);
      expect(find.text(_ordinaryHelp), findsOneWidget);
      expect(find.text(_streamedTarHelp), findsNothing);
      expect(find.text(_encodedHelp), findsNothing);
    }
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
    testWidgets(
      '$language distinguishes native archive and data image limits at narrow large text',
      (tester) async {
        backend = _StreamingCreationBackend()
          ..put('/input/report.txt', [1, 2, 3]);
        await show(tester, language: language, width: 320, textScale: 1.8);
        for (final value in [
          ArchiveCreationFormat.tar,
          ArchiveCreationFormat.cbt,
        ]) {
          await format(tester, tr(tester, value.label));
          expect(find.text(tr(tester, _streamedTarHelp)), findsOneWidget);
          expect(find.text(tr(tester, _ordinaryHelp)), findsNothing);
          expect(find.text(tr(tester, _encodedHelp)), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await format(tester, tr(tester, ArchiveCreationFormat.tarGzip.label));
        expect(find.text(tr(tester, _streamedTarHelp)), findsNothing);
        expect(find.text(tr(tester, _streamedCommonHelp)), findsOneWidget);
        expect(find.text(tr(tester, _compressedTarHelp)), findsNothing);
        expect(find.text(tr(tester, _encodedHelp)), findsNothing);
        await format(tester, tr(tester, ArchiveCreationFormat.zip.label));
        expect(find.text(tr(tester, _ordinaryHelp)), findsNothing);
        expect(find.text(tr(tester, _streamedCommonHelp)), findsOneWidget);
        expect(find.text(tr(tester, _streamedTarHelp)), findsNothing);
        expect(tester.takeException(), isNull);
        for (final value in [
          ArchiveCreationFormat.rar,
          ArchiveCreationFormat.cbr,
        ]) {
          await format(tester, tr(tester, value.label));
          expect(find.text(tr(tester, value.label)), findsOneWidget);
          expect(find.text(tr(tester, _streamedCommonHelp)), findsOneWidget);
          expect(find.text(tr(tester, _ordinaryHelp)), findsNothing);
          expect(
            find.byKey(const ValueKey('archive-create-protect')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
        for (final value in [
          ArchiveCreationFormat.iso,
          ArchiveCreationFormat.hfsx,
          ArchiveCreationFormat.dmg,
        ]) {
          await format(tester, tr(tester, value.label));
          final iso = value == ArchiveCreationFormat.iso;
          expect(
            find.text(
              tr(tester, iso ? _streamedIsoHelp : _streamedDataImageHelp),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              tr(tester, iso ? _streamedDataImageHelp : _streamedIsoHelp),
            ),
            findsNothing,
          );
          expect(
            find.text(tr(tester, iso ? _isoHelp : _hfsHelp)),
            findsOneWidget,
          );
          for (final obsolete in [
            _dataImageHelp,
            _ordinaryHelp,
            _streamedTarHelp,
            _streamedCommonHelp,
            _compressedTarHelp,
            _encodedHelp,
          ]) {
            expect(find.text(tr(tester, obsolete)), findsNothing);
          }
          expect(
            find.byKey(const ValueKey('archive-create-protect')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

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

  testWidgets(
    'background queue receives reviewed options and clears the password',
    (tester) async {
      final queued = <ArchiveCreationOptions>[];
      var viewed = false;
      await show(
        tester,
        onQueue: (options) async => queued.add(options),
        onViewJobs: () async => viewed = true,
      );
      await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-password')),
        'queue-secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('archive-create-confirmation')),
        'queue-secret',
      );
      final queue = find.byKey(const ValueKey('archive-create-queue'));
      await tester.ensureVisible(queue);
      await tester.tap(queue);
      await tester.pumpAndSettle();
      expect(queued.single.name, 'report.zip');
      expect(queued.single.password, 'queue-secret');
      expect(service.requests, isEmpty);
      expect(
        find.byKey(const ValueKey('archive-create-queued')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('archive-create-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('archive-create-submit')), findsNothing);
      await tester.ensureVisible(find.text('View jobs'));
      await tester.tap(find.text('View jobs'));
      await tester.pumpAndSettle();
      expect(viewed, isTrue);
    },
  );

  testWidgets('failed queue admission remains a retryable form', (
    tester,
  ) async {
    await show(
      tester,
      onQueue: (_) async => throw StateError('Queue unavailable'),
    );
    final queue = find.byKey(const ValueKey('archive-create-queue'));
    await tester.ensureVisible(queue);
    await tester.tap(queue);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archive-create-queued')), findsNothing);
    expect(find.byKey(const ValueKey('archive-create-error')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(queue).onPressed, isNotNull);
    expect(service.requests, isEmpty);
  });

  testWidgets(
    'separate archives preview every output and enter the queue together',
    (tester) async {
      backend.put('/input/report.csv', [4]);
      List<ArchiveCreationBatchItem>? batch;
      await show(
        tester,
        selectedPaths: ['/input/report.txt', '/input/report.csv'],
        onQueue: (_) async => fail('Combined archive was not selected'),
        onQueueBatch: (items) async => batch = items,
      );
      final separate = find.byKey(const ValueKey('archive-create-batch'));
      await tester.ensureVisible(separate);
      await tester.tap(separate);
      await tester.pumpAndSettle();
      expect(find.text('/output/report.txt.zip'), findsOneWidget);
      expect(find.text('/output/report.csv.zip'), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-create-name')), findsNothing);
      expect(find.byKey(const ValueKey('archive-create-submit')), findsNothing);
      await tester.ensureVisible(find.text('Queue 2 archives'));
      await tester.tap(find.text('Queue 2 archives'));
      await tester.pumpAndSettle();
      expect(batch!.map((item) => item.options.name), [
        'report.txt.zip',
        'report.csv.zip',
      ]);
      expect(batch!.map((item) => item.files.single.path), [
        '/input/report.txt',
        '/input/report.csv',
      ]);
      expect(find.text('Queued 2 archives.'), findsOneWidget);
      expect(service.requests, isEmpty);
    },
  );

  testWidgets('protected creation cannot delegate to an unencrypted packer', (
    tester,
  ) async {
    var calls = 0;
    await show(
      tester,
      onExternalPacker: () async {
        calls++;
        return const ArchiveCreationResult('/output/external.7z', 1, 42);
      },
    );
    final staleAction = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Use installed packer…'),
        )
        .onPressed!;
    await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
    await tester.pumpAndSettle();
    expect(find.text('Use installed packer…'), findsNothing);
    staleAction();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(service.requests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('archive-create-protect')));
    await tester.pumpAndSettle();
    expect(find.text('Use installed packer…'), findsOneWidget);
  });

  testWidgets('installed packer returns the verified result to creation', (
    tester,
  ) async {
    await show(
      tester,
      onExternalPacker: () async =>
          const ArchiveCreationResult('/output/external.7z', 1, 42),
    );
    await tester.ensureVisible(find.text('Use installed packer…'));
    await tester.tap(find.text('Use installed packer…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Created and verified: /output/external.7z'),
      findsOneWidget,
    );
    expect(service.requests, isEmpty);
  });
}
