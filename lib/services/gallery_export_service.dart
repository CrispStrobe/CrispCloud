import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;

import 'gallery_media_service.dart';

enum GalleryExportFormat { jpeg, png }

enum GalleryExportProblem {
  noImages,
  tooManyFiles,
  invalidOptions,
  inputTooLarge,
  inputDimensionsTooLarge,
  inputBudgetExceeded,
  unsupportedImage,
  invalidImage,
  readFailed,
  staleSource,
  outputTooLarge,
  outputBudgetExceeded,
}

class GalleryExportException implements Exception {
  const GalleryExportException(this.problem);

  final GalleryExportProblem problem;

  @override
  String toString() => 'GalleryExportException(${problem.name})';
}

/// Independent limits for file reads, decoded pixels and retained export data.
/// Processing is sequential; originals are never used as output destinations.
class GalleryExportLimits {
  const GalleryExportLimits({
    this.maxFiles = 100,
    this.maxInputBytes = 32 * 1024 * 1024,
    this.maxTotalInputBytes = 256 * 1024 * 1024,
    this.maxInputPixels = 40 * 1000 * 1000,
    this.maxTotalInputPixels = 400 * 1000 * 1000,
    this.maxOutputPixels = 16 * 1000 * 1000,
    this.maxDimension = 16384,
    this.maxOutputBytes = 32 * 1024 * 1024,
    this.maxTotalOutputBytes = 64 * 1024 * 1024,
    this.maxArchiveBytes = 66 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxInputBytes;
  final int maxTotalInputBytes;
  final int maxInputPixels;
  final int maxTotalInputPixels;
  final int maxOutputPixels;
  final int maxDimension;
  final int maxOutputBytes;
  final int maxTotalOutputBytes;
  final int maxArchiveBytes;
}

class GalleryConversionOptions {
  const GalleryConversionOptions({
    this.format = GalleryExportFormat.jpeg,
    this.quality = 90,
    this.maxWidth,
    this.maxHeight,
    this.allowUpscale = false,
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
  });

  final GalleryExportFormat format;
  final int quality;
  final int? maxWidth;
  final int? maxHeight;
  final bool allowUpscale;
  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final double brightness;
  final double contrast;
  final double saturation;

  String get extension => format == GalleryExportFormat.jpeg ? 'jpg' : 'png';
}

class GalleryContactSheetOptions {
  const GalleryContactSheetOptions({
    this.columns = 4,
    this.cellWidth = 320,
    this.cellHeight = 240,
    this.captions = true,
  });

  final int columns;
  final int cellWidth;
  final int cellHeight;
  final bool captions;

  static const padding = 16;
  int get captionHeight => captions ? 28 : 0;
  int get rowHeight => cellHeight + captionHeight + padding;
  int sheetWidth(int count) => math.min(columns, count) *
      (cellWidth + padding) + padding;
  int sheetHeight(int count) => ((count + columns - 1) ~/ columns) *
      rowHeight + padding;
}

class GalleryExportCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

enum GalleryExportStage { loading, processing, finishing }

class GalleryExportProgress {
  const GalleryExportProgress({
    required this.completed,
    required this.total,
    required this.stage,
    this.fileName,
  });

  final int completed;
  final int total;
  final GalleryExportStage stage;
  final String? fileName;
}

class GalleryExportItemResult {
  const GalleryExportItemResult({
    required this.sourceName,
    this.outputName,
    this.width,
    this.height,
    this.problem,
    this.firstFrameOnly = false,
  });

  final String sourceName;
  final String? outputName;
  final int? width;
  final int? height;
  final GalleryExportProblem? problem;
  final bool firstFrameOnly;
  bool get succeeded => problem == null;

  Map<String, Object?> toJson() => {
    'sourceName': sourceName,
    'outputName': outputName,
    'width': width,
    'height': height,
    'status': problem?.name ?? 'exported',
    'firstFrameOnly': firstFrameOnly,
  };
}

class GalleryExportReport {
  GalleryExportReport({
    required this.suggestedName,
    required this.mimeType,
    required List<GalleryExportItemResult> items,
    this.bytes,
    this.cancelled = false,
  }) : items = List.unmodifiable(items);

  final Uint8List? bytes;
  final String suggestedName;
  final String mimeType;
  final List<GalleryExportItemResult> items;
  final bool cancelled;
  int get succeeded => items.where((item) => item.succeeded).length;
  int get failed => items.where((item) => !item.succeeded).length;
  bool get hasOutput => !cancelled && succeeded > 0 &&
      bytes != null && bytes!.isNotEmpty;
}

typedef GalleryExportImageLoader = Future<GalleryImageData> Function(
  GalleryMediaRequest request,
);

class GalleryExportService {
  GalleryExportService({
    required GalleryExportImageLoader loadImage,
    this.limits = const GalleryExportLimits(),
  }) : _loadImage = loadImage;

  final GalleryExportImageLoader _loadImage;
  final GalleryExportLimits limits;

  Future<GalleryExportReport> convert(
    List<GalleryMediaRequest> requests, {
    GalleryConversionOptions options = const GalleryConversionOptions(),
    GalleryExportCancellation? cancellation,
    void Function(GalleryExportProgress)? onProgress,
  }) async {
    _validateRequests(requests);
    _validateConversion(options, limits);
    final token = cancellation ?? GalleryExportCancellation();
    final budget = _InputBudget(limits);
    final items = <GalleryExportItemResult>[];
    final outputs = <_EncodedFile>[];
    final names = _ExportNames();
    var outputBytes = 0;

    for (final request in requests) {
      if (token.isCancelled) break;
      try {
        onProgress?.call(GalleryExportProgress(
          completed: items.length, total: requests.length,
          stage: GalleryExportStage.loading, fileName: request.file.name,
        ));
        if (token.isCancelled) break;
        final data = await _read(request, budget);
        if (token.isCancelled) break;
        onProgress?.call(GalleryExportProgress(
          completed: items.length, total: requests.length,
          stage: GalleryExportStage.processing, fileName: request.file.name,
        ));
        // Yield before CPU work even on web, where compute uses this isolate.
        await Future<void>.delayed(Duration.zero);
        if (token.isCancelled) break;
        final converted = await compute(
          _convertImage,
          _ImageWork(data.bytes, options, limits, data.frameCount > 1),
        );
        if (token.isCancelled) break;
        _assertCurrent(request);
        if (outputBytes + converted.bytes.length > limits.maxTotalOutputBytes) {
          throw const GalleryExportException(
            GalleryExportProblem.outputBudgetExceeded,
          );
        }
        final name = names.allocate(request.file.name, options.extension);
        outputs.add(_EncodedFile(name, converted.bytes));
        outputBytes += converted.bytes.length;
        items.add(GalleryExportItemResult(
          sourceName: request.file.name, outputName: name,
          width: converted.width, height: converted.height,
          firstFrameOnly: converted.firstFrameOnly,
        ));
      } catch (error) {
        items.add(_failure(request, error));
      }
    }

    const name = 'crispcloud-images.zip';
    const mime = 'application/zip';
    if (token.isCancelled || outputs.isEmpty) {
      return GalleryExportReport(suggestedName: name, mimeType: mime,
        items: items, cancelled: token.isCancelled);
    }
    // A connection or source revision may have changed after an early image.
    _assertAllCurrent(requests);
    onProgress?.call(GalleryExportProgress(
      completed: items.length, total: requests.length,
      stage: GalleryExportStage.finishing,
    ));
    final manifest = utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'application': 'CrispCloud',
      'format': options.format.name,
      'note': 'Independent copies. First frame/page only. '
          'EXIF, IPTC and XMP are not copied. JPEG transparency is white.',
      'files': items.map((item) => item.toJson()).toList(),
    }));
    outputs.add(_EncodedFile('crispcloud-export-report.json',
      Uint8List.fromList(manifest)));
    final zip = await compute(_encodeZip, _ZipWork(outputs, limits.maxArchiveBytes));
    _assertAllCurrent(requests);
    return GalleryExportReport(
      suggestedName: name, mimeType: mime, items: items,
      bytes: token.isCancelled ? null : zip, cancelled: token.isCancelled,
    );
  }

  Future<GalleryExportReport> contactSheet(
    List<GalleryMediaRequest> requests, {
    GalleryContactSheetOptions options = const GalleryContactSheetOptions(),
    GalleryExportCancellation? cancellation,
    void Function(GalleryExportProgress)? onProgress,
  }) async {
    _validateRequests(requests);
    _validateContactSheet(options, requests.length, limits);
    final token = cancellation ?? GalleryExportCancellation();
    final budget = _InputBudget(limits);
    final items = <GalleryExportItemResult>[];
    final tiles = <_SheetTile>[];
    var tileBytes = 0;

    for (final request in requests) {
      if (token.isCancelled) break;
      try {
        onProgress?.call(GalleryExportProgress(
          completed: items.length, total: requests.length,
          stage: GalleryExportStage.loading, fileName: request.file.name,
        ));
        if (token.isCancelled) break;
        final data = await _read(request, budget);
        if (token.isCancelled) break;
        onProgress?.call(GalleryExportProgress(
          completed: items.length, total: requests.length,
          stage: GalleryExportStage.processing, fileName: request.file.name,
        ));
        await Future<void>.delayed(Duration.zero);
        if (token.isCancelled) break;
        final converted = await compute(_contactTile, _ImageWork(
          data.bytes,
          GalleryConversionOptions(format: GalleryExportFormat.png,
            maxWidth: options.cellWidth, maxHeight: options.cellHeight),
          limits, data.frameCount > 1,
        ));
        if (token.isCancelled) break;
        _assertCurrent(request);
        if (tileBytes + converted.bytes.length > limits.maxTotalOutputBytes) {
          throw const GalleryExportException(
            GalleryExportProblem.outputBudgetExceeded,
          );
        }
        tiles.add(_SheetTile(request.file.name, converted));
        tileBytes += converted.bytes.length;
        items.add(GalleryExportItemResult(sourceName: request.file.name,
          width: converted.width, height: converted.height,
          firstFrameOnly: converted.firstFrameOnly));
      } catch (error) {
        items.add(_failure(request, error));
      }
    }

    const name = 'crispcloud-contact-sheet.png';
    const mime = 'image/png';
    if (token.isCancelled || tiles.isEmpty) {
      return GalleryExportReport(suggestedName: name, mimeType: mime,
        items: items, cancelled: token.isCancelled);
    }
    _assertAllCurrent(requests);
    onProgress?.call(GalleryExportProgress(completed: items.length,
      total: requests.length, stage: GalleryExportStage.finishing));
    final sheet = await compute(_assembleContactSheet,
      _SheetWork(tiles, options, limits));
    _assertAllCurrent(requests);
    return GalleryExportReport(suggestedName: name, mimeType: mime,
      items: items, bytes: token.isCancelled ? null : sheet,
      cancelled: token.isCancelled);
  }

  void _validateRequests(List<GalleryMediaRequest> requests) {
    if (requests.isEmpty) {
      throw const GalleryExportException(GalleryExportProblem.noImages);
    }
    if (requests.length > limits.maxFiles) {
      throw const GalleryExportException(GalleryExportProblem.tooManyFiles);
    }
  }

  Future<GalleryImageData> _read(
    GalleryMediaRequest request, _InputBudget budget,
  ) async {
    _assertCurrent(request);
    if (request.file.isFolder) {
      throw const GalleryExportException(GalleryExportProblem.unsupportedImage);
    }
    final size = request.file.size;
    if (size != null && size > limits.maxInputBytes) {
      throw const GalleryExportException(GalleryExportProblem.inputTooLarge);
    }
    if (budget.exhausted || (size != null &&
        budget.bytes + size > limits.maxTotalInputBytes)) {
      throw const GalleryExportException(GalleryExportProblem.inputBudgetExceeded);
    }
    final readLimit = math.min(limits.maxInputBytes,
      limits.maxTotalInputBytes - budget.bytes);
    if (readLimit < 1) {
      throw const GalleryExportException(GalleryExportProblem.inputBudgetExceeded);
    }
    var sourceBytes = 0;
    // Enforce the export's smaller limit at the storage reader, including
    // sources without a declared size and formats converted by the media layer.
    final boundedRequest = GalleryMediaRequest(
      file: request.file, namespaceId: request.namespaceId, path: request.path,
      isRemote: request.isRemote, isArchive: request.isArchive,
      isCurrent: () => request.isCurrent,
      revisionSalt: 'export:${request.revisionKey}:$readLimit',
      readBytes: (requestedLimit) async {
        final bytes = await request.readBytes(math.min(readLimit, requestedLimit));
        sourceBytes = bytes.length;
        if (sourceBytes > readLimit) {
          throw GalleryExportException(readLimit < limits.maxInputBytes
            ? GalleryExportProblem.inputBudgetExceeded
            : GalleryExportProblem.inputTooLarge);
        }
        return bytes;
      },
    );
    final GalleryImageData data;
    try {
      data = await _loadImage(boundedRequest);
    } catch (error) {
      // Failed decoding still consumed the returned source bytes.
      budget.addBytes(sourceBytes);
      _assertCurrent(request);
      if (error is GalleryExportException) rethrow;
      throw const GalleryExportException(GalleryExportProblem.readFailed);
    }
    _assertCurrent(request);
    budget.add(data, sourceBytes: sourceBytes);
    if (data.isSvg) {
      throw const GalleryExportException(GalleryExportProblem.unsupportedImage);
    }
    if (data.bytes.isEmpty) {
      throw const GalleryExportException(GalleryExportProblem.invalidImage);
    }
    if (data.bytes.length > limits.maxInputBytes) {
      throw const GalleryExportException(GalleryExportProblem.inputTooLarge);
    }
    _checkDimensions(data.width, data.height, limits.maxInputPixels,
      limits.maxDimension, GalleryExportProblem.inputDimensionsTooLarge);
    return data;
  }
}

