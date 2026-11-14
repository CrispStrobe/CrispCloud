import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/disk_partition_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/disk_partition_inspector.dart';
import 'package:crisp_cloud/widgets/disk_partition_dialog.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/disk_partition_fixture.dart';
import '../support/archive_disk_image_fixture.dart';
import '../support/archive_fat_reference_data.dart';

Uint8List _mbr() {
  final bytes = Uint8List(32 * 512);
  bytes[450] = 0x83;
  final data = ByteData.sublistView(bytes);
  data.setUint32(454, 1, Endian.little);
  data.setUint32(458, 16, Endian.little);
  bytes[510] = 0x55;
  bytes[511] = 0xaa;
  return bytes;
}

Future<void> _open(WidgetTester tester, Uint8List bytes) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: InternalViewerDialog(
          file: FileItem(name: 'disk.img', isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
  await tester.pumpAndSettle();
}

Future<void> _waitForReport(WidgetTester tester) async {
  // The inspector yields between reads. Pump those timers as well as frames.
  for (
    var i = 0;
    i < 40 && find.byType(DiskPartitionDialog).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(find.byType(DiskPartitionDialog), findsOneWidget);
}

Future<void> _inspect(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('viewer-partition-structure'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await _waitForReport(tester);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find
          .descendant(
            of: find.byType(DiskPartitionDialog),
            matching: find.byType(Scrollable),
          )
          .last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _revealArchiveMember(WidgetTester tester, String path) async {
  for (
    var i = 0;
    i < 80 && find.textContaining('   ·   DISK-IMAGE').evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(find.textContaining('   ·   DISK-IMAGE'), findsOneWidget);
  final list = find
      .descendant(
        of: find.byType(InternalViewerDialog),
        matching: find.byType(ListView),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text(path),
    120,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  expect(find.text(path), findsOneWidget);
}

void main() {
  testWidgets(
    'a short unknown file is not reported as an ambiguous sector size',
    (tester) async {
      await _open(tester, Uint8List.fromList([1, 2, 3]));
      await _inspect(tester);
      expect(find.text('No recognized partition table'), findsOneWidget);
      expect(find.text('Sector size is ambiguous'), findsNothing);
      final report = tester.widget<DiskPartitionDialog>(
        find.byType(DiskPartitionDialog),
      );
      expect(
        report.analysis.findings.map((f) => f.code),
        contains(DiskPartitionFindingCode.truncated),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(HexViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GPT mirror CRC results stay separate and backup fields select their real offsets',
    (tester) async {
      final fixture = DiskPartitionFixture.gpt();
      fixture.primaryHeader[16] ^= 0x80;
      fixture.backupTable[56] ^= 1;
      final bytes = fixture.materialize();
      final original = bytes.toList();
      await _open(tester, bytes);
      final source = tester.widget<HexViewer>(find.byType(HexViewer)).source;
      await _inspect(tester);
      expect(
        find.byKey(const ValueKey('partition-browse-image')),
        findsNothing,
      );
      final primary = find.byKey(const ValueKey('partition-header-primary'));
      await _reveal(tester, primary);
      expect(
        find.descendant(
          of: primary,
          matching: find.text('Header CRC: Does not match'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: primary,
          matching: find.text('Entry table CRC: Matches'),
        ),
        findsOneWidget,
      );
      final backup = find.byKey(const ValueKey('partition-header-backup'));
      await _reveal(tester, backup);
      expect(
        find.descendant(of: backup, matching: find.text('Header CRC: Matches')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: backup,
          matching: find.text('Entry table CRC: Does not match'),
        ),
        findsOneWidget,
      );
      final offset = fixture.totalBytes - fixture.sectorBytes;
      final group = find.byKey(
        ValueKey('partition-group-$offset-Backup GPT header'),
      );
      await _reveal(tester, group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      final guid = find.byKey(
        ValueKey('partition-field-${offset + 56}-Disk GUID'),
      );
      await _reveal(tester, guid);
      await tester.tap(guid);
      await tester.pumpAndSettle();
      final hex = tester.widget<HexViewer>(find.byType(HexViewer));
      expect(hex.source, same(source));
      expect(hex.highlightRangeStart, offset + 56);
      expect(hex.highlightRangeEnd, offset + 72);
      expect(bytes, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partition field selection highlights real bytes in the same Hex source',
    (tester) async {
      final bytes = _mbr();
      final original = bytes.toList();
      await _open(tester, bytes);
      final source = tester.widget<HexViewer>(find.byType(HexViewer)).source;
      await _inspect(tester);
      expect(find.text('Disk partitions'), findsOneWidget);
      expect(find.text('MBR'), findsOneWidget);
      final group = find.byKey(
        const ValueKey('partition-group-0-Master boot record'),
      );
      await _reveal(tester, group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      final signature = find.byKey(
        const ValueKey('partition-field-510-Boot-sector signature'),
      );
      await _reveal(tester, signature);
      await tester.tap(signature);
      await tester.pumpAndSettle();
      expect(find.byType(DiskPartitionDialog), findsNothing);
      final hex = tester.widget<HexViewer>(find.byType(HexViewer));
      expect(hex.source, same(source));
      expect(hex.selectedByte, 510);
      expect(hex.highlightRangeStart, 510);
      expect(hex.highlightRangeEnd, 512);
      expect(bytes, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit sector size reinspects MBR bounds without changing bytes',
    (tester) async {
      final bytes = _mbr();
      final original = bytes.toList();
      await _open(tester, bytes);
      final source = tester.widget<HexViewer>(find.byType(HexViewer)).source;
      await _inspect(tester);
      final selector = find.byKey(const ValueKey('partition-sector-size'));
      await _reveal(tester, selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4096 B').last);
      await _waitForReport(tester);
      expect(find.text('Logical sector size: 4096 B'), findsOneWidget);
      final report = tester.widget<DiskPartitionDialog>(
        find.byType(DiskPartitionDialog),
      );
      expect(
        report.analysis.findings.map((f) => f.code),
        contains(DiskPartitionFindingCode.outOfRange),
      );
      expect(
        find.byKey(const ValueKey('partition-browse-image')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HexViewer>(find.byType(HexViewer)).source,
        same(source),
      );
      expect(bytes, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Browse image retains the selected 4096-byte geometry across Hex and Archive',
    (tester) async {
      final fixture = DiskImageFixture.mbr(
        volumes: [FatReferenceSource('fat16-sector4096')],
        sectorBytes: 4096,
        types: [0x06],
      );
      final bytes = (await tester.runAsync(
        () => fixture.read(0, fixture.length),
      ))!;
      final digest = sha256.convert(bytes);
      await _open(tester, bytes);
      final source = tester.widget<HexViewer>(find.byType(HexViewer)).source;
      await _inspect(tester);
      final selector = find.byKey(const ValueKey('partition-sector-size'));
      await _reveal(tester, selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4096 B').last);
      await _waitForReport(tester);
      expect(find.text('Logical sector size: 4096 B'), findsOneWidget);
      final browse = find.byKey(const ValueKey('partition-browse-image'));
      expect(browse, findsOneWidget);
      await tester.tap(browse);
      await _revealArchiveMember(tester, 'partition-001/files/café-雪.txt');
      expect(find.byType(DiskPartitionDialog), findsNothing);
      expect(find.text('partition-001/files/café-雪.txt'), findsOneWidget);
      expect(find.textContaining('   ·   DISK-IMAGE'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HexViewer>(find.byType(HexViewer)).source,
        same(source),
      );
      await _inspect(tester);
      expect(find.text('Logical sector size: 4096 B'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
      await _revealArchiveMember(tester, 'partition-001/files/café-雪.txt');
      expect(find.text('partition-001/files/café-雪.txt'), findsOneWidget);
      expect(sha256.convert(bytes), digest);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mode change cancels metadata inspection before a stale report opens',
    (tester) async {
      await _open(tester, _mbr());
      final action = find.byKey(const ValueKey('viewer-partition-structure'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Text'))
          .onSelected!(true);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(find.byType(DiskPartitionDialog), findsNothing);
      expect(find.byType(HexViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing the viewer during inspection discards the pending report',
    (tester) async {
      await _open(tester, _mbr());
      final action = find.byKey(const ValueKey('viewer-partition-structure'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(DiskPartitionDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small screens and enlarged text retain a reachable Close action',
    (tester) async {
      final bytes = _mbr();
      final analysis = await tester.runAsync(
        () => inspectDiskPartitions(
          totalBytes: bytes.length,
          read: (offset, length) =>
              Uint8List.sublistView(bytes, offset, offset + length),
        ),
      );
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<DiskPartitionDialogResult>(
                  context: context,
                  builder: (_) => DiskPartitionDialog(
                    analysis: analysis!,
                    filename: 'disk.img',
                    canBrowse: true,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final close = find.widgetWithText(TextButton, 'Close');
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(480));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(DiskPartitionDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partition controls and CRC statuses are localized', (
    tester,
  ) async {
    final titles = <String>{};
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
      late DiskPartitionStrings strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              strings = DiskPartitionStrings(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      titles.add(strings.text('title'));
      for (final key in [
        'inspect',
        'scope',
        'sectorSize',
        'primary',
        'backup',
        'valid',
        'invalid',
        'unchecked',
        'missing',
      ]) {
        expect(strings.text(key), isNotEmpty);
      }
      expect(strings.summary(512, 8192), contains('512'));
      expect(strings.summary(512, 8192), contains('8192'));
    }
    expect(titles, hasLength(9));
    expect(tester.takeException(), isNull);
  });
}
