// lib/services/internal_viewer_service.dart
//
// Internal file viewer service for the dual-panel orthodox file manager.
// Supports F3 quick-preview in text, safe-ascii, binary, hex, image, markdown,
// pdf, media, font, csv, office and archive modes.

import 'dart:convert';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// ViewerMode enum
// ---------------------------------------------------------------------------

/// Discriminated mode determining how the viewer renders a file.
enum ViewerMode {
  /// Plain text — UTF-8 / UTF-16 / Latin-1 encoded.
  text,

  /// Safe ASCII view — bytes rendered with control chars replaced by '·'
  /// but Latin-1 high bytes still readable (DC "ASCII" lister mode).
  ascii,

  /// Pure byte view — only 0x20–0x7E shown literally, everything else '.'.
  /// This is the DC "Binary" lister mode; also the default for unknown
  /// or non-decodable binary files.
  binary,

  /// Raw hex dump — 16 bytes per row with offset + hex + ASCII columns.
  hex,

  /// Raster or vector image (.png, .jpg, .gif, .webp, .bmp, .svg).
  image,

  /// Markdown document (.md, .markdown).
  markdown,

  /// HTML document — rendered view or source.
  html,

  /// Well-formed XML — collapsible tree or source.
  xml,

  /// PDF document.
  pdf,

  /// Audio or video file (rendered with a media player).
  media,

  /// Font file (.ttf/.otf/.woff) — sample text at various sizes.
  font,

  /// .csv / .tsv — parsed into a scrollable table.
  csv,

  /// Office document (DOCX/XLSX/PPTX/ODT/ODS/ODP/EPUB) — extracted text.
  office,

  /// Saved email (.eml/.msg), with decoded headers, body and attachments.
  email,

  /// Archive container (.zip/.tar/.gz) — member listing.
  archive,

  /// File type is recognised but cannot be previewed (e.g. encrypted archive).
  unsupported,
}

// ---------------------------------------------------------------------------
// HexLine model
// ---------------------------------------------------------------------------

/// A single row in a hex dump.
class HexLine {
  /// Byte offset of the first byte on this row.
  final int offset;

  /// Each hex byte as a two-character upper-case string, e.g. ['48', '65', …].
  final List<String> hexParts;

  /// Printable ASCII representation; non-printable bytes rendered as '.'.
  final String asciiPart;

  const HexLine({
    required this.offset,
    required this.hexParts,
    required this.asciiPart,
  });

  @override
  String toString() {
    final offsetStr = offset.toRadixString(16).toUpperCase().padLeft(8, '0');
    final hexStr = hexParts.join(' ').padRight(47); // 16 bytes * 3 - 1 = 47
    return '$offsetStr  $hexStr  $asciiPart';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HexLine &&
          other.offset == offset &&
          other.asciiPart == asciiPart;

  @override
  int get hashCode => Object.hash(offset, asciiPart);
}

// ---------------------------------------------------------------------------
// ViewerContent model
// ---------------------------------------------------------------------------

/// The result of loading a file for viewing.
class ViewerContent {
  /// Raw file bytes.
  final Uint8List data;

  /// How the UI should render the content.
  final ViewerMode mode;

  /// Base filename (no directory component).
  final String filename;

  /// Total size of the file in bytes.
  final int sizeBytes;

  /// Character encoding detected for text modes; null for binary/image/pdf.
  final String? encoding;

  /// Number of newline-terminated lines (text/markdown only); null otherwise.
  final int? lineCount;

  /// MIME type inferred from extension + magic bytes.
  final String? mimeType;

  const ViewerContent({
    required this.data,
    required this.mode,
    required this.filename,
    required this.sizeBytes,
    this.encoding,
    this.lineCount,
    this.mimeType,
  });

  /// Serialise non-binary fields for logging / caching.
  Map<String, dynamic> toJson() => {
        'filename': filename,
        'mode': mode.name,
        'sizeBytes': sizeBytes,
        if (encoding != null) 'encoding': encoding,
        if (lineCount != null) 'lineCount': lineCount,
        if (mimeType != null) 'mimeType': mimeType,
      };

  @override
  String toString() =>
      'ViewerContent(filename=$filename, mode=${mode.name}, '
      'size=$sizeBytes, encoding=$encoding, lines=$lineCount)';
}

// ---------------------------------------------------------------------------
// InternalViewerService
// ---------------------------------------------------------------------------

/// Maximum in-memory size for `loadContent` (50 MB). The F3 viewer streams
/// larger files from disk via a windowed reader, so this only guards the
/// convenience API and remote (memory-limited) paths.
const _kMaxViewSizeBytes = 50 * 1024 * 1024;

class InternalViewerService {
  const InternalViewerService();

  // ---- Extension → mode mapping --------------------------------------------