void _assertCurrent(GalleryMediaRequest request) {
  if (!request.isCurrent) {
    throw const GalleryExportException(GalleryExportProblem.staleSource);
  }
}

void _assertAllCurrent(List<GalleryMediaRequest> requests) {
  for (final request in requests) {
    _assertCurrent(request);
  }
}

GalleryExportItemResult _failure(GalleryMediaRequest request, Object error) =>
    GalleryExportItemResult(sourceName: request.file.name,
      problem: error is GalleryExportException
          ? error.problem : GalleryExportProblem.invalidImage);

class _InputBudget {
  _InputBudget(this.limits);
  final GalleryExportLimits limits;
  int bytes = 0;
  int pixels = 0;
  bool exhausted = false;

  void addBytes(int amount) {
    bytes += amount;
    if (bytes > limits.maxTotalInputBytes) {
      exhausted = true;
      throw const GalleryExportException(GalleryExportProblem.inputBudgetExceeded);
    }
  }

  void add(GalleryImageData data, {int sourceBytes = 0}) {
    addBytes(sourceBytes > 0 ? sourceBytes : data.bytes.length);
    pixels += data.width * data.height;
    if (pixels > limits.maxTotalInputPixels) {
      exhausted = true;
      throw const GalleryExportException(GalleryExportProblem.inputBudgetExceeded);
    }
  }
}

