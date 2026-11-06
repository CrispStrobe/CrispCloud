import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_attributes_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/widgets/file_attributes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final language in ['en', 'de', 'ar']) {
    testWidgets(
      'review then apply is explicit and reachable at large text in $language',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = _AttributesBackend();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: FileAttributesDialog(
                targets: [FileAttributesTarget(backend, backend.file)],
              ),
            ),
          ),
        );
        final apply = find.byKey(const ValueKey('attributes-apply'));
        expect(tester.widget<FilledButton>(apply).onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('attributes-mode')),
          '0750',
        );
        await tester.tap(find.byKey(const ValueKey('attributes-preview')));
        await tester.pumpAndSettle();
        expect(backend.writes, 0, reason: 'Preview must remain read-only.');
        expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(backend.mode, 0x1e8);
        expect(backend.writes, 1);
        expect(tester.widget<FilledButton>(apply).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('timestamps reject normalized invalid dates instead of changing another date', () {
    expect(
      () => parseFileAttributeTime('2025-02-31 12:00:00', utc: true),
      throwsFormatException,
    );
    expect(
      () => parseFileAttributeTime('2025-02-01 25:00:00', utc: true),
      throwsFormatException,
    );
    expect(
      parseFileAttributeTime('2024-02-29 12:34:56', utc: true),
      DateTime.utc(2024, 2, 29, 12, 34, 56),
    );
    expect(parseFileAttributeTime('', utc: false), isNull);
  });
}

class _AttributesBackend extends FileOperationBackend {
  final file = FileItem(
    name: 'document.txt',
    path: '/documents/document.txt',
    isFolder: false,
    size: 5,
  );
  int mode = 0x1ed;
  int writes = 0;
  @override
  Object get identity => 'captured-attributes-test';
  @override
  bool get isCurrent => true;
  @override
  String get label => 'Original source';
  @override
  p.Context get paths => p.posix;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(permissions: true);
  @override
  Future<FileItem?> stat(String path) async => file;
  @override
  Future<TransferMetadata> readMetadata(String path) async =>
      TransferMetadata(mode: mode);
  @override
  Future<void> writeMetadata(String path, TransferMetadata metadata) async {
    mode = metadata.mode!;
    writes++;
  }

  @override
  Future<List<FileItem>> list(String path) => throw UnimplementedError();
  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteEmptyDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteFile(FileItem file) => throw UnimplementedError();
  @override
  Stream<List<int>> readFile(FileItem file) => throw UnimplementedError();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => throw UnimplementedError();
}
