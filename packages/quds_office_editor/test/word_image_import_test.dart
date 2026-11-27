import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_image_import.dart';
import 'package:super_clipboard/super_clipboard.dart';

class _Progress extends Fake implements ReadProgress {}

class _File extends Fake implements DataReaderFile {
  _File(this.bytes, this.fileSize);

  final Uint8List bytes;
  @override
  final int? fileSize;

  @override
  Stream<Uint8List> getStream() => Stream.value(bytes);
}

class _ImageReader extends Fake implements ClipboardDataReader {
  _ImageReader({this.bytes, this.uri, this.claimedSize});

  final Uint8List? bytes;
  final Uri? uri;
  final int? claimedSize;
  var opened = 0;

  @override
  bool canProvide(DataFormat format) =>
      (format == Formats.png && bytes != null) ||
      (format == Formats.fileUri && uri != null);

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async => null;

  @override
  ReadProgress? getValue<T extends Object>(
    ValueFormat<T> format,
    AsyncValueChanged<T?> onValue, {
    void Function(Object)? onError,
  }) {
    if (T != Uri || uri == null) return null;
    unawaited(Future<void>.sync(() => onValue(uri as T)));
    return _Progress();
  }

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    void Function(Object)? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    expect(synthesizeFilesFromURIs, isFalse);
    if (format != Formats.png || bytes == null) return null;
    opened++;
    unawaited(Future<void>.sync(() => onFile(_File(bytes!, claimedSize))));
    return _Progress();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'image-only clipboard data survives DOCX save and is undoable',
    () async {
      final bytes = PngBytes.studioCard(width: 40, height: 20);
      final reader = _ImageReader(bytes: bytes);
      final payload = await OfficeClipboard.readWordRepresentations(
        reader,
        includeImages: true,
      );
      final picture = payload!.visual!;
      expect(picture.imageBytes, isNotNull);
      expect(picture.width / picture.height, 2);
      expect(reader.opened, 1);
      final ignored = await OfficeClipboard.readWordRepresentations(reader);
      expect(ignored, isNull);
      expect(reader.opened, 1);

      final clipboard = OfficeClipboard.instance;
      final useSystem = clipboard.useSystem;
      clipboard.useSystem = false;
      clipboard.writeLocal(payload);
      addTearDown(() {
        clipboard.clear();
        clipboard.useSystem = useSystem;
      });
      final controller = WordEditorController(document: WmlDocument.empty());
      addTearDown(controller.dispose);
      await controller.pasteFromClipboard(mode: OfficePasteMode.keepTextOnly);
      expect(controller.document.visuals, isEmpty);
      await controller.pasteFromClipboard();
      final reopened = WordDeserializer().read(
        OfficeRepair.open(controller.saveBytes()),
      );
      expect(reopened.visuals.single.visual.imageBytes, picture.imageBytes);
      controller.undo();
      expect(controller.document.visuals, isEmpty);
    },
  );

  test(
    'drop reads local raster files and places them after the target paragraph',
    () async {
      final folder = await Directory.systemTemp.createTemp('crisp-image-drop-');
      addTearDown(() => folder.delete(recursive: true));
      final file = await File(
        '${folder.path}/picture.png',
      ).writeAsBytes(PngBytes.studioCard(width: 40, height: 20));
      final raw = await WordImageImport.readBytes(
        _ImageReader(uri: file.uri),
        localFiles: true,
      );
      expect(raw, isNotNull);
      final picture = await WordImageImport.normalize(raw!);
      expect(picture, isNotNull);
      final first = WmlParagraph(inlines: [WmlRun(text: 'First')]);
      final second = WmlParagraph(inlines: [WmlRun(text: 'Second')]);
      final controller = WordEditorController(
        document: WmlDocument(
          sections: [
            WmlSection(blocks: [first, second]),
          ],
        ),
      );
      addTearDown(controller.dispose);
      expect(
        controller.insertImportedPictures([picture!], after: first),
        isTrue,
      );
      expect(controller.document.sections.single.blocks, [
        first,
        isA<WmlVisual>(),
        second,
      ]);
      controller.undo();
      expect(controller.document.sections.single.blocks, [first, second]);
    },
  );

  test(
    'image import rejects disguised, malformed, oversized or remote data',
    () async {
      final good = PngBytes.studioCard(width: 32, height: 32);
      final svg = Uint8List.fromList(
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
        ),
      );
      expect(await WordImageImport.normalize(svg), isNull);
      expect(await WordImageImport.normalize(good.sublist(0, 16)), isNull);
      expect(
        await WordImageImport.normalize(
          PngBytes.studioCard(width: 8193, height: 16),
        ),
        isNull,
      );
      final trailing = Uint8List.fromList([
        ...good,
        ...utf8.encode('DROP_METADATA_SENTINEL'),
      ]);
      final sanitized = await WordImageImport.normalize(trailing);
      expect(
        latin1.decode(sanitized!.imageBytes!),
        isNot(contains('DROP_METADATA_SENTINEL')),
      );
      expect(
        await WordImageImport.readBytes(
          _ImageReader(
            bytes: good,
            claimedSize: WordImageImport.maxInputBytes + 1,
          ),
        ),
        isNull,
      );
      expect(
        await WordImageImport.readBytes(
          _ImageReader(
            bytes: good,
            uri: Uri.parse('https://example.com/picture.png'),
          ),
          localFiles: true,
        ),
        isNull,
      );
      expect(
        await WordImageImport.readBytes(
          _ImageReader(uri: Uri.parse('file://network-share/picture.png')),
          localFiles: true,
        ),
        isNull,
      );
    },
  );
}
