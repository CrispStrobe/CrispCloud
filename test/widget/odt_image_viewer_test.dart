import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _odtBytes() {
  const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
 xmlns:xlink="http://www.w3.org/1999/xlink">
 <office:body><office:text>
  <text:p>Before <draw:frame draw:name="Picture 1">
   <draw:image xlink:href="Pictures/p.png"/>
  </draw:frame> after</text:p>
 </office:text></office:body>
</office:document-content>
''';
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nXQAAAAASUVORK5CYII=',
  );
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(xml)))
    ..addFile(ArchiveFile.bytes('Pictures/p.png', png));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 300,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets('ODT pictures render from bounded package data', (tester) async {
    final bytes = _odtBytes();
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          InternalViewerDialog(
            file: FileItem(
              name: 'picture.odt',
              isFolder: false,
              size: bytes.length,
            ),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find
          .byWidgetPredicate(
            (widget) => widget is Image && widget.image is MemoryImage,
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Before'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
