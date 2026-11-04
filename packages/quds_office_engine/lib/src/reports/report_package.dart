/// `.qrep` package: a ZIP holding the layout XML and embedded images.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../builders/image_fit.dart';
import '../opc/zip/zip_reader.dart';
import '../opc/zip/zip_writer.dart';
import 'report_data.dart';
import 'report_font_file.dart';
import 'report_fonts.dart';
import 'report_template_manifest.dart';

/// Thrown when `.qrep` bytes are neither a valid package nor plain XML.
class ReportPackageException implements Exception {
  /// ReportPackageException API.
  const ReportPackageException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ReportPackageException: $message';
}

/// Image format accepted inside a `.qrep` package.
enum ReportImageFormat {
  /// PNG (`images/<name>.png`).
  png('png'),

  /// JPEG (`images/<name>.jpg`).
  jpeg('jpg');

  const ReportImageFormat(this.extension);

  /// File extension used inside the package.
  final String extension;

  /// Sniffs PNG / JPEG from the leading bytes; null for anything else.
  static ReportImageFormat? sniff(Uint8List bytes) {
    if (ImageFit.readPngSize(bytes) != null) {
      return ReportImageFormat.png;
    }
    if (ImageFit.readJpegSize(bytes) != null) {
      return ReportImageFormat.jpeg;
    }
    return null;
  }
}

/// A `.qrep` report file: [xml] layout plus pre-saved [images] and [fonts].
///
/// On disk it is a ZIP archive:
///
/// ```text
/// mimetype                application/vnd.quds.qrep+zip (stored, first entry)
/// layout.xml              the <Report> template
/// images/logo.png         embedded image, referenced as <Image source="logo"/>
/// images/stamp.jpg
/// fonts/Cairo/regular.ttf embedded TrueType faces, used as fontFamily="Cairo"
/// fonts/Cairo/bold.ttf
/// shapes/districts.qmap   embedded region outlines for a shape map
/// data/sample.json        design-time data shown by the designer (optional)
/// template.json           catalog details when the file is a template
/// ```
///
/// Image keys are the file stems under `images/`; an `<Image>` element whose
/// `source` evaluates to a key draws that image. Font folders are family
/// names, so a report exported on another machine draws with the faces it
/// was designed with. [ReportPackage.decode] also accepts legacy plain-XML
/// `.qrep` files (no images or fonts).
class ReportPackage {
  /// ReportPackage API.
  ReportPackage({
    required this.xml,
    Map<String, Uint8List>? images,
    Map<String, ReportFontFiles>? fonts,
    Map<String, Uint8List>? shapes,
    this.sampleData,
    this.template,
    Map<String, String>? subreports,
  }) : images = images ?? <String, Uint8List>{},
       fonts = fonts ?? <String, ReportFontFiles>{},
       shapes = shapes ?? <String, Uint8List>{},
       subreports = subreports ?? <String, String>{};

