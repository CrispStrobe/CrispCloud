// lib/services/internal_viewer_service.dart
//
// Internal file viewer service for the dual-panel orthodox file manager.
// Supports F3 quick-preview in text, hex, image, markdown, PDF, and binary modes.

import 'dart:convert';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// ViewerMode enum
// ---------------------------------------------------------------------------

/// Discriminated mode determining how the viewer renders a file.
enum ViewerMode {
  /// Plain text — UTF-8 or Latin-1 encoded.
  text,

  /// Raw hex dump — 16 bytes per row with offset + hex + ASCII columns.
  hex,

  /// Raster or vector image (.png, .jpg, .gif, .webp, .bmp, .svg).
  image,

  /// Arbitrary binary data for which no better mode is available.
  binary,

  /// Markdown document (.md, .markdown).
  markdown,

  /// PDF document.
  pdf,

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

/// Maximum file size that the viewer will attempt to load (50 MB).
const _kMaxViewSizeBytes = 50 * 1024 * 1024;

class InternalViewerService {
  const InternalViewerService();

  // ---- Extension → mode mapping --------------------------------------------

  /// Returns a map from [ViewerMode] to the list of file extensions handled by
  /// that mode (lower-case, including the leading dot).
  Map<ViewerMode, List<String>> getSupportedExtensions() => const {
        ViewerMode.text: [
          '.txt',
          '.log',
          '.csv',
          '.json',
          '.xml',
          '.yaml',
          '.yml',
          '.toml',
          '.ini',
          '.cfg',
          '.conf',
          '.dart',
          '.py',
          '.js',
          '.ts',
          '.jsx',
          '.tsx',
          '.java',
          '.kt',
          '.swift',
          '.c',
          '.cpp',
          '.h',
          '.hpp',
          '.cs',
          '.go',
          '.rs',
          '.rb',
          '.php',
          '.sh',
          '.bash',
          '.zsh',
          '.fish',
          '.bat',
          '.cmd',
          '.ps1',
          '.html',
          '.htm',
          '.css',
          '.scss',
          '.sass',
          '.less',
          '.sql',
          '.r',
          '.m',
          '.tex',
          '.diff',
          '.patch',
          '.gitignore',
          '.env',
          '.properties',
        ],
        ViewerMode.image: [
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.webp',
          '.bmp',
          '.svg',
          '.ico',
          '.tiff',
          '.tif',
          '.avif',
          '.heic',
          '.heif',
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
        ViewerMode.binary: [
          '.exe',
          '.dll',
          '.so',
          '.dylib',
          '.bin',
          '.dat',
          '.db',
          '.sqlite',
          '.o',
          '.obj',
          '.class',
          '.pyc',
          '.wasm',
        ],
      };

  // ---- Mode detection -------------------------------------------------------

  /// Detect the best [ViewerMode] for [filename].
  ///
  /// If [header] is supplied (first ~16 bytes of the file) it is also checked
  /// for known magic byte signatures, which override extension-based guessing.
  ViewerMode detectMode(String filename, {Uint8List? header}) {
    // Magic-byte check takes precedence.
    if (header != null && header.isNotEmpty) {
      final magic = _detectMagic(header);
      if (magic != null) return magic;
    }

    final lower = filename.toLowerCase();

    // Try to find a matching extension from longest to shortest so that
    // multi-segment extensions like ".tar.gz" are handled correctly if added.
    final ext = _extensionOf(lower);

    final map = getSupportedExtensions();
    for (final entry in map.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }

    // Unknown extension → binary.
    return ViewerMode.binary;
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
        final result = _decodeText(data);
        encoding = result.encoding;
        lineCount = result.lineCount;
        mimeType = mode == ViewerMode.markdown ? 'text/markdown' : 'text/plain';

      case ViewerMode.image:
        mimeType = _mimeForImage(filename.toLowerCase());

      case ViewerMode.pdf:
        mimeType = 'application/pdf';

      case ViewerMode.hex:
      case ViewerMode.binary:
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

  // ---- Text preview --------------------------------------------------------

  /// Decode [data] to a string with at most [maxLines] lines.
  ///
  /// Encoding is auto-detected: UTF-8 BOM → UTF-8, otherwise try UTF-8, fall
  /// back to Latin-1 (ISO-8859-1).  If [encoding] is supplied it overrides
  /// detection ('utf8' or 'latin1').
  String getTextPreview(
    Uint8List data, {
    int maxLines = 1000,
    String? encoding,
  }) {
    if (data.isEmpty) return '';

    final decoded = _decodeBytes(data, hint: encoding);
    final text = decoded.text;

    if (maxLines <= 0) return '';

    // Split preserving the original line endings.
    final lines = text.split('\n');
    if (lines.length <= maxLines) return text;

    return lines.take(maxLines).join('\n');
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

      // WebP: RIFF????WEBP
      if (header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return ViewerMode.image;
      }

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

    // UTF-8 BOM: EF BB BF  → text
    if (header.length >= 3 &&
        header[0] == 0xEF &&
        header[1] == 0xBB &&
        header[2] == 0xBF) {
      return ViewerMode.text;
    }

    return null;
  }

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

  // ---- Text decoding helpers ------------------------------------------------

  /// Decoded text with metadata.
  static ({String text, String encoding, int lineCount}) _decodeText(
      Uint8List data) {
    final result = _decodeBytes(data);
    final lineCount = '\n'.allMatches(result.text).length + (result.text.isNotEmpty ? 1 : 0);
    return (
      text: result.text,
      encoding: result.encoding,
      lineCount: lineCount,
    );
  }

  /// Decode bytes to a string, auto-detecting encoding.
  static ({String text, String encoding}) _decodeBytes(
    Uint8List data, {
    String? hint,
  }) {
    if (data.isEmpty) return (text: '', encoding: 'utf8');

    // Caller override.
    if (hint == 'latin1') {
      return (text: latin1.decode(data), encoding: 'latin1');
    }

    // UTF-8 BOM (EF BB BF) → strip BOM, decode as UTF-8.
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

    // Try strict UTF-8.
    try {
      final text = utf8.decode(data, allowMalformed: false);
      return (text: text, encoding: 'utf8');
    } catch (_) {
      // Fall back to Latin-1 which can always decode arbitrary bytes.
      return (text: latin1.decode(data), encoding: 'latin1');
    }
  }

  // ---- Search helpers -------------------------------------------------------

  /// Case-insensitive search on decoded text; returns character offsets.
  List<int> _searchText(Uint8List data, String query) {
    final decoded = _decodeBytes(data);
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
  List<int> _searchBytes(Uint8List data, List<int> pattern) {
    if (pattern.isEmpty) return const [];
    final results = <int>[];
    outer:
    for (var i = 0; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      results.add(i);
    }
    return results;
  }
}
