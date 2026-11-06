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

  testWidgets(
    'Windows flags keep unselected values and preview creation time before writes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = _AttributesBackend(windows: true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
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
      expect(find.byKey(const ValueKey('attributes-mode')), findsNothing);
      final created = find.byKey(const ValueKey('attributes-created'));
      await tester.enterText(created, '2022-03-04 05:06:07');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final readOnly = find.byKey(const ValueKey('attributes-windows-1'));
      final hidden = find.byKey(const ValueKey('attributes-windows-2'));
      expect(tester.widget<CheckboxListTile>(readOnly).value, isNull);
      await Scrollable.ensureVisible(tester.element(readOnly), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: readOnly, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(readOnly).value, isFalse);
      await Scrollable.ensureVisible(tester.element(hidden), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: hidden, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(of: hidden, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(hidden).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('attributes-preview')));
      await tester.pumpAndSettle();
      expect(backend.writes, 0);
      final apply = find.byKey(const ValueKey('attributes-apply'));
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(backend.flags, 0x26);
      expect(backend.created, DateTime(2022, 3, 4, 5, 6, 7));
      expect(backend.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
  _AttributesBackend({this.windows = false});
  final bool windows;
  final file = FileItem(
    name: 'document.txt',
    path: '/documents/document.txt',
    isFolder: false,
    size: 5,
  );
  int mode = 0x1ed;
  int writes = 0;
  int flags = 0x25;
  DateTime created = DateTime.utc(2020);
  @override
  Object get identity => 'captured-attributes-test';
  @override
  bool get isCurrent => true;
  @override
  String get label => 'Original source';
  @override
  p.Context get paths => p.posix;
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    permissions: !windows,
    windowsAttributes: windows,
    setCreatedTime: windows,
  );
  @override
  Future<FileItem?> stat(String path) async => file;
  @override
  Future<TransferMetadata> readMetadata(String path) async =>
      TransferMetadata(mode: mode, windowsAttributes: flags, created: created);
  @override
  Future<void> writeMetadata(String path, TransferMetadata metadata) async {
    mode = metadata.mode ?? mode;
    created = metadata.created ?? created;
    if (metadata.windowsAttributes != null) {
      flags =
          (flags & ~metadata.windowsAttributesMask) |
          metadata.windowsAttributes!;
    }
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