  /// Returns a map from [ViewerMode] to the list of file extensions handled by
  /// that mode (lower-case, including the leading dot).
  Map<ViewerMode, List<String>> getSupportedExtensions() => const {
        ViewerMode.text: [
          '.txt',
          '.text',
          '.log',
          '.log2',
          '.json',
          '.json5',
          '.jsonl',
          '.ndjson',
          '.vim',
          '.sty',
          '.cls',
          '.properties',
          '.cfg',
          '.conf',
          '.ini',
          '.env',
          '.yaml',
          '.yml',
          '.toml',
          '.gradle',
          '.groovy',
          '.cmake',
          '.mk',
          '.make',
          '.bazel',
          '.ninja',
          '.edn',
          '.gitconfig',
          '.gitignore',
          '.gitattributes',
          '.gitmodules',
          '.editorconfig',
          // ---- Programming languages ----
          '.dart',
          '.py',
          '.pyw',
          '.pyi',
          '.js',
          '.mjs',
          '.cjs',
          '.ts',
          '.mts',
          '.cts',
          '.jsx',
          '.tsx',
          '.java',
          '.kt',
          '.kts',
          '.swift',
          '.c',
          '.cpp',
          '.cc',
          '.cxx',
          '.h',
          '.hpp',
          '.hh',
          '.hxx',
          '.cs',
          '.go',
          '.rs',
          '.rb',
          '.php',
          '.lua',
          '.sh',
          '.bash',
          '.zsh',
          '.fish',
          '.ksh',
          '.bat',
          '.cmd',
          '.ps1',
          '.psm1',
          '.sql',
          '.r',
          '.m',
          '.mm',
          '.tex',
          '.diff',
          '.patch',
          '.asm',
          '.s',
          '.nasm',
          '.coffee',
          '.pl',
          '.pm',
          '.ex',
          '.exs',
          '.erl',
          '.hrl',
          '.hs',
          '.elm',
          '.fs',
          '.fsi',
          '.fsx',
          '.gd',
          '.ipynb',
          '.jl',
          '.nim',
          '.pas',
          '.purs',
          '.smali',
          '.twig',
          '.vue',
          '.svelte',
          '.sol',
          '.pug',
          '.jade',
          '.sass',
          '.less',
          '.scss',
          '.css',
          '.astro',
          '.hcl',
          '.tf',
          '.tfvars',
          '.rego',
          '.srt',
          '.vtt',
          '.sub',
        ],
        ViewerMode.html: [
          '.html',
          '.htm',
          '.xhtml',
        ],
        ViewerMode.xml: [
          '.xml',
          '.xsl',
          '.xslt',
          '.plist',
          '.xaml',
          '.ui',
          '.resx',
          '.rss',
          '.atom',
          '.csproj',
          '.vcxproj',
          '.props',
          '.targets',
          '.kbdx',
        ],
        ViewerMode.image: [
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.webp',
          '.bmp',
          '.svg',
          '.svgz',
          '.ico',
          '.tiff',
          '.tif',
          '.avif',
          '.heic',
          '.heif',
          '.psd',
          '.xcf',
        ],
        ViewerMode.markdown: [
          '.md',
          '.markdown',
          '.mdown',
          '.mkd',
          '.mkdn',
          '.mdx',
        ],
        ViewerMode.pdf: [
          '.pdf',
        ],
        ViewerMode.media: [
          '.mp4',
          '.m4v',
          '.mov',
          '.avi',
          '.mkv',
          '.webm',
          '.wmv',
          '.flv',
          '.ogv',
          '.3gp',
          '.mpg',
          '.mpeg',
          '.mp3',
          '.wav',
          '.flac',
          '.aac',
          '.ogg',
          '.oga',
          '.opus',
          '.m4a',
          '.wma',
          '.aiff',
          '.aif',
          '.mid',
          '.midi',
          '.gsm',
          '.amr',
          '.au',
        ],
        ViewerMode.font: [
          '.ttf',
          '.otf',
          '.woff',
          '.woff2',
          '.pfb',
        ],
        ViewerMode.csv: [
          '.csv',
          '.tsv',
        ],
        ViewerMode.office: [
          '.ppt',
          '.pps',
          '.doc',
          '.dot',
          '.docx',
          '.docm',
          '.dotx',
          '.dotm',
          '.xlsx',
          '.xlsm',
          '.xltx',
          '.pptx',
          '.pptm',
          '.potx',
          '.odt',
          '.ods',
          '.odp',
          '.epub',
        ],
        ViewerMode.email: ['.eml', '.msg'],
        ViewerMode.archive: [
          '.zip',
          '.jar',
          '.whl',
          '.apk',
          '.ipa',
          '.aab',
          '.crx',
          '.xpi',
          '.nupkg',
          '.vsix',
          '.cbz',
          '.cbt',
          '.cb7',
          '.cbr',
          '.7z',
          '.rar',
          '.tar',
          '.tgz',
          '.tbz2',
          '.tbz',
          '.txz',
          '.tzst',
          '.gz',
          '.bz2',
          '.xz',
          '.zst',
        ],
        ViewerMode.binary: [
          '.exe',
          '.dll',
          '.so',
          '.dylib',
          '.bin',
          '.dat',
          '.db',
          '.sqlite',
          '.sqlite3',
          '.o',
          '.obj',
          '.class',
          '.pyc',
          '.deb',
          '.rpm',
          '.dmg',
          '.iso',
          '.img',
          '.vhd',
          '.vhdx',
          '.wasm',
          '.z',
          '.cab',
          '.pak',
          '.pack',
          '.cache',
          '.swp',
          '.core',
          '.a',
          '.lib',
        ],
      };

