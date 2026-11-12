import 'dart:convert';
import 'dart:typed_data';

enum FileConversionFormat {
  uue('UUE', '.uue'),
  xxe('XXE', '.xxe'),
  mime('MIME (Base64)', '.mime');

  const FileConversionFormat(this.label, this.extension);
  final String label;
  final String extension;
}

enum FileConversionDirection { encode, decode }

enum FileConversionCodecProblem {
  malformed,
  unsupportedMime,
  headerLimit,
  filename,
}

class FileConversionCodecException implements Exception {
  const FileConversionCodecException(this.problem);
  final FileConversionCodecProblem problem;
  @override
  String toString() => 'File conversion: ${problem.name}';
}

/// Independent streaming implementations of the historical 6-bit file
/// encodings and a single-part Base64 MIME entity. See docs/file-conversion.md
/// for specification references and the deliberately restricted decoder scope.
class FileConversionCodec {
  const FileConversionCodec();

  static const maxLineBytes = 4096;
  static const maxHeaderBytes = 64 * 1024;
  // Even fully percent-encoded UTF-8 fits on one MIME header line (< 998).
  static const maxFilenameBytes = 255;
  static const outputChunkBytes = 32 * 1024;
  static const _base64 =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  static const _xx =
      '+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static final _uu = String.fromCharCodes([
    96,
    ...List.generate(63, (i) => i + 33),
  ]);

  bool _invalidFilename(String filename) =>
      filename.isEmpty ||
      filename.trim() != filename ||
      filename == '.' ||
      filename == '..' ||
      filename.contains('/') ||
      filename.contains('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(filename) ||
      utf8.encode(filename).length > maxFilenameBytes ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(filename);

  void validateFilename(String filename, FileConversionFormat format) {
    if (_invalidFilename(filename) ||
        (format != FileConversionFormat.mime &&
            filename.codeUnits.any((byte) => byte > 126))) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.filename,
      );
    }
  }

  Stream<List<int>> encode(
    Stream<List<int>> input, {
    required FileConversionFormat format,
    required String filename,
  }) async* {
    validateFilename(filename, format);
    final mime = format == FileConversionFormat.mime;
    if (mime) {
      // RFC 2231 parameter bytes are UTF-8, not an encoded-word or HTTP header.
      final name = utf8
          .encode(filename)
          .map(
            (byte) =>
                '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          )
          .join();
      final header =
          'MIME-Version: 1.0\r\n'
          'Content-Type: application/octet-stream\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          'Content-Disposition: attachment;\r\n filename*=UTF-8\'\'$name\r\n\r\n';
      if (header.split('\r\n').any((line) => line.length > maxLineBytes)) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.headerLimit,
        );
      }
      yield ascii.encode(header);
    } else {
      yield ascii.encode('begin 600 $filename\n');
    }
    final alphabet = mime
        ? _base64
        : format == FileConversionFormat.uue
        ? _uu
        : _xx;
    final lineBytes = mime ? 57 : 45;
    final pending = Uint8List(lineBytes);
    var used = 0;
    var output = BytesBuilder(copy: false);
    void line(int count) {
      final chars = <int>[if (!mime) alphabet.codeUnitAt(count)];
      for (var i = 0; i < count; i += 3) {
        final a = pending[i];
        final b = i + 1 < count ? pending[i + 1] : 0;
        final c = i + 2 < count ? pending[i + 2] : 0;
        chars.addAll([
          alphabet.codeUnitAt(a >> 2),
          alphabet.codeUnitAt(((a & 3) << 4) | (b >> 4)),
          mime && i + 1 >= count
              ? 61
              : alphabet.codeUnitAt(((b & 15) << 2) | (c >> 6)),
          mime && i + 2 >= count ? 61 : alphabet.codeUnitAt(c & 63),
          if (mime && i + 3 >= count) 13,
        ]);
      }
      chars.add(10);
      output.add(Uint8List.fromList(chars));
    }

    await for (final chunk in input) {
      for (final byte in chunk) {
        if (byte < 0 || byte > 255) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        pending[used++] = byte;
        if (used == lineBytes) {
          line(used);
          used = 0;
          if (output.length >= outputChunkBytes) {
            yield output.takeBytes();
            output = BytesBuilder(copy: false);
          }
        }
      }
    }
    if (used > 0) line(used);
    if (!mime) output.add(ascii.encode('${alphabet[0]}\nend\n'));
    if (output.isNotEmpty) yield output.takeBytes();
  }

  Stream<List<int>> decode(
    Stream<List<int>> input, {
    required FileConversionFormat format,
    void Function(String? filename)? onFilename,
  }) => format == FileConversionFormat.mime
      ? _decodeMime(input, onFilename)
      : _decodeLegacy(input, format, onFilename);

  Stream<String> _lines(Stream<List<int>> input) async* {
    var line = <int>[];
    String takeLine() {
      if (line.isNotEmpty && line.last == 13) line.removeLast();
      if (line.contains(13)) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      final result = ascii.decode(line);
      line = <int>[];
      return result;
    }

    await for (final chunk in input) {
      for (final byte in chunk) {
        if (byte == 10) {
          yield takeLine();
        } else {
          if (byte < 0 ||
              byte > 127 ||
              (byte < 32 && byte != 9 && byte != 13)) {
            throw const FileConversionCodecException(
              FileConversionCodecProblem.malformed,
            );
          }
          line.add(byte);
          if (line.length > maxLineBytes) {
            throw const FileConversionCodecException(
              FileConversionCodecProblem.headerLimit,
            );
          }
        }
      }
    }
    if (line.isNotEmpty) yield takeLine();
  }

  Stream<List<int>> _decodeLegacy(
    Stream<List<int>> input,
    FileConversionFormat format,
    void Function(String?)? onFilename,
  ) async* {
    var begun = false, zero = false, ended = false;
    var headerBytes = 0;
    var output = BytesBuilder(copy: false);
    final alphabet = format == FileConversionFormat.uue ? _uu : _xx;
    int value(int code) {
      if (format == FileConversionFormat.uue && code == 32) return 0;
      final found = alphabet.indexOf(String.fromCharCode(code));
      if (found < 0) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      return found;
    }

    await for (final line in _lines(input)) {
      if (!begun) {
        headerBytes += line.length + 1;
        if (headerBytes > maxHeaderBytes) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.headerLimit,
          );
        }
        if (!line.startsWith('begin ')) continue;
        final match = RegExp(r'^begin [0-7]{3,4} (.+)$').firstMatch(line);
        if (match == null || _invalidFilename(match[1]!)) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        onFilename?.call(match[1]);
        begun = true;
        continue;
      }
      if (ended) {
        if (line.trim().isNotEmpty) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        continue;
      }
      if (zero) {
        if (line != 'end') {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        ended = true;
        continue;
      }
      if (line.isEmpty) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      final count = value(line.codeUnitAt(0));
      if (count > 45 || line.length != 1 + ((count + 2) ~/ 3) * 4) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      if (count == 0) {
        zero = true;
        continue;
      }
      final decoded = <int>[];
      for (var i = 1; i < line.length; i += 4) {
        final a = value(line.codeUnitAt(i));
        final b = value(line.codeUnitAt(i + 1));
        final c = value(line.codeUnitAt(i + 2));
        final d = value(line.codeUnitAt(i + 3));
        decoded.addAll([
          (a << 2) | (b >> 4),
          ((b & 15) << 4) | (c >> 2),
          ((c & 3) << 6) | d,
        ]);
      }
      output.add(Uint8List.fromList(decoded.take(count).toList()));
      if (output.length >= outputChunkBytes) {
        yield output.takeBytes();
        output = BytesBuilder(copy: false);
      }
    }
    if (!begun || !zero || !ended) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
    if (output.isNotEmpty) yield output.takeBytes();
  }

  Stream<List<int>> _decodeMime(
    Stream<List<int>> input,
    void Function(String?)? onFilename,
  ) async* {
    final headers = <String, String>{};
    String? lastHeader;
    var headerBytes = 0, body = false, padded = false;
    final quantum = <int>[];
    var output = BytesBuilder(copy: false);
    await for (final line in _lines(input)) {
      if (!body) {
        headerBytes += line.length + 2;
        if (headerBytes > maxHeaderBytes || headers.length > 64) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.headerLimit,
          );
        }
        if (line.isEmpty) {
          if (headers['content-transfer-encoding']?.toLowerCase() != 'base64' ||
              (headers['mime-version'] != null &&
                  headers['mime-version'] != '1.0')) {
            throw const FileConversionCodecException(
              FileConversionCodecProblem.unsupportedMime,
            );
          }
          final type = headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase();
          if (type == null ||
              !RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$')
                  .hasMatch(type) ||
              type.startsWith('multipart/') ||
              type.startsWith('message/')) {
            throw const FileConversionCodecException(
              FileConversionCodecProblem.unsupportedMime,
            );
          }
          // Validation is unconditional: a caller that ignores filename
          // metadata must not accidentally accept unsupported/malformed MIME.
          final filename = _mimeFilename(headers['content-disposition']);
          onFilename?.call(filename);
          body = true;
          continue;
        }
        if (line.startsWith(' ') || line.startsWith('\t')) {
          if (lastHeader == null) {
            throw const FileConversionCodecException(
              FileConversionCodecProblem.malformed,
            );
          }
          headers[lastHeader] = '${headers[lastHeader]} ${line.trim()}';
          continue;
        }
        final colon = line.indexOf(':');
        if (colon < 1 ||
            !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(line.substring(0, colon))) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        lastHeader = line.substring(0, colon).toLowerCase();
        if (headers.containsKey(lastHeader)) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        headers[lastHeader] = line.substring(colon + 1).trim();
        continue;
      }
      for (final code in line.codeUnits) {
        if (code == 32 || code == 9) continue;
        if (padded) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        if (code != 61 && !_base64.contains(String.fromCharCode(code))) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        quantum.add(code);
        if (quantum.length != 4) continue;
        final a = _base64.indexOf(String.fromCharCode(quantum[0]));
        final b = _base64.indexOf(String.fromCharCode(quantum[1]));
        final c = quantum[2] == 61
            ? -1
            : _base64.indexOf(String.fromCharCode(quantum[2]));
        final d = quantum[3] == 61
            ? -1
            : _base64.indexOf(String.fromCharCode(quantum[3]));
        if (a < 0 ||
            b < 0 ||
            (c < 0 && d >= 0) ||
            (c < 0 && (b & 15) != 0) ||
            (d < 0 && c >= 0 && (c & 3) != 0)) {
          throw const FileConversionCodecException(
            FileConversionCodecProblem.malformed,
          );
        }
        output.add(
          Uint8List.fromList([
            (a << 2) | (b >> 4),
            if (c >= 0) ((b & 15) << 4) | (c >> 2),
            if (d >= 0) ((c & 3) << 6) | d,
          ]),
        );
        padded = c < 0 || d < 0;
        quantum.clear();
        if (output.length >= outputChunkBytes) {
          yield output.takeBytes();
          output = BytesBuilder(copy: false);
        }
      }
    }
    if (!body || quantum.isNotEmpty) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
    if (output.isNotEmpty) yield output.takeBytes();
  }

  String? _mimeFilename(String? disposition) {
    if (disposition == null) return null;
    final parts = <String>[];
    final current = StringBuffer();
    var quoted = false, escaped = false;
    for (final code in disposition.codeUnits) {
      if (escaped) {
        current.writeCharCode(code);
        escaped = false;
        continue;
      }
      if (quoted && code == 92) {
        escaped = true;
        continue;
      }
      if (code == 34) {
        quoted = !quoted;
        continue;
      }
      if (code == 59 && !quoted) {
        parts.add(current.toString().trim());
        current.clear();
      } else {
        current.writeCharCode(code);
      }
    }
    if (quoted || escaped) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
    parts.add(current.toString().trim());
    final params = <String, String>{};
    for (final part in parts.skip(1)) {
      final equal = part.indexOf('=');
      if (equal < 1) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      final key = part.substring(0, equal).trim().toLowerCase();
      if (params.containsKey(key)) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      params[key] = part.substring(equal + 1).trim();
    }
    String? name;
    if (params.containsKey('filename*')) {
      if (params.keys.any((key) => RegExp(r'^filename\*\d').hasMatch(key))) {
        throw const FileConversionCodecException(
          FileConversionCodecProblem.malformed,
        );
      }
      name = _extendedFilename(params['filename*']!);
    } else if (params.keys.any(
      (key) => RegExp(r'^filename\*\d').hasMatch(key),
    )) {
      // The file converter deliberately rejects RFC 2231 continuation variants
      // rather than guessing an ambiguous or incomplete attachment filename.
      throw const FileConversionCodecException(
        FileConversionCodecProblem.unsupportedMime,
      );
    } else {
      name = params['filename'];
    }
    if (name != null && _invalidFilename(name)) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
    return name;
  }

  String _extendedFilename(String value) {
    final first = value.indexOf("'");
    final second = value.indexOf("'", first + 1);
    if (first < 0 || second < 0) {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
    final charset = value.substring(0, first).toLowerCase();
    if (charset != 'utf-8' && charset != 'us-ascii') {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.unsupportedMime,
      );
    }
    try {
      final name = Uri.decodeComponent(value.substring(second + 1));
      if (charset == 'us-ascii' && name.codeUnits.any((unit) => unit > 127)) {
        throw const FormatException();
      }
      return name;
    } on FormatException {
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    } on ArgumentError {
      // Dart reports malformed percent escapes as ArgumentError; invalid
      // decoded UTF-8 uses FormatException. Both are malformed input here.
      throw const FileConversionCodecException(
        FileConversionCodecProblem.malformed,
      );
    }
  }
}
