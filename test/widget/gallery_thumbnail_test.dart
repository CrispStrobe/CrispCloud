import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/gallery_media_provider.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/services/thumbnail_service.dart';
import 'package:crisp_cloud/widgets/gallery_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _DelayedMedia extends GalleryMediaService {
  _DelayedMedia() : super(thumbnails: ThumbnailService());
  final loads = <String, Completer<Uint8List?>>{};
  @override
  Future<Uint8List?> loadThumbnail(GalleryMediaRequest request,
      {int size = 256, bool retry = false}) =>
      (loads[request.namespaceId] ??= Completer<Uint8List?>()).future;
}

void main() {
  final file = FileItem(name: 'same.png', path: '/same.png', isFolder: false);
  Uint8List png(int width) => img.encodePng(img.Image(width: width, height: 2));
  GalleryMediaRequest request(String account, {bool Function()? current}) =>
      GalleryMediaRequest(file: file, namespaceId: account, path: '/same.png',
          readBytes: (_) async => png(2), isCurrent: current);

  testWidgets('a recycled tile never shows an earlier account result', (tester) async {
    final media = _DelayedMedia();
    Widget view(GalleryMediaRequest source) => ProviderScope(
      overrides: [galleryMediaServiceProvider.overrideWithValue(media)],
      child: MaterialApp(home: Scaffold(body: Center(child: GalleryThumbnail(
        side: PanelSide.local, file: file, request: source, width: 160, height: 120,
      )))),
    );
    final first = request('account-a');
    final second = request('account-b');
    await tester.pumpWidget(view(first));
    await tester.pumpWidget(view(second));
    final expected = png(4);
    media.loads['account-b']!.complete(expected);
    await tester.pump();
    final displayed = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    expect(displayed.bytes, expected);
    media.loads['account-a']!.complete(png(8));
    await tester.pump();
    final stillDisplayed = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    expect(stillDisplayed.bytes, expected);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalidating a captured source immediately hides cached pixels', (tester) async {
    final media = _DelayedMedia();
    var alive = true;
    final source = request('one', current: () => alive);
    Widget view() => ProviderScope(
      overrides: [galleryMediaServiceProvider.overrideWithValue(media)],
      child: MaterialApp(home: Scaffold(body: Center(child: GalleryThumbnail(
        side: PanelSide.remote, file: file, request: source, width: 160, height: 120,
      )))),
    );
    await tester.pumpWidget(view());
    media.loads['one']!.complete(png(3));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    alive = false;
    await tester.pumpWidget(view());
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