  // ---- Mode detection -------------------------------------------------------

  /// Detect the best [ViewerMode] for [filename].
  ///
  /// If [header] is supplied (first ~16 bytes of the file) it is also checked
  /// for known magic byte signatures, which override extension-based guessing.
  /// Unknown extensions sniff the content: decodable data returns text mode,
  /// everything else lands in the DC-style binary (safe byte) view.
  ViewerMode detectMode(String filename, {Uint8List? header}) {
    final lower = filename.toLowerCase();

    // Multi-segment suffixes first (.tar.gz, .tar.bz2) so that archive
    // suffixes match before the plain '.gz' entry.
    for (final suffix in _archiveSuffixes) {
      if (lower.endsWith(suffix)) return ViewerMode.archive;
    }

    if (header != null && header.isNotEmpty) {
      final magic = _detectMagic(header);
      if (magic != null) return magic;
    }

    final mode = _modeForName(lower, header);
    // Content sniffing for extension-less / generic markup files. The magic
    // check above runs first; here we only refine text/binary guesses so
    // e.g. .svg keeps its image mapping.
    if (header != null &&
        header.isNotEmpty &&
        (mode == ViewerMode.text || mode == ViewerMode.binary)) {
      final snippet = latin1
          .decode(header.length > 512 ? header.sublist(0, 512) : header)
          .replaceFirst('\uFEFF', '')
          .trimLeft()
          .toLowerCase();
      if (snippet.startsWith('<?xml')) return ViewerMode.xml;
      if (snippet.startsWith('<!doctype html') ||
          snippet.startsWith('<html')) {
        return ViewerMode.html;
      }
    }
    return mode;
  }

  static const _archiveSuffixes = <String>[
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.zst',
    '.tgz',
    '.tbz2',
    '.tbz',
    '.txz',
    '.tzst',
  ];

  /// Extension names commonly plain text even without a real extension
  /// (README, LICENSE, Makefile, …). Matched against the lower-case basename.
  static const _knownTextBasenameSuffixes = <String>[
    'readme',
    'license',
    'licence',
    'changelog',
    'authors',
    'contributors',
    'notice',
    'todo',
    'makefile',
    'dockerfile',
    'meson.build',
    'pipfile',
    'vagrantfile',
    'gemfile',
    'rakefile',
    'guardfile',
    'jenkinsfile',
    'cmakelists.txt',
    'bashrc',
    'zshrc',
    'profile',
    'bash_profile',
    'inputrc',
  ];

  ViewerMode _modeForName(String lowerFullname, Uint8List? header) {
    final map = getSupportedExtensions();

    final slash = lowerFullname.lastIndexOf('/');
    final backslash = lowerFullname.lastIndexOf('\\');
    final start = (slash > backslash ? slash : backslash) + 1;
    final basename = lowerFullname.substring(start);
    final ext = _extensionOf(lowerFullname);

    for (final entry in map.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }

    // Extension-less well-known text files: Makefile, LICENSE, Dockerfile…
    for (final suffix in _knownTextBasenameSuffixes) {
      if (basename == suffix ||
          (basename.length > suffix.length &&
              basename.endsWith(suffix) &&
              basename[basename.length - suffix.length - 1] == '.')) {
        return ViewerMode.text;
      }
    }

    // Unknown: sniff bytes when available. A short header is a stronger
    // predictor than the extension, so run it only with a header present.
    if (header != null && looksLikeText(header)) return ViewerMode.text;
    return ViewerMode.binary;
  }

  /// Heuristic: should this data be displayed as plain text?
  ///
  /// Data is considered text when it contains no NUL bytes, its control
  /// character ratio is tiny (<2%) and at most half the bytes are high bytes
  /// (UTF-8 prose vs. compressed/encrypted streams). BOMs are strong signals.
  static bool looksLikeText(Uint8List header) {
    if (header.isEmpty) return true;

    // UTF-8 BOM.
    if (header.length >= 3 &&
        header[0] == 0xEF &&
        header[1] == 0xBB &&
        header[2] == 0xBF) {
      return true;
    }
    // UTF-16 BOMs.
    if (header.length >= 2 &&
        ((header[0] == 0xFF && header[1] == 0xFE) ||
            (header[0] == 0xFE && header[1] == 0xFF))) {
      return true;
    }

    // Skip a UTF-8 BOM for the statistics if present.
    int start = 0;
    if (header.length >= 3 && header[0] == 0xEF && header[1] == 0xBB && header[2] == 0xBF) {
      start = 3;
    }

    var controls = 0;
    var highBytes = 0;
    for (var i = start; i < header.length; i++) {
      final b = header[i];
      if (b == 0) return false; // NUL byte → almost never text
      if (b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) controls++;
      if (b >= 0x80) highBytes++;
    }
    final n = header.length - start;
    if (n == 0) return true;
    if (controls / n > 0.02) return false;
    return highBytes / n < 0.5;
  }

