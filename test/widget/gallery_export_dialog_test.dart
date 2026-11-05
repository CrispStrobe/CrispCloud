import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/gallery_device_export.dart';
import 'package:crisp_cloud/services/gallery_export_service.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/widgets/gallery_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreparedService extends GalleryExportService {
  _PreparedService(this.report) : super(loadImage: (_) async =>
    throw StateError('The prepared dialog fixture does not read files.'));

  final GalleryExportReport report;

  @override
  Future<GalleryExportReport> convert(List<GalleryMediaRequest> requests, {
    GalleryConversionOptions options = const GalleryConversionOptions(),
    GalleryExportCancellation? cancellation,
    void Function(GalleryExportProgress)? onProgress,
  }) async => report;
}

GalleryMediaRequest _request({bool Function()? current}) => GalleryMediaRequest(
  file: FileItem(name: 'photo.png', path: '/photo.png', isFolder: false),
  namespaceId: 'test', path: '/photo.png',
  readBytes: (_) async => Uint8List(0), isCurrent: current,
);

GalleryExportReport _ready() => GalleryExportReport(
  suggestedName: 'crispcloud-images.zip', mimeType: 'application/zip',
  bytes: Uint8List.fromList([1, 2, 3]),
  items: const [GalleryExportItemResult(sourceName: 'photo.png',
    outputName: 'photo.jpg', width: 24, height: 16)],
);

Future<void> _pump(WidgetTester tester, {
  required GalleryExportReport report,
  required GalleryDeviceExporter exporter,
  GalleryMediaRequest? request,
}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: GalleryExportDialog(
    requests: [request ?? _request()], service: _PreparedService(report),
    exporter: exporter,
  ))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelled save keeps the prepared export and does not claim success', (tester) async {
    var saves = 0;
    await _pump(tester, report: _ready(),
      exporter: (bytes, name, {mimeType, dialogTitle}) async {
        saves++;
        expect(name, 'crispcloud-images.zip');
        expect(mimeType, 'application/zip');
        return null;
      });
    await tester.tap(find.text('Create ZIP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save copy'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Save cancelled. Your prepared export is still available.'), findsOneWidget);
    expect(find.text('Copy saved.'), findsNothing);
    expect(find.text('Save copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a batch with no converted images never offers to save', (tester) async {
    var saves = 0;
    await _pump(tester, report: GalleryExportReport(
      suggestedName: 'crispcloud-images.zip', mimeType: 'application/zip',
      items: const [GalleryExportItemResult(sourceName: 'photo.png',
        problem: GalleryExportProblem.invalidImage)],
    ), exporter: (bytes, name, {mimeType, dialogTitle}) async {
      saves++;
      return GalleryExportResult.savedCopy;
    });
    await tester.tap(find.text('Create ZIP'));
    await tester.pumpAndSettle();
    expect(find.text('No images could be exported.'), findsOneWidget);
    expect(find.text('Save copy'), findsNothing);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale source is checked again at the save boundary', (tester) async {
    var current = true;
    var saves = 0;
    await _pump(tester, report: _ready(), request: _request(current: () => current),
      exporter: (bytes, name, {mimeType, dialogTitle}) async {
        saves++;
        return GalleryExportResult.savedCopy;
      });
    await tester.tap(find.text('Create ZIP'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('Save copy'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('The source or connection changed. Reopen the export.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch export controls fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, report: _ready(),
      exporter: (bytes, name, {mimeType, dialogTitle}) async => null);
    expect(find.text('Create ZIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