  /// Parses `.qrep` bytes: a package ZIP or a legacy plain-XML template.
  ///
  /// Throws [ReportPackageException] when the ZIP is damaged, lacks
  /// [layoutEntry], or holds an image that is not PNG / JPEG.
  factory ReportPackage.decode(Uint8List bytes) {
    if (!isPackage(bytes)) {
      try {
        return ReportPackage(xml: _text(bytes));
      } on FormatException {
        throw const ReportPackageException('Not a .qrep package or UTF-8 XML');
      }
    }
    final ZipReader zip;
    try {
      zip = ZipReader.fromBytes(bytes);
    } on Exception catch (e) {
      throw ReportPackageException('Damaged .qrep archive: $e');
    }
    if (!zip.contains(layoutEntry)) {
      throw const ReportPackageException('Missing $layoutEntry');
    }
    final Map<String, Uint8List> images = <String, Uint8List>{};
    final Map<String, Uint8List> shapes = <String, Uint8List>{};
    final Map<String, String> subreports = <String, String>{};
    Map<String, Object?>? sample;
    ReportTemplateManifest? template;
    final Map<String, _FontSlots> faces = <String, _FontSlots>{};
    for (final ZipEntry entry in zip.entries) {
      if (entry.isDirectory) {
        continue;
      }
      if (entry.uncompressedSize > maxEntryBytes) {
        throw ReportPackageException(
          '${entry.fileName} exceeds ${maxEntryBytes ~/ (1024 * 1024)} MB',
        );
      }
      final (String, _FontSlot)? face = _fontFace(entry.fileName);
      if (face != null) {
        final (String family, _FontSlot slot) = face;
        final Uint8List data = _read(zip, entry.fileName);
        try {
          ReportFontFile.inspect(data);
        } on ReportFontException catch (e) {
          throw ReportPackageException('${entry.fileName}: ${e.message}');
        }
        final _FontSlots slots = faces.putIfAbsent(family, _FontSlots.new);
        switch (slot) {
          case _FontSlot.regular:
            slots.regular = data;
          case _FontSlot.bold:
            slots.bold = data;
          case _FontSlot.italic:
            slots.italic = data;
          case _FontSlot.boldItalic:
            slots.boldItalic = data;
        }
        continue;
      }
      if (entry.fileName == sampleDataEntry) {
        try {
          sample = ReportData.fromJson(
            _text(_read(zip, sampleDataEntry)),
          ).values;
        } on FormatException {
          throw const ReportPackageException('$sampleDataEntry is not UTF-8');
        } on ReportDataException catch (e) {
          throw ReportPackageException('$sampleDataEntry: ${e.message}');
        }
        continue;
      }
      if (entry.fileName == ReportTemplateManifest.entry) {
        try {
          template = ReportTemplateManifest.decode(
            _text(_read(zip, ReportTemplateManifest.entry)),
          );
        } on FormatException catch (e) {
          throw ReportPackageException(
            '${ReportTemplateManifest.entry}: ${e.message}',
          );
        }
        continue;
      }
      final String? shapeKey = _shapeKey(entry.fileName);
      if (shapeKey != null) {
        final Uint8List data = _read(zip, entry.fileName);
        if (data.length < 4 ||
            data[0] != 0x51 ||
            data[1] != 0x4D ||
            data[2] != 0x41 ||
            data[3] != 0x50) {
          throw ReportPackageException('${entry.fileName} is not a shape layer');
        }
        shapes[shapeKey] = data;
        continue;
      }
      final String? sub = _subreportKey(entry.fileName);
      if (sub != null) {
        try {
          subreports[sub] = _text(_read(zip, entry.fileName));
        } on FormatException {
          throw ReportPackageException('${entry.fileName} is not UTF-8');
        }
        continue;
      }
      final String? key = _imageKey(entry.fileName);
      if (key == null) {
        continue;
      }
      final Uint8List data = _read(zip, entry.fileName);
      if (ReportImageFormat.sniff(data) == null) {
        throw ReportPackageException('${entry.fileName} is not PNG or JPEG');
      }
      images[key] = data;
    }
    final String xml;
    try {
      xml = _text(_read(zip, layoutEntry));
    } on FormatException {
      throw const ReportPackageException('$layoutEntry is not UTF-8');
    }
    return ReportPackage(
      xml: xml,
      images: images,
      shapes: shapes,
      fonts: <String, ReportFontFiles>{
        for (final MapEntry<String, _FontSlots> f in faces.entries)
          f.key: ReportFontFiles(
            regular: f.value.regular,
            bold: f.value.bold,
            italic: f.value.italic,
            boldItalic: f.value.boldItalic,
          ),
      },
      sampleData: sample,
      template: template,
      subreports: subreports,
    );
  }

  /// Layout entry name.
  static const String layoutEntry = 'layout.xml';

  /// Folder holding embedded images.
  static const String imagesFolder = 'images/';

  /// Folder holding embedded shape layers (`shapes/<name>.qmap`).
  static const String shapesFolder = 'shapes/';

  /// Folder holding embedded fonts
  /// (`fonts/<family>/regular.ttf|bold.ttf|italic.ttf|boldItalic.ttf`).
  static const String fontsFolder = 'fonts/';

  /// Design-time data entry (JSON object).
  static const String sampleDataEntry = 'data/sample.json';

  /// Child report templates (`subreports/<name>.xml`).
  static const String subreportsFolder = 'subreports/';

  /// Content of the leading `mimetype` entry.
  static const String mimeType = 'application/vnd.quds.qrep+zip';

  /// Largest entry accepted by [ReportPackage.decode] (64 MB).
  static const int maxEntryBytes = 64 * 1024 * 1024;