  // ---- Load content ---------------------------------------------------------

  /// Build a [ViewerContent] from raw [data] bytes and a [filename].
  ///
  /// Throws a [StateError] when [data] exceeds the 50 MB limit.
  ViewerContent loadContent(Uint8List data, String filename) {
    if (data.length > _kMaxViewSizeBytes) {
      throw StateError(
        'File "$filename" is too large to view '
        '(${data.length} bytes > $_kMaxViewSizeBytes bytes limit).',
      );
    }

    final header =
        data.length >= 16 ? Uint8List.sublistView(data, 0, 16) : data;
    final mode = detectMode(filename, header: header);

    String? encoding;
    int? lineCount;
    String? mimeType;

    switch (mode) {
      case ViewerMode.text:
      case ViewerMode.markdown:
      case ViewerMode.html:
      case ViewerMode.xml:
        final result = _decodeText(data);
        encoding = result.encoding;
        lineCount = result.lineCount;
        mimeType = switch (mode) {
          ViewerMode.markdown => 'text/markdown',
          ViewerMode.html => 'text/html',
          ViewerMode.xml => 'application/xml',
          _ => 'text/plain',
        };

      case ViewerMode.image:
        mimeType = _mimeForImage(filename.toLowerCase());

      case ViewerMode.pdf:
        mimeType = 'application/pdf';

      case ViewerMode.media:
        mimeType = _mimeForMedia(filename.toLowerCase());

      case ViewerMode.font:
        mimeType = _mimeForFont(filename.toLowerCase());

      case ViewerMode.csv:
        mimeType = filename.toLowerCase().endsWith('.tsv')
            ? 'text/tab-separated-values'
            : 'text/csv';

      case ViewerMode.office:
        mimeType = _mimeForOffice(filename.toLowerCase());

      case ViewerMode.email:
        mimeType = filename.toLowerCase().endsWith('.msg')
            ? 'application/vnd.ms-outlook'
            : 'message/rfc822';

      case ViewerMode.archive:
        mimeType = _mimeForArchive(filename.toLowerCase());

      case ViewerMode.ascii:
      case ViewerMode.binary:
      case ViewerMode.hex:
      case ViewerMode.unsupported:
        mimeType = 'application/octet-stream';
    }

    return ViewerContent(
      data: data,
      mode: mode,
      filename: _basenameOf(filename),
      sizeBytes: data.length,
      encoding: encoding,
      lineCount: lineCount,
      mimeType: mimeType,
    );
  }

  // ---- Hex dump -------------------------------------------------------------

  /// Format [data] as a classic hex dump.
  ///
  /// [bytesPerLine] defaults to 16 (the canonical value).
  /// [offset] shifts the displayed offset column (useful for partial views).
  /// [limit] caps the number of *bytes* processed (not lines).
  List<HexLine> formatHexDump(
    Uint8List data, {
    int bytesPerLine = 16,
    int offset = 0,
    int? limit,
  }) {
    if (bytesPerLine < 1) bytesPerLine = 16;
    final end =
        limit != null ? (offset + limit).clamp(0, data.length) : data.length;
    final lines = <HexLine>[];

    for (var pos = offset; pos < end; pos += bytesPerLine) {
      final rowEnd = (pos + bytesPerLine).clamp(0, end);
      final chunk = data.sublist(pos, rowEnd);

      final hexParts = chunk
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .toList();

      final asciiPart = chunk.map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.').join();

      lines.add(HexLine(
        offset: pos,
        hexParts: hexParts,
        asciiPart: asciiPart,
      ));
    }

    return lines;
  }

  /// Parse a user-supplied hex byte pattern into bytes.
  ///
  /// Accepts `DE AD BE EF`, `de:ad:be:ef`, `0xDeadBeef`, `68 65 6c 6c 6f`
  /// (any non-hex separator). Returns null for malformed input.
  static Uint8List? parseHexPattern(String input) {
    final cleaned = input
        .toLowerCase()
        .replaceAll(RegExp(r'0x'), '')
        .replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (cleaned.isEmpty || cleaned.length % 2 != 0) return null;
    if (cleaned.length > 512) return null; // sanity cap
    final out = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.tryParse(cleaned.substring(i * 2, i * 2 + 2), radix: 16) ?? 0;
    }
    return out;
  }

  /// Find occurrences of [pattern] in [data], starting at [start].
  ///
  /// Returns at most [maxMatches] byte offsets.
  static List<int> findBytes(
    Uint8List data,
    List<int> pattern, {
    int start = 0,
    int? end,
    int maxMatches = 4096,
  }) {
    if (pattern.isEmpty) return const [];
    final e = end ?? data.length;
    final results = <int>[];
    outer:
    for (var i = (start < 0 ? 0 : start); i <= e - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      results.add(i);
      if (results.length >= maxMatches) break;
    }
    return results;
  }

