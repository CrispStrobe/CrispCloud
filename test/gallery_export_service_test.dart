import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/gallery_export_service.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

GalleryMediaRequest _request(String name, {int? size, bool Function()? current}) =>
    GalleryMediaRequest(file: FileItem(name: name, path: '/images/$name',
      isFolder: false, size: size), namespaceId: 'test', path: '/images/$name',
      readBytes: (_) async => Uint8List(0), isCurrent: current);

Uint8List _png({int width = 4, int height = 3, bool transparent = false}) {
  final pixels = image.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels.setPixelRgba(x, y, x.isEven ? 255 : 0, 0,
        x.isEven ? 0 : 255, transparent ? 0 : 255);
    }
  }
  return image.encodePng(pixels);
}

GalleryImageData _data(Uint8List bytes, {int width = 4, int height = 3,
    int frameCount = 1, bool isSvg = false}) => GalleryImageData(
  bytes: bytes, width: width, height: height,
  frameCount: frameCount, isSvg: isSvg,
);

List<ArchiveFile> _imageEntries(GalleryExportReport report) =>
    ZipDecoder().decodeBytes(report.bytes!).files.where((entry) =>
      entry.name.endsWith('.png') || entry.name.endsWith('.jpg')).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ZIP copies have case-insensitive collision-safe flat names and a report', () async {
    final original = _png();
    final snapshot = Uint8List.fromList(original);
    final service = GalleryExportService(loadImage: (_) async => _data(original));
    final report = await service.convert([
      _request('../photo.jpg'), _request('PHOTO.png'),
      _request('folder\\photo.gif'), _request('CON.png'),
    ], options: const GalleryConversionOptions(format: GalleryExportFormat.png));

    expect(report.hasOutput, isTrue);
    expect(report.succeeded, 4);
    expect(report.failed, 0);
    final archive = ZipDecoder().decodeBytes(report.bytes!);
    final names = archive.files.map((file) => file.name).toList();
    expect(names, containsAll([
      'photo.png', 'PHOTO (2).png', 'photo (3).png', 'image_CON.png',
      'crispcloud-export-report.json',
    ]));
    expect(names.any((name) => name.contains('/') || name.contains('\\')), isFalse);
    final manifest = archive.findFile('crispcloud-export-report.json')!;
    final json = jsonDecode(utf8.decode(manifest.content as List<int>)) as Map;
    expect((json['files'] as List).length, 4);
    expect(original, orderedEquals(snapshot), reason: 'Original bytes are immutable input.');
  });

  test('rotation and flip change pixels, while fit preserves aspect ratio', () async {
    final original = _png(width: 2, height: 1);
    final service = GalleryExportService(loadImage: (_) async =>
      _data(original, width: 2, height: 1));
    final report = await service.convert([_request('strip.png')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png,
        quarterTurns: 1, flipVertical: true, maxWidth: 2, maxHeight: 2));
    final pixels = image.decodePng(Uint8List.fromList(
      _imageEntries(report).single.content as List<int>))!;
    expect((pixels.width, pixels.height), (1, 2));
    expect(pixels.getPixel(0, 0).b, 255);
    expect(pixels.getPixel(0, 0).r, 0);
    expect(pixels.getPixel(0, 1).r, 255);
  });

  test('resize does not upscale unless explicitly enabled', () async {
    final bytes = _png(width: 4, height: 2);
    final service = GalleryExportService(loadImage: (_) async =>
      _data(bytes, width: 4, height: 2));
    final normal = await service.convert([_request('small.png')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png,
        maxWidth: 8, maxHeight: 8));
    expect((normal.items.single.width, normal.items.single.height), (4, 2));
    final enlarged = await service.convert([_request('small.png')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png,
        maxWidth: 8, maxHeight: 8, allowUpscale: true));
    expect((enlarged.items.single.width, enlarged.items.single.height), (8, 4));
  });

  test('JPEG flattens transparent pixels against white', () async {
    final bytes = _png(width: 8, height: 8, transparent: true);
    final service = GalleryExportService(loadImage: (_) async =>
      _data(bytes, width: 8, height: 8));
    final report = await service.convert([_request('transparent.png')]);
    final pixels = image.decodeJpg(Uint8List.fromList(
      _imageEntries(report).single.content as List<int>))!;
    final center = pixels.getPixel(4, 4);
    expect(center.r, greaterThan(245));
    expect(center.g, greaterThan(245));
    expect(center.b, greaterThan(245));
  });

  test('EXIF orientation is baked and descriptive PNG metadata is omitted', () async {
    final pixels = image.Image(width: 6, height: 2, numChannels: 3)
      ..clear(image.ColorRgb8(20, 80, 120));
    pixels.exif.imageIfd.orientation = 6;
    final source = image.encodeJpg(pixels);
    final service = GalleryExportService(loadImage: (_) async =>
      _data(source, width: 6, height: 2));
    final report = await service.convert([_request('oriented.jpg')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png));
    final output = image.decodePng(Uint8List.fromList(
      _imageEntries(report).single.content as List<int>))!;
    expect((output.width, output.height), (2, 6));
    expect(output.exif.imageIfd.orientation, isNull);

    final tagged = image.Image(width: 4, height: 3, numChannels: 3)
      ..addTextData({'Comment': 'private caption', 'XML:com.adobe.xmp': 'private XMP'});
    final taggedService = GalleryExportService(loadImage: (_) async =>
      _data(image.encodePng(tagged)));
    final stripped = await taggedService.convert([_request('tagged.png')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png));
    final decoded = image.decodePng(Uint8List.fromList(
      _imageEntries(stripped).single.content as List<int>))!;
    expect(decoded.textData ?? const <String, String>{}, isEmpty);
  });

  test('animated inputs export only the first frame and disclose it', () async {
    final first = image.Image(width: 2, height: 2, numChannels: 3)
      ..clear(image.ColorRgb8(255, 0, 0));
    final second = image.Image(width: 2, height: 2, numChannels: 3)
      ..clear(image.ColorRgb8(0, 0, 255));
    first.addFrame(second);
    final bytes = image.encodeGif(first);
    final service = GalleryExportService(loadImage: (_) async =>
      _data(bytes, width: 2, height: 2, frameCount: 2));
    final report = await service.convert([_request('animated.gif')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png));
    expect(report.items.single.firstFrameOnly, isTrue);
    final output = image.decodePng(Uint8List.fromList(
      _imageEntries(report).single.content as List<int>))!;
    expect(output.numFrames, 1);
    expect(output.getPixel(0, 0).r, greaterThan(245));
    expect(output.getPixel(0, 0).b, lessThan(10));
  });

  test('color adjustment is applied to exported pixels', () async {
    final service = GalleryExportService(loadImage: (_) async => _data(_png()));
    final report = await service.convert([_request('photo.png')],
      options: const GalleryConversionOptions(format: GalleryExportFormat.png,
        brightness: 0));
    final output = image.decodePng(Uint8List.fromList(
      _imageEntries(report).single.content as List<int>))!;
    expect(output.getPixel(0, 0).r, 0);
    expect(output.getPixel(1, 0).b, 0);
  });

  test('mixed failures are reported and are absent from ZIP image entries', () async {
    final service = GalleryExportService(loadImage: (request) async {
      if (request.file.name == 'failed.png') throw StateError('private provider detail');
      return _data(_png());
    });
    final report = await service.convert([_request('good.png'), _request('failed.png')]);
    expect(report.hasOutput, isTrue);
    expect(report.succeeded, 1);
    expect(report.failed, 1);
    expect(report.items.last.problem, GalleryExportProblem.readFailed);
    expect(_imageEntries(report).map((file) => file.name), ['good.jpg']);
    expect(utf8.decode(ZipDecoder().decodeBytes(report.bytes!)
      .findFile('crispcloud-export-report.json')!.content as List<int>),
      isNot(contains('private provider detail')));
  });

  test('all invalid or unsupported inputs never create an empty successful ZIP', () async {
    final service = GalleryExportService(loadImage: (request) async =>
      request.file.name.endsWith('.svg')
        ? _data(Uint8List.fromList(utf8.encode('<svg/>')), isSvg: true)
        : _data(Uint8List.fromList([1, 2, 3, 4])));
    final report = await service.convert([_request('bad.png'), _request('vector.svg')]);
    expect(report.hasOutput, isFalse);
    expect(report.bytes, isNull);
    expect(report.succeeded, 0);
    expect(report.failed, 2);
  });

  test('file count and option validation run before any source read', () async {
    var reads = 0;
    final service = GalleryExportService(
      limits: const GalleryExportLimits(maxFiles: 1),
      loadImage: (_) async { reads++; return _data(_png()); });
    await expectLater(service.convert([]), throwsA(isA<GalleryExportException>()
      .having((error) => error.problem, 'problem', GalleryExportProblem.noImages)));
    await expectLater(service.convert([_request('one.png'), _request('two.png')]),
      throwsA(isA<GalleryExportException>().having((error) => error.problem,
        'problem', GalleryExportProblem.tooManyFiles)));
    await expectLater(service.convert([_request('one.png')],
      options: const GalleryConversionOptions(maxWidth: 0)),
      throwsA(isA<GalleryExportException>().having((error) => error.problem,
        'problem', GalleryExportProblem.invalidOptions)));
    await expectLater(service.convert([_request('one.png')],
      options: const GalleryConversionOptions(brightness: double.nan)),
      throwsA(isA<GalleryExportException>()));
    expect(reads, 0);
  });

  test('declared source byte limits stop oversized reads', () async {
    var reads = 0;
    final service = GalleryExportService(
      limits: const GalleryExportLimits(maxInputBytes: 16),
      loadImage: (_) async { reads++; return _data(_png()); });
    final report = await service.convert([_request('large.png', size: 17)]);
    expect(reads, 0);
    expect(report.items.single.problem, GalleryExportProblem.inputTooLarge);
    expect(report.hasOutput, isFalse);
  });

  test('actual input bytes and advertised decoded dimensions are bounded', () async {
    final source = _png();
    final bytesService = GalleryExportService(
      limits: GalleryExportLimits(maxInputBytes: source.length - 1),
      loadImage: (_) async => _data(source));
    final bytesReport = await bytesService.convert([_request('unknown-size.png')]);
    expect(bytesReport.items.single.problem, GalleryExportProblem.inputTooLarge);
    final pixelsService = GalleryExportService(loadImage: (_) async =>
      _data(source, width: 100000, height: 100000));
    final pixelsReport = await pixelsService.convert([_request('oversized.png')]);
    expect(pixelsReport.hasOutput, isFalse);
    expect(pixelsReport.failed, 1);
  });

  test('unknown-size sources receive the export byte cap at the actual reader', () async {
    final bytes = _png();
    final cap = bytes.length + 1;
    int? requestedLimit;
    final request = GalleryMediaRequest(
      file: FileItem(name: 'unknown.png', path: '/unknown.png', isFolder: false),
      namespaceId: 'test', path: '/unknown.png',
      readBytes: (limit) async { requestedLimit = limit; return bytes; },
    );
    final service = GalleryExportService(
      limits: GalleryExportLimits(maxInputBytes: cap),
      loadImage: (bounded) async => _data(await bounded.readBytes(1024 * 1024)),
    );
    final report = await service.convert([request]);
    expect(requestedLimit, cap);
    expect(report.hasOutput, isTrue);
  });

  test('output bytes and pixel limits reject oversized conversions', () async {
    final bytesService = GalleryExportService(
      limits: const GalleryExportLimits(maxOutputBytes: 1),
      loadImage: (_) async => _data(_png()));
    final bytesReport = await bytesService.convert([_request('photo.png')]);
    expect(bytesReport.items.single.problem, GalleryExportProblem.outputTooLarge);
    expect(bytesReport.bytes, isNull);
    final pixelsService = GalleryExportService(
      limits: const GalleryExportLimits(maxOutputPixels: 3),
      loadImage: (_) async => _data(_png()));
    final pixelsReport = await pixelsService.convert([_request('photo.png')]);
    expect(pixelsReport.items.single.problem, GalleryExportProblem.outputTooLarge);
    expect(pixelsReport.bytes, isNull);
  });

  test('aggregate input limit stops subsequent reads', () async {
    final bytes = _png();
    var reads = 0;
    final service = GalleryExportService(
      limits: GalleryExportLimits(maxTotalInputBytes: bytes.length + 1),
      loadImage: (_) async { reads++; return _data(bytes); });
    final report = await service.convert([
      _request('one.png', size: bytes.length),
      _request('two.png', size: bytes.length),
    ]);
    expect(reads, 1);
    expect(report.succeeded, 1);
    expect(report.items.last.problem, GalleryExportProblem.inputBudgetExceeded);
  });

  test('cancel between files prevents further reads and discards prepared output', () async {
    var reads = 0;
    var active = 0;
    var peak = 0;
    final token = GalleryExportCancellation();
    final service = GalleryExportService(loadImage: (_) async {
      reads++;
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(Duration.zero);
      active--;
      return _data(_png());
    });
    final report = await service.convert([_request('one.png'), _request('two.png')],
      cancellation: token,
      onProgress: (progress) {
        if (progress.completed == 1) token.cancel();
      });
    expect(reads, 1);
    expect(peak, 1);
    expect(report.cancelled, isTrue);
    expect(report.hasOutput, isFalse);
    expect(report.bytes, isNull);
  });

  test('source invalidated during a read cannot become an export', () async {
    var current = true;
    final service = GalleryExportService(loadImage: (_) async {
      current = false;
      return _data(_png());
    });
    final report = await service.convert([_request('photo.png', current: () => current)]);
    expect(report.items.single.problem, GalleryExportProblem.staleSource);
    expect(report.hasOutput, isFalse);
  });

  test('earlier sources are checked again before packing the complete batch', () async {
    var firstCurrent = true;
    final service = GalleryExportService(loadImage: (request) async {
      if (request.file.name == 'two.png') firstCurrent = false;
      return _data(_png());
    });
    await expectLater(service.convert([
      _request('one.png', current: () => firstCurrent), _request('two.png'),
    ]), throwsA(isA<GalleryExportException>().having((error) => error.problem,
      'problem', GalleryExportProblem.staleSource)));
  });

  test('contact sheets fit images, compact failed cells, and include caption space', () async {
    final service = GalleryExportService(loadImage: (request) async {
      if (request.file.name == 'bad.png') return _data(Uint8List.fromList([1, 2]));
      return _data(_png());
    });
    const options = GalleryContactSheetOptions(columns: 2, cellWidth: 120,
      cellHeight: 90);
    final report = await service.contactSheet([
      _request('one.png'), _request('bad.png'), _request('two.png'),
    ], options: options);
    expect(report.succeeded, 2);
    expect(report.failed, 1);
    expect(report.hasOutput, isTrue);
    final sheet = image.decodePng(report.bytes!)!;
    expect((sheet.width, sheet.height),
      (options.sheetWidth(2), options.sheetHeight(2)));
    final pixel = sheet.getPixel(16 + (120 - 4) ~/ 2, 16 + (90 - 3) ~/ 2);
    expect(pixel.r, 255);
    expect(pixel.b, 0);
    var captionPixels = 0;
    for (var y = 112; y < 132; y++) {
      for (var x = 16; x < 120; x++) {
        if (sheet.getPixel(x, y).r < 200) captionPixels++;
      }
    }
    expect(captionPixels, greaterThan(0));
  });

  test('contact-sheet dimensions are validated before reading files', () async {
    var reads = 0;
    final service = GalleryExportService(
      limits: const GalleryExportLimits(maxOutputPixels: 100),
      loadImage: (_) async { reads++; return _data(_png()); });
    await expectLater(service.contactSheet([_request('one.png')]),
      throwsA(isA<GalleryExportException>().having((error) => error.problem,
        'problem', GalleryExportProblem.outputTooLarge)));
    expect(reads, 0);
  });

  test('contact sheet cancellation produces no output', () async {
    final token = GalleryExportCancellation();
    var reads = 0;
    final service = GalleryExportService(loadImage: (_) async {
      reads++;
      token.cancel();
      return _data(_png());
    });
    final report = await service.contactSheet([_request('one.png'), _request('two.png')],
      cancellation: token);
    expect(report.cancelled, isTrue);
    expect(report.hasOutput, isFalse);
    expect(reads, 1);
  });
}