  /// Report template XML (`<Report>`).
  final String xml;

  /// Embedded images by key (`<Image source="key"/>`).
  final Map<String, Uint8List> images;

  /// Embedded shape layers by name (`shape="name"` on a shape map).
  final Map<String, Uint8List> shapes;

  /// Child templates by name (`subreports/<name>.xml`).
  final Map<String, String> subreports;

  /// Embedded TrueType families by name (`fontFamily="Cairo"`).
  final Map<String, ReportFontFiles> fonts;

  /// Data the designer previews the report with (`data/sample.json`); null
  /// when the report has none. Hosts feed real data at export time.
  final Map<String, Object?>? sampleData;

  /// Catalog details ([ReportTemplateManifest.entry]) when this file is a
  /// template; null for an ordinary report.
  final ReportTemplateManifest? template;

  /// Whether [bytes] start with a ZIP local-file header.
  static bool isPackage(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  static final RegExp _keyPattern = RegExp(
    r'^[A-Za-z0-9_\-\u0600-\u06FF]{1,64}$',
  );

  /// Whether [family] can name an embedded font folder: 1–64 characters,
  /// no slashes or control characters, no surrounding spaces.
  static bool isValidFontFamily(String family) =>
      family.isNotEmpty &&
      family.length <= 64 &&
      family.trim() == family &&
      !family.contains(RegExp(r'[/\\\x00-\x1F\x7F]'));

  /// A registry with [base]'s families first (they win on name clashes),
  /// then [fonts]; [base] itself is not modified.
  ReportFontRegistry fontRegistry({ReportFontRegistry? base}) =>
      mergeFonts(base, fonts);

  /// [base]'s families followed by the [embedded] ones it lacks, in a new
  /// registry; the default family stays [base]'s.
  static ReportFontRegistry mergeFonts(
    ReportFontRegistry? base,
    Map<String, ReportFontFiles> embedded,
  ) {
    final ReportFontRegistry out = ReportFontRegistry();
    if (base != null) {
      for (final ReportFontFamily f in base.families) {
        out.register(
          f.name,
          regular: f.regular,
          bold: f.bold,
          italic: f.italic,
          boldItalic: f.boldItalic,
        );
      }
      out.defaultFamily = base.defaultFamily ?? out.defaultFamily;
    }
    for (final MapEntry<String, ReportFontFiles> f in embedded.entries) {
      if (!out.has(f.key)) {
        f.value.registerIn(out, f.key);
      }
    }
    return out;
  }

  /// Whether [key] can name an embedded image (letters, digits, `_`, `-`,
  /// Arabic letters; 1–64 characters).
  static bool isValidKey(String key) => _keyPattern.hasMatch(key);

  /// Turns a file name such as `Company Logo.PNG` into a valid key
  /// (`Company_Logo`), avoiding [taken] keys by appending `2`, `3`, ….
  static String keyFor(String fileName, {Iterable<String> taken = const []}) {
    var stem = fileName.split(RegExp(r'[\\/]')).last;
    final int dot = stem.lastIndexOf('.');
    if (dot > 0) {
      stem = stem.substring(0, dot);
    }
    stem = stem
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-\u0600-\u06FF]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (stem.isEmpty) {
      stem = 'image';
    }
    if (stem.length > 60) {
      stem = stem.substring(0, 60);
    }
    final Set<String> used = <String>{
      for (final String t in taken) t.toLowerCase(),
    };
    var key = stem;
    var n = 1;
    while (used.contains(key.toLowerCase())) {
      n++;
      key = '$stem$n';
    }
    return key;
  }