  // ---- Text preview --------------------------------------------------------

  /// Decode [data] to a string with at most [maxLines] lines.
  ///
  /// Encoding is auto-detected: BOM → UTF-8/UTF-16, otherwise try UTF-8,
  /// fall back to Latin-1 (ISO-8859-1). If [encoding] is supplied it overrides
  /// detection ('utf8' / 'utf16le' / 'utf16be' / 'latin1').
  String getTextPreview(
    Uint8List data, {
    int maxLines = 1000,
    String? encoding,
  }) {
    if (data.isEmpty) return '';

    final decoded = decodeTextForView(data, encoding: encoding);
    final text = decoded.text;

    if (maxLines <= 0) return '';

    // Split preserving the original line endings.
    final lines = text.split('\n');
    if (lines.length <= maxLines) return text;

    return lines.take(maxLines).join('\n');
  }

  /// Decode bytes to a string for the viewer, honouring BOMs and optional
  /// [encoding] hints: 'utf8', 'utf16le', 'utf16be', 'latin1'.
  ///
  /// Without an explicit hint the decoder tries: UTF-16 BOM → UTF-8 BOM →
  /// strict UTF-8 → UTF-16 NUL-pattern sniff → Latin-1 fallback (which always
  /// succeeds, keeping the text view byte-safe for any input).
  static ({String text, String encoding}) decodeTextForView(
    Uint8List data, {
    String? encoding,
  }) {
    if (data.isEmpty) return (text: '', encoding: 'utf8');

    switch (encoding) {
      case 'latin1':
        return (text: latin1.decode(data), encoding: 'latin1');
      case 'utf16le':
        return (text: _decodeUtf16(data, false), encoding: 'utf16le');
      case 'utf16be':
        return (text: _decodeUtf16(data, true), encoding: 'utf16be');
      case 'utf32le':
        return (text: _decodeUtf32(data, false), encoding: 'utf32le');
      case 'utf32be':
        return (text: _decodeUtf32(data, true), encoding: 'utf32be');
      case 'utf8':
        return (text: utf8.decode(data, allowMalformed: true), encoding: 'utf8');
    }

    // Test four-byte BOMs before the UTF-16 prefixes they can share.
    if (data.length >= 4 &&
        data[0] == 0xff &&
        data[1] == 0xfe &&
        data[2] == 0 &&
        data[3] == 0) {
      return (text: _decodeUtf32(data.sublist(4), false), encoding: 'utf32le');
    }
    if (data.length >= 4 &&
        data[0] == 0 &&
        data[1] == 0 &&
        data[2] == 0xfe &&
        data[3] == 0xff) {
      return (text: _decodeUtf32(data.sublist(4), true), encoding: 'utf32be');
    }

    // UTF-16 LE BOM (FF FE).
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      return (text: _decodeUtf16(data.sublist(2), false), encoding: 'utf16le');
    }