void _validateConversion(GalleryConversionOptions options, GalleryExportLimits limits) {
  final dimensions = [options.maxWidth, options.maxHeight].whereType<int>();
  if (options.quality < 1 || options.quality > 100 ||
      options.quarterTurns < 0 || options.quarterTurns > 3 ||
      dimensions.any((value) => value < 1 || value > limits.maxDimension) ||
      [options.brightness, options.contrast, options.saturation].any(
        (value) => !value.isFinite || value < 0 || value > 2)) {
    throw const GalleryExportException(GalleryExportProblem.invalidOptions);
  }
}

void _validateContactSheet(GalleryContactSheetOptions options, int count,
    GalleryExportLimits limits) {
  if (options.columns < 1 || options.columns > 8 ||
      options.cellWidth < 120 || options.cellWidth > 640 ||
      options.cellHeight < 90 || options.cellHeight > 640) {
    throw const GalleryExportException(GalleryExportProblem.invalidOptions);
  }
  _checkDimensions(options.sheetWidth(count), options.sheetHeight(count),
    limits.maxOutputPixels, limits.maxDimension,
    GalleryExportProblem.outputTooLarge);
}

void _checkDimensions(int width, int height, int pixels, int dimension,
    GalleryExportProblem problem) {
  if (width < 1 || height < 1 || width > dimension || height > dimension ||
      width * height > pixels) {
    throw GalleryExportException(problem);
  }
}