  /// ZIP bytes of this package.
  ///
  /// Throws [ReportPackageException] for an invalid key or an image that is
  /// not PNG / JPEG.
  Uint8List encode() {
    final ZipWriter zip = ZipWriter()
      ..addFile('mimetype', ascii.encode(mimeType), store: true)
      ..addFile(layoutEntry, utf8.encode(xml));
    final List<String> keys = images.keys.toList()..sort();
    for (final String key in keys) {
      if (!isValidKey(key)) {
        throw ReportPackageException('Invalid image name "$key"');
      }
      final Uint8List data = images[key]!;
      final ReportImageFormat? format = ReportImageFormat.sniff(data);
      if (format == null) {
        throw ReportPackageException('Image "$key" is not PNG or JPEG');
      }
      zip.addFile('$imagesFolder$key.${format.extension}', data, store: true);
    }
    final List<String> subNames = subreports.keys.toList()..sort();
    for (final String key in subNames) {
      if (!isValidKey(key)) {
        throw ReportPackageException('Invalid subreport name "$key"');
      }
      zip.addFile('$subreportsFolder$key.xml', utf8.encode(subreports[key]!));
    }
    final List<String> shapeNames = shapes.keys.toList()..sort();
    for (final String key in shapeNames) {
      if (!isValidKey(key)) {
        throw ReportPackageException('Invalid shape name "$key"');
      }
      zip.addFile('$shapesFolder$key.qmap', shapes[key]!);
    }
    final List<String> families = fonts.keys.toList()..sort();
    for (final String family in families) {
      if (!isValidFontFamily(family)) {
        throw ReportPackageException('Invalid font family "$family"');
      }
      final ReportFontFiles files = fonts[family]!;
      for (final (String face, Uint8List? data) in <(String, Uint8List?)>[
        ('regular', files.regular),
        ('bold', files.bold),
        ('italic', files.italic),
        ('boldItalic', files.boldItalic),
      ]) {
        if (data == null) {
          continue;
        }
        try {
          ReportFontFile.inspect(data);
        } on ReportFontException catch (e) {
          throw ReportPackageException('Font "$family" ($face): ${e.message}');
        }
        zip.addFile('$fontsFolder$family/$face.ttf', data);
      }
    }
    final Map<String, Object?>? sample = sampleData;
    if (sample != null) {
      zip.addFile(
        sampleDataEntry,
        utf8.encode(ReportData.encodeJson(sample, pretty: true)),
      );
    }
    final ReportTemplateManifest? manifest = template;
    if (manifest != null) {
      zip.addFile(ReportTemplateManifest.entry, utf8.encode(manifest.encode()));
    }
    return zip.close();
  }

  static (String, _FontSlot)? _fontFace(String fileName) {
    if (!fileName.startsWith(fontsFolder)) {
      return null;
    }
    final List<String> parts = fileName
        .substring(fontsFolder.length)
        .split('/');
    if (parts.length != 2 || !isValidFontFamily(parts[0])) {
      return null;
    }
    return switch (parts[1].toLowerCase()) {
      'regular.ttf' => (parts[0], _FontSlot.regular),
      'bold.ttf' => (parts[0], _FontSlot.bold),
      'italic.ttf' => (parts[0], _FontSlot.italic),
      'bolditalic.ttf' => (parts[0], _FontSlot.boldItalic),
      _ => null,
    };
  }

  static String? _shapeKey(String fileName) {
    if (!fileName.startsWith(shapesFolder) || !fileName.endsWith('.qmap')) {
      return null;
    }
    final String key = fileName.substring(
      shapesFolder.length,
      fileName.length - 5,
    );
    if (key.isEmpty || key.contains('/')) {
      return null;
    }
    return isValidKey(key) ? key : null;
  }

  static String? _subreportKey(String fileName) {
    if (!fileName.startsWith(subreportsFolder) || !fileName.endsWith('.xml')) {
      return null;
    }
    final String key = fileName.substring(
      subreportsFolder.length,
      fileName.length - 4,
    );
    if (key.isEmpty || key.contains('/')) {
      return null;
    }
    return isValidKey(key) ? key : null;
  }

  static String? _imageKey(String fileName) {
    if (!fileName.startsWith(imagesFolder)) {
      return null;
    }
    final String name = fileName.substring(imagesFolder.length);
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || name.contains('/')) {
      return null;
    }
    final String key = name.substring(0, dot);
    return isValidKey(key) ? key : null;
  }

  static Uint8List _read(ZipReader zip, String name) {
    try {
      return zip.read(name);
    } on Exception catch (e) {
      throw ReportPackageException('Cannot read $name: $e');
    }
  }

  static String _text(Uint8List bytes) {
    final bool bom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    return utf8.decode(bom ? Uint8List.sublistView(bytes, 3) : bytes);
  }
}

enum _FontSlot { regular, bold, italic, boldItalic }

class _FontSlots {
  Uint8List? regular;
  Uint8List? bold;
  Uint8List? italic;
  Uint8List? boldItalic;
}