    // UTF-16 BE BOM (FE FF).
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      return (text: _decodeUtf16(data.sublist(2), true), encoding: 'utf16be');
    }

    // UTF-8 BOM (EF BB BF).
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      final stripped = Uint8List.sublistView(data, 3);
      try {
        return (
          text: utf8.decode(stripped, allowMalformed: false),
          encoding: 'utf8',
        );
      } catch (_) {
        // Unusual: BOM present but body is not valid UTF-8; fall through.
      }
    }

    // Strict UTF-8 — but only after the UTF-16 sniff: NUL-interleaved bytes
    // decode as "valid UTF-8" while clearly being BOM-less UTF-16.
    final sniff = _sniffUtf16(data);
    if (sniff != null) return sniff;

    try {
      return (text: utf8.decode(data, allowMalformed: false), encoding: 'utf8');
    } catch (_) {/* fall through */}

    // Fall back to Latin-1 which can always decode arbitrary bytes.
    return (text: latin1.decode(data), encoding: 'latin1');
  }

  static String _decodeUtf32(Uint8List data, bool bigEndian) {
    final buffer = StringBuffer();
    final view = ByteData.sublistView(data);
    for (var offset = 0; offset + 4 <= data.length; offset += 4) {
      final code = view.getUint32(
        offset,
        bigEndian ? Endian.big : Endian.little,
      );
      buffer.writeCharCode(
        code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) ? 0xfffd : code,
      );
    }
    return buffer.toString();
  }

  /// Detect BOM-less UTF-16 by sampling the first kilobyte.
  static ({String text, String encoding})? _sniffUtf16(Uint8List data) {
    if (data.length < 16) return null;
    final sample = data.length > 1024 ? Uint8List.sublistView(data, 0, 1024) : data;
    final pairs = sample.length ~/ 2;
    var leMatch = 0;
    var beMatch = 0;
    for (var i = 0; i < pairs; i++) {
      final lo = sample[i * 2];
      final hi = sample[i * 2 + 1];
      // Count code units that look like ASCII with a specific byte order.
      final isLeAscii = hi == 0x00 &&
          (lo >= 0x20 && lo < 0x7F || lo == 0x0A || lo == 0x0D || lo == 0x09);
      final isBeAscii = lo == 0x00 &&
          (hi >= 0x20 && hi < 0x7F || hi == 0x0A || hi == 0x0D || hi == 0x09);
      if (isLeAscii) leMatch++;
      if (isBeAscii) beMatch++;
    }
    if (pairs == 0) return null;
    if (leMatch > pairs * 0.9) {
      return (text: _decodeUtf16(data, false), encoding: 'utf16le');
    }
    if (beMatch > pairs * 0.9) {
      return (text: _decodeUtf16(data, true), encoding: 'utf16be');
    }
    return null;
  }

  /// Decode UTF-16 code units into a Dart string. [bigEndian] selects the
  /// unit order; a trailing odd byte is ignored and surrogate pairs are
  /// preserved verbatim.
  static String _decodeUtf16(Uint8List data, bool bigEndian) {
    final units = data.length ~/ 2;
    final buf = StringBuffer();
    for (var i = 0; i < units; i++) {
      final lo = data[i * 2];
      final hi = data[i * 2 + 1];
      final unit = bigEndian ? (lo << 8 | hi) : (hi << 8 | lo);
      buf.writeCharCode(unit);
    }
    return buf.toString();
  }

  // ---- Safe byte rendering (DC ASCII / Binary views) ------------------------

  /// Render raw bytes as a *safe* ASCII string for the DC-style lister views.
  ///
  /// [asciiMode] (ViewerMode.ascii semantics):
  ///  - 0x20–0x7E literal; TAB kept; LF line break; other control bytes <0x20
  ///    and 0x7F–0x9F → '·'; 0xA0–0xFF → Latin-1 glyph (à, é … are readable).
  ///
  /// [binaryMode] (ViewerMode.binary semantics) — pure byte view:
  ///  - only 0x20–0x7E and TAB/LF survive; every other byte becomes '.'
  ///    (including high bytes — you see the bytes, not a glyph interpretation).
  ///
  /// CR is treated as a line break unless directly followed by LF (CRLF).
  static String renderSafeBytes(
    Uint8List data, {
    bool binaryMode = false,
    int start = 0,
    int? end,
  }) {
    final e = (end ?? data.length).clamp(start, data.length);
    if (start < 0) start = 0;
    if (start >= e) return '';

    final buf = StringBuffer();
    for (var i = start; i < e; i++) {
      final b = data[i];
      if (b >= 0x20 && b < 0x7F) {
        buf.writeCharCode(b);
      } else if (b == 0x09) {
        buf.write('\t');
      } else if (b == 0x0A) {
        buf.write('\n');
      } else if (b == 0x0D) {
        // CRLF → emit only the LF (the loop writes it next).
        if (i + 1 >= e || data[i + 1] != 0x0A) buf.write('\n');
      } else if (binaryMode || b == 0x7F || b < 0x20 || (b >= 0x80 && b < 0xA0)) {
        buf.write(binaryMode ? '.' : '·');
      } else {
        // Latin-1 high byte (0xA0–0xFF) — only reachable in ASCII mode.
        buf.write(latin1.decode([b]));
      }
    }
    return buf.toString();
  }

  // ---- Search --------------------------------------------------------------

  /// Return the list of byte-offsets in [content] where [query] is found.
  ///
  /// For text/markdown modes: search is performed on the decoded string
  /// (case-insensitive); returned offsets are *character* indices in the
  /// decoded text.
  ///
  /// For all other modes: search is performed on the raw bytes, interpreting
  /// [query] as a UTF-8 byte sequence; returned offsets are byte indices.
  List<int> searchInContent(ViewerContent content, String query) {
    if (query.isEmpty) return const [];

    if (content.mode == ViewerMode.text ||
        content.mode == ViewerMode.markdown) {
      return _searchText(content.data, query);
    }

    return _searchBytes(content.data, utf8.encode(query));
  }

  // ---- MIME helpers --------------------------------------------------------

  /// MIME type for image extensions.
  static String _mimeForImage(String lower) {
    final ext = _extensionOf(lower);
    return switch (ext) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.svg' => 'image/svg+xml',
      '.ico' => 'image/x-icon',
      '.tiff' || '.tif' => 'image/tiff',
      '.avif' => 'image/avif',
      '.heic' || '.heif' => 'image/heic',
      _ => 'image/unknown',
    };
  }

  /// MIME type for audio/video extensions (HTML5 playback on web).
  static String _mimeForMedia(String lower) {
    final ext = _extensionOf(lower);
    return switch (ext) {
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.aac' => 'audio/aac',
      '.flac' => 'audio/flac',
      '.ogg' || '.oga' || '.ogv' => 'audio/ogg',
      '.m4a' => 'audio/mp4',
      '.wma' => 'audio/x-ms-wma',
      '.opus' => 'audio/opus',
      '.aiff' || '.aif' => 'audio/aiff',
      '.mid' || '.midi' => 'audio/midi',
      '.amr' => 'audio/amr',
      '.au' => 'audio/basic',
      '.gsm' => 'audio/gsm',
      '.mp4' => 'video/mp4',
      '.webm' => 'video/webm',
      '.mov' => 'video/quicktime',
      '.avi' => 'video/x-msvideo',
      '.mkv' => 'video/x-matroska',
      '.wmv' => 'video/x-ms-wmv',
      '.flv' => 'video/x-flv',
      '.3gp' => 'video/3gpp',
      '.mpg' || '.mpeg' => 'video/mpeg',
      _ => 'application/octet-stream',
    };
  }

  /// MIME type for font extensions.
  static String _mimeForFont(String lower) {
    final ext = _extensionOf(lower);
    return switch (ext) {
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.pfb' => 'application/x-font',
      _ => 'font/unknown',
    };
  }

  /// MIME type for office document extensions (text extraction).
  static String _mimeForOffice(String lower) {
    final ext = _extensionOf(lower);
    return switch (ext) {
      '.doc' || '.dot' => 'application/msword',
      '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.docm' => 'application/vnd.ms-word.document.macroEnabled.12',
      '.dotx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
      '.dotm' => 'application/vnd.ms-word.template.macroEnabled.12',
      '.xlsx' || '.xlsm' || '.xltx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.pptx' || '.pptm' || '.potx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.odt' => 'application/vnd.oasis.opendocument.text',
      '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
      '.odp' => 'application/vnd.oasis.opendocument.presentation',
      '.epub' => 'application/epub+zip',
      _ => 'application/x-office',
    };
  }

  /// MIME type for archive extensions.
  static String _mimeForArchive(String lower) {
    final ext = _extensionOf(lower);
    return switch (ext) {
      '.zip' || '.jar' || '.whl' || '.apk' || '.ipa' || '.aab'
          || '.crx' || '.xpi' || '.nupkg' || '.vsix'
          || '.cbz' => 'application/zip',
      '.7z' || '.cb7' => 'application/x-7z-compressed',
      '.rar' || '.cbr' => 'application/vnd.rar',
      '.tar' || '.cbt' => 'application/x-tar',
      '.gz' || '.tgz' || '.tar.gz' => 'application/gzip',
      '.bz2' || '.tbz' || '.tbz2' || '.tar.bz2' => 'application/x-bzip2',
      '.xz' || '.txz' || '.tar.xz' => 'application/x-xz',
      '.zst' || '.tzst' || '.tar.zst' => 'application/zstd',
      _ => 'application/octet-stream',
    };
  }

  // ---- Private helpers -------------------------------------------------------

  /// Extract the file extension (lower-case, including the leading dot).
  static String _extensionOf(String lower) {
    final slash = lower.lastIndexOf('/');
    final backslash = lower.lastIndexOf('\\');
    final start = (slash > backslash ? slash : backslash) + 1;
    final basename = lower.substring(start);

    final dot = basename.lastIndexOf('.');
    if (dot < 0) return '';
    return basename.substring(dot);
  }

  /// Extract just the filename (no directory component).
  static String _basenameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final start = (slash > backslash ? slash : backslash) + 1;
    return path.substring(start);
  }

  /// Check known magic byte signatures.
  static ViewerMode? _detectMagic(Uint8List header) {
    if (header.length >= 4) {
      // PNG: 89 50 4E 47
      if (header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47) {
        return ViewerMode.image;
      }

      // JPEG: FF D8 FF
      if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        return ViewerMode.image;
      }

      // GIF: 47 49 46 38 (GIF8)
      if (header[0] == 0x47 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x38) {
        return ViewerMode.image;
      }

      // BMP: 42 4D
      if (header[0] == 0x42 && header[1] == 0x4D) {
        return ViewerMode.image;
      }

      // PDF: 25 50 44 46 (%PDF)
      if (header[0] == 0x25 &&
          header[1] == 0x50 &&
          header[2] == 0x44 &&
          header[3] == 0x46) {
        return ViewerMode.pdf;
      }

      // RIFF family: 52 49 46 46
      if (header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46) {
        // WebP: RIFF????WEBP
        if (header[8] == 0x57 &&
            header[9] == 0x45 &&
            header[10] == 0x42 &&
            header[11] == 0x50) {
          return ViewerMode.image;
        }
        // WAV: RIFF????WAVE
        if (header[8] == 0x57 &&
            header[9] == 0x41 &&
            header[10] == 0x56 &&
            header[11] == 0x45) {
          return ViewerMode.media;
        }
        // AVI: RIFF????AVI
        if (header[8] == 0x41 &&
            header[9] == 0x56 &&
            header[10] == 0x49 &&
            header[11] == 0x20) {
          return ViewerMode.media;
        }
      }

      // MP4/M4V/M4A: ????ftyp
      if (header.length >= 8 &&
          header[4] == 0x66 &&
          header[5] == 0x74 &&
          header[6] == 0x79 &&
          header[7] == 0x70) {
        return ViewerMode.media;
      }

      // FLAC: fLaC
      if (header[0] == 0x66 &&
          header[1] == 0x4C &&
          header[2] == 0x61 &&
          header[3] == 0x43) {
        return ViewerMode.media;
      }

      // MP3 (ID3 tag): 49 44 33
      if (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
        return ViewerMode.media;
      }

      // OGG: 4F 67 67 53
      if (header[0] == 0x4F &&
          header[1] == 0x67 &&
          header[2] == 0x67 &&
          header[3] == 0x53) {
        return ViewerMode.media;
      }

      // TTF: 00 01 00 00 | OTF: OTTO
      if ((header[0] == 0x00 && header[1] == 0x01 && header[2] == 0x00 && header[3] == 0x00) ||
          (header[0] == 0x4F && header[1] == 0x54 && header[2] == 0x54 && header[3] == 0x4F)) {
        return ViewerMode.font;
      }

      // WOFF/WOFF2: wOF…
      if (header[0] == 0x77 && header[1] == 0x4F && header[2] == 0x46) {
        return ViewerMode.font;
      }

      // ZIP containers (office docs, epub, zips) are left to the extension
      // mapping, which disambiguates docx/xlsx/epub from generic archives.

      // ELF executable: 7F 45 4C 46
      if (header[0] == 0x7F &&
          header[1] == 0x45 &&
          header[2] == 0x4C &&
          header[3] == 0x46) {
        return ViewerMode.binary;
      }

      // Windows PE: 4D 5A (MZ)
      if (header[0] == 0x4D && header[1] == 0x5A) {
        return ViewerMode.binary;
      }
    }

    // 7z: 37 7A BC AF 27 1C
    if (header.length >= 6 &&
        header[0] == 0x37 &&
        header[1] == 0x7A &&
        header[2] == 0xBC &&
        header[3] == 0xAF &&
        header[4] == 0x27 &&
        header[5] == 0x1C) {
      return ViewerMode.archive;
    }

    // RAR4 / RAR5: 52 61 72 21 1A 07
    if (header.length >= 7 &&
        header[0] == 0x52 &&
        header[1] == 0x61 &&
        header[2] == 0x72 &&
        header[3] == 0x21 &&
        header[4] == 0x1A &&
        header[5] == 0x07) {
      return ViewerMode.archive;
    }

    // XZ: FD 37 7A 58 5A 00
    if (header.length >= 6 &&
        header[0] == 0xFD &&
        header[1] == 0x37 &&
        header[2] == 0x7A &&
        header[3] == 0x58 &&
        header[4] == 0x5A &&
        header[5] == 0x00) {
      return ViewerMode.archive;
    }

    // Zstandard: 28 B5 2F FD
    if (header.length >= 4 &&
        header[0] == 0x28 &&
        header[1] == 0xB5 &&
        header[2] == 0x2F &&
        header[3] == 0xFD) {
      return ViewerMode.archive;
    }

    // POSIX tar: "ustar" at offset 257.
    if (header.length >= 262 &&
        header[257] == 0x75 &&
        header[258] == 0x73 &&
        header[259] == 0x74 &&
        header[260] == 0x61 &&
        header[261] == 0x72) {
      return ViewerMode.archive;
    }

    // GZIP: 1F 8B
    if (header.length >= 2 && header[0] == 0x1F && header[1] == 0x8B) {
      return ViewerMode.archive;
    }

    // BZIP2: BZh
    if (header.length >= 3 &&
        header[0] == 0x42 &&
        header[1] == 0x5A &&
        header[2] == 0x68) {
      return ViewerMode.archive;
    }

    // UTF-16 BOMs (FF FE / FE FF) → text.
    if (header.length >= 2 &&
        ((header[0] == 0xFF && header[1] == 0xFE) ||
            (header[0] == 0xFE && header[1] == 0xFF))) {
      return ViewerMode.text;
    }

    // UTF-8 BOM: EF BB BF  → text
    if (header.length >= 3 &&
        header[0] == 0xEF &&
        header[1] == 0xBB &&
        header[2] == 0xBF) {
      return ViewerMode.text;
    }

    return null;
  }

  // ---- Text decoding helpers ------------------------------------------------

  /// Decoded text with metadata.
  static ({String text, String encoding, int lineCount}) _decodeText(
      Uint8List data) {
    final result = decodeTextForView(data);
    final lineCount = '\n'.allMatches(result.text).length + (result.text.isNotEmpty ? 1 : 0);
    return (
      text: result.text,
      encoding: result.encoding,
      lineCount: lineCount,
    );
  }

  // ---- Search helpers -------------------------------------------------------

  /// Case-insensitive search on decoded text; returns character offsets.
  List<int> _searchText(Uint8List data, String query) {
    final decoded = decodeTextForView(data);
    final text = decoded.text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final results = <int>[];
    var start = 0;
    while (true) {
      final idx = text.indexOf(lowerQuery, start);
      if (idx < 0) break;
      results.add(idx);
      start = idx + 1;
    }
    return results;
  }

  /// Exact byte-pattern search on raw data; returns byte offsets.
  List<int> _searchBytes(Uint8List data, List<int> pattern) =>
      findBytes(data, pattern);
}