class _ImageWork {
  const _ImageWork(this.bytes, this.options, this.limits, this.multipleFrames);
  final Uint8List bytes;
  final GalleryConversionOptions options;
  final GalleryExportLimits limits;
  final bool multipleFrames;
}

class _ConvertedImage {
  const _ConvertedImage(this.bytes, this.width, this.height, this.firstFrameOnly);
  final Uint8List bytes;
  final int width;
  final int height;
  final bool firstFrameOnly;
}

class _DecodedImage {
  const _DecodedImage(this.pixels, this.multipleFrames);
  final image.Image pixels;
  final bool multipleFrames;
}

_DecodedImage _decodeAndTransform(_ImageWork work) {
  if (work.bytes.length > work.limits.maxInputBytes) {
    throw const GalleryExportException(GalleryExportProblem.inputTooLarge);
  }
  final maxPixels = work.limits.maxInputPixels;
  // Explicit limits also protect decoders that allocate while parsing headers.
  final decoders = <image.Decoder>[
    image.JpegDecoder(maxPixels: maxPixels),
    image.PngDecoder(maxPixels: maxPixels),
    image.GifDecoder()..maxPixels = maxPixels,
    image.WebPDecoder()..maxPixels = maxPixels,
    image.BmpDecoder(maxPixels: maxPixels),
    image.TiffDecoder(maxPixels: maxPixels),
    image.PsdDecoder(maxPixels: maxPixels),
    image.IcoDecoder(maxPixels: maxPixels),
  ];
  image.Decoder? decoder;
  for (final candidate in decoders) {
    if (candidate.isValidFile(work.bytes)) {
      decoder = candidate;
      break;
    }
  }
  if (decoder == null) {
    throw const GalleryExportException(GalleryExportProblem.unsupportedImage);
  }
  final info = decoder.startDecode(work.bytes);
  if (info == null) {
    throw const GalleryExportException(GalleryExportProblem.invalidImage);
  }
  _checkDimensions(info.width, info.height, maxPixels,
    work.limits.maxDimension, GalleryExportProblem.inputDimensionsTooLarge);
  var pixels = decoder.decodeFrame(0);
  if (pixels == null) {
    throw const GalleryExportException(GalleryExportProblem.invalidImage);
  }
  _checkDimensions(pixels.width, pixels.height, maxPixels,
    work.limits.maxDimension, GalleryExportProblem.inputDimensionsTooLarge);

  // Preserve the canvas and offset of a partial first animation frame.
  var frameX = 0;
  var frameY = 0;
  if (info is image.GifInfo && info.frames.isNotEmpty) {
    frameX = info.frames.first.x;
    frameY = info.frames.first.y;
  } else if (info is image.WebPInfo && info.frames.isNotEmpty) {
    frameX = info.frames.first.x;
    frameY = info.frames.first.y;
  } else if (info is image.PngInfo && info.frames.isNotEmpty) {
    frameX = info.frames.first.xOffset;
    frameY = info.frames.first.yOffset;
  }
  if ((info is image.GifInfo || info is image.WebPInfo || info is image.PngInfo) &&
      (pixels.width != info.width || pixels.height != info.height ||
       frameX != 0 || frameY != 0)) {
    if (frameX < 0 || frameY < 0 || frameX + pixels.width > info.width ||
        frameY + pixels.height > info.height) {
      throw const GalleryExportException(GalleryExportProblem.invalidImage);
    }
    final canvas = image.Image(width: info.width, height: info.height,
      numChannels: 4, exif: pixels.exif, iccp: pixels.iccProfile);
    image.compositeImage(canvas, pixels, dstX: frameX, dstY: frameY);
    pixels = canvas;
  }
  if (pixels.exif.imageIfd.hasOrientation &&
      pixels.exif.imageIfd.orientation != 1) {
    pixels = image.bakeOrientation(pixels);
  }
  final options = work.options;
  if (options.quarterTurns != 0) {
    pixels = image.copyRotate(pixels, angle: options.quarterTurns * 90);
  }
  if (options.flipHorizontal) pixels = image.flipHorizontal(pixels);
  if (options.flipVertical) pixels = image.flipVertical(pixels);
  var scale = 1.0;
  if (options.maxWidth != null || options.maxHeight != null) {
    scale = math.min(options.maxWidth == null ? double.infinity :
      options.maxWidth! / pixels.width,
      options.maxHeight == null ? double.infinity :
      options.maxHeight! / pixels.height);
    if (!options.allowUpscale) scale = math.min(1.0, scale);
  }
  final width = math.max(1, (pixels.width * scale).round());
  final height = math.max(1, (pixels.height * scale).round());
  _checkDimensions(width, height, work.limits.maxOutputPixels,
    work.limits.maxDimension, GalleryExportProblem.outputTooLarge);
  if (pixels.width != width || pixels.height != height) {
    pixels = image.copyResize(pixels, width: width, height: height,
      interpolation: image.Interpolation.average);
  }
  // Normalize high-bit-depth/palette images to bounded 8-bit RGBA exports.
  if (pixels.format != image.Format.uint8 || pixels.hasPalette ||
      pixels.numChannels != 4) {
    pixels = pixels.convert(format: image.Format.uint8, numChannels: 4);
  }
  if (options.brightness != 1 || options.contrast != 1 ||
      options.saturation != 1) {
    pixels = image.adjustColor(pixels, brightness: options.brightness,
      contrast: options.contrast, saturation: options.saturation);
  }
  pixels.exif = image.ExifData();
  pixels.textData = null;
  return _DecodedImage(pixels, work.multipleFrames || info.numFrames > 1);
}

