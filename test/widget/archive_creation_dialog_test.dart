import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_creation_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/archive_creation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

const _dataImageHelp =
    'Create a data image from local files and folders. Up to 2 GiB of image output. Existing files are never replaced.';
const _singleFileHelp =
    'Select one local file, up to 64 MiB. Its name after decompression comes from the output filename.';
const _flatFilesHelp =
    'Select regular local files without folders. Up to 64 MiB per file and 256 MiB total.';
const _compressedTarHelp =
    'Compressed TAR is limited to 64 MiB after decompression, including archive headers.';
const _hfsHelp =
    'Creates a case-sensitive HFSX data volume. Names use HFS Unicode normalization. Resource forks, extended attributes and symbolic links are not copied.';
const _isoHelp =
    'Creates a data-only ISO with Rock Ridge and Joliet names. Boot records and UDF filesystems are not created.';
const _lz4Help =
    'LZ4 offers fast compression or storage without compression. Both modes include content checksums.';
const _lzmaHelp =
    'LZMA uses a 64 KiB dictionary for Fast, 8 MiB for Normal and 64 MiB for Maximum. The format has no content checksum.';

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
    String selectedPath = '/input/report.txt',
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = (await backend.stat(selectedPath))!;
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
    await tester.tap(field);
    await tester.pumpAndSettle();
    // The format menu lazily builds rows outside its visible viewport.
    // Scroll toward the target before ensureVisible asks for its element.
    await tester.scrollUntilVisible(
      find.text(label),
      target.index < current.index ? -180 : 180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
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
    ArchiveCreationFormat.lz4,
    ArchiveCreationFormat.tarLz4,
    ArchiveCreationFormat.lzma,
    ArchiveCreationFormat.tarLzma,
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
      expect(find.text(lz4 ? _lz4Help : _lzmaHelp), findsOneWidget);
      expect(find.text(lz4 ? _lzmaHelp : _lz4Help), findsNothing);
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
  ]) {
    testWidgets('${value.label} displays the shared decompression limit', (
      tester,
    ) async {
      await show(tester);
      await format(tester, value.label);
      expect(find.text(_compressedTarHelp), findsOneWidget);
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
        'gzip — one file',
        'bzip2 — one file',
        'XZ — one file',
        'Zstandard — one file',
        'LZ4 — one file',
        'LZMA — one file',
        'ISO data image',
        'HFSX data image',
        'DMG (HFSX data volume)',
        'AR — flat files',
        'JAR (unsigned)',
        'WAR (unsigned)',
        'EAR (unsigned)',
        _dataImageHelp,
        _singleFileHelp,
        _flatFilesHelp,
        _compressedTarHelp,
        _hfsHelp,
        _isoHelp,
        _lz4Help,
        _lzmaHelp,
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
        ArchiveCreationFormat.lz4,
        ArchiveCreationFormat.lzma,
        ArchiveCreationFormat.xz,
      ]) {
        await format(tester, tr(tester, value.label));
        expect(find.text(tr(tester, value.label)), findsOneWidget);
        final help = value.diskImage
            ? _dataImageHelp
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
            value == ArchiveCreationFormat.tarLzma) {
          final detail =
              value == ArchiveCreationFormat.lz4 ||
                  value == ArchiveCreationFormat.tarLz4
              ? _lz4Help
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