_ConvertedImage _convertImage(_ImageWork work) {
  final decoded = _decodeAndTransform(work);
  var pixels = decoded.pixels;
  if (work.options.format == GalleryExportFormat.jpeg) {
    final opaque = image.Image(width: pixels.width, height: pixels.height,
      numChannels: 3)..clear(image.ColorRgb8(255, 255, 255));
    image.compositeImage(opaque, pixels);
    // Retain a supported embedded profile; this is not an ICC conversion.
    opaque.iccProfile = pixels.iccProfile;
    pixels = opaque;
  }
  final bytes = work.options.format == GalleryExportFormat.jpeg
      ? image.encodeJpg(pixels, quality: work.options.quality)
      : image.encodePng(pixels);
  if (bytes.isEmpty || bytes.length > work.limits.maxOutputBytes) {
    throw const GalleryExportException(GalleryExportProblem.outputTooLarge);
  }
  return _ConvertedImage(bytes, pixels.width, pixels.height, decoded.multipleFrames);
}

_ConvertedImage _contactTile(_ImageWork work) {
  final decoded = _decodeAndTransform(work);
  final pixels = decoded.pixels;
  // Small RGBA tiles avoid retaining every source image or decoding it twice.
  return _ConvertedImage(pixels.getBytes(order: image.ChannelOrder.rgba),
    pixels.width, pixels.height, decoded.multipleFrames);
}

class _EncodedFile {
  const _EncodedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class _ZipWork {
  const _ZipWork(this.files, this.maxBytes);
  final List<_EncodedFile> files;
  final int maxBytes;
}

Uint8List _encodeZip(_ZipWork work) {
  final archive = Archive();
  for (final file in work.files) {
    archive.addFile(ArchiveFile.bytes(file.name, file.bytes)
      ..compression = CompressionType.none);
  }
  final bytes = ZipEncoder().encodeBytes(archive, level: 0);
  if (bytes.isEmpty || bytes.length > work.maxBytes) {
    throw const GalleryExportException(GalleryExportProblem.outputBudgetExceeded);
  }
  return bytes;
}

class _SheetTile {
  const _SheetTile(this.caption, this.imageData);
  final String caption;
  final _ConvertedImage imageData;
}

class _SheetWork {
  const _SheetWork(this.tiles, this.options, this.limits);
  final List<_SheetTile> tiles;
  final GalleryContactSheetOptions options;
  final GalleryExportLimits limits;
}

Uint8List _assembleContactSheet(_SheetWork work) {
  _validateContactSheet(work.options, work.tiles.length, work.limits);
  final options = work.options;
  final sheet = image.Image(width: options.sheetWidth(work.tiles.length),
    height: options.sheetHeight(work.tiles.length), numChannels: 3)
    ..clear(image.ColorRgb8(248, 249, 251));
  const padding = GalleryContactSheetOptions.padding;
  for (var index = 0; index < work.tiles.length; index++) {
    final tile = work.tiles[index];
    final x = padding + (index % options.columns) * (options.cellWidth + padding);
    final y = padding + (index ~/ options.columns) * options.rowHeight;
    image.fillRect(sheet, x1: x, y1: y,
      x2: x + options.cellWidth - 1, y2: y + options.cellHeight - 1,
      color: image.ColorRgb8(233, 236, 240));
    final data = tile.imageData;
    final pixels = image.Image.fromBytes(width: data.width, height: data.height,
      bytes: data.bytes.buffer, bytesOffset: data.bytes.offsetInBytes,
      numChannels: 4);
    image.compositeImage(sheet, pixels,
      dstX: x + (options.cellWidth - data.width) ~/ 2,
      dstY: y + (options.cellHeight - data.height) ~/ 2);
    if (options.captions) {
      image.drawString(sheet, _fitCaption(tile.caption, options.cellWidth),
        font: image.arial14, x: x, y: y + options.cellHeight + 6,
        color: image.ColorRgb8(32, 40, 52));
    }
  }
  final bytes = image.encodePng(sheet);
  if (bytes.isEmpty || bytes.length > work.limits.maxOutputBytes) {
    throw const GalleryExportException(GalleryExportProblem.outputTooLarge);
  }
  return bytes;
}

String _fitCaption(String text, int width) {
  final font = image.arial14;
  final codePoints = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').runes
      .map((rune) => font.characters.containsKey(rune) ? rune : 63).toList();
  var used = 0;
  final result = <int>[];
  for (final rune in codePoints) {
    final advance = font.characters[rune]?.xAdvance ?? 8;
    if (used + advance > width - 15) {
      return '${String.fromCharCodes(result)}...';
    }
    result.add(rune);
    used += advance;
  }
  return String.fromCharCodes(result);
}

class _ExportNames {
  final _used = <String>{};

  String allocate(String source, String extension) {
    var base = source.replaceAll('\\', '/').split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    base = String.fromCharCodes(base.runes.take(100));
    if (base.isEmpty) base = 'image';
    if (RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false)
        .hasMatch(base)) {
      base = 'image_$base';
    }
    var candidate = '$base.$extension';
    var suffix = 2;
    while (!_used.add(candidate.toLowerCase())) {
      candidate = '$base (${suffix++}).$extension';
    }
    return candidate;
  }
}
