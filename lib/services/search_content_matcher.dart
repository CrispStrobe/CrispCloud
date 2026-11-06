import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/file_search_query.dart';

/// Match already decoded text. Structured-document extraction bypasses the
/// encoding choice, which describes plain input bytes rather than extracted text.
String? matchSearchText(String text, FileSearchQuery query) {
  final expression = RegExp(
    query.contentRegex
        ? query.contentPattern
        : RegExp.escape(query.contentPattern),
    caseSensitive: query.contentCaseSensitive,
    multiLine: query.contentRegex,
    unicode: true,
  );
  final match = expression.firstMatch(text);
  if (query.contentNegated) {
    return match == null ? 'Content does not contain the query.' : null;
  }
  if (match == null) return null;
  final start = math.max(0, match.start - 45);
  final end = math.min(text.length, match.end + 90);
  return '${start > 0 ? '…' : ''}'
      '${text.substring(start, end).replaceAll('\n', ' ')}'
      '${end < text.length ? '…' : ''}';
}

/// Search complete plain files with memory bounded by the query and a 32 KiB
/// decode chunk. The full stream is consumed before reporting a result so a
/// negative match or late read failure is never mistaken for a completed search.
/// Arbitrary regular expressions deliberately remain on the bounded full-text
/// path: finite overlap cannot implement every regex faithfully.
Future<String?> searchLiteralContent(
  Stream<List<int>> stream,
  FileSearchQuery query, {
  required void Function() check,
}) async {
  if (query.contentRegex) {
    throw ArgumentError('Streaming content search requires a literal query.');
  }
  final sample = BytesBuilder(copy: false);
  _TextDecoder? primary;
  _TextDecoder? fallback;

  void initialize() {
    final bytes = sample.takeBytes();
    final automatic = query.contentEncoding == 'auto';
    final detected = automatic
        ? _detectEncoding(bytes)
        : (encoding: query.contentEncoding, skip: 0, fallback: false);
    primary = _TextDecoder(
      detected.encoding,
      _LiteralMatcher(query),
      strictUtf8: automatic && detected.encoding == 'utf8',
    );
    if (detected.fallback) {
      // Auto detection historically falls back to Latin-1 if any UTF-8 byte is
      // malformed, even near EOF. Keep a second bounded matcher instead of
      // buffering or rereading the file to discover that at the end.
      fallback = _TextDecoder(
        _sniffUtf16(bytes) ?? 'latin1',
        _LiteralMatcher(query),
      );
      fallback!.add(bytes);
    }
    primary!.add(Uint8List.sublistView(bytes, detected.skip));
  }

  var sinceYield = 0;
  await for (final chunk in stream) {
    check();
    for (var offset = 0; offset < chunk.length;) {
      check();
      final remaining = primary == null ? 1024 - sample.length : 32 * 1024;
      final end = math.min(chunk.length, offset + remaining);
      final part = chunk is Uint8List
          ? Uint8List.sublistView(chunk, offset, end)
          : chunk.sublist(offset, end);
      if (primary == null) {
        sample.add(part);
        if (sample.length == 1024) initialize();
      } else {
        primary!.add(part);
        fallback?.add(part);
      }
      sinceYield += end - offset;
      offset = end;
      if (sinceYield >= 256 * 1024) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
        check();
      }
    }
  }
  check();
  if (primary == null) initialize();
  primary!.close();
  fallback?.close();
  check();
  return (primary!.valid ? primary! : fallback!).matcher.result;
}

({String encoding, int skip, bool fallback}) _detectEncoding(Uint8List data) {
  if (data.length >= 4) {
    if (data[0] == 0xff && data[1] == 0xfe && data[2] == 0 && data[3] == 0) {
      return (encoding: 'utf32le', skip: 4, fallback: false);
    }
    if (data[0] == 0 && data[1] == 0 && data[2] == 0xfe && data[3] == 0xff) {
      return (encoding: 'utf32be', skip: 4, fallback: false);
    }
  }
  if (data.length >= 2) {
    if (data[0] == 0xff && data[1] == 0xfe) {
      return (encoding: 'utf16le', skip: 2, fallback: false);
    }
    if (data[0] == 0xfe && data[1] == 0xff) {
      return (encoding: 'utf16be', skip: 2, fallback: false);
    }
  }
  if (data.length >= 3 &&
      data[0] == 0xef &&
      data[1] == 0xbb &&
      data[2] == 0xbf) {
    return (encoding: 'utf8', skip: 3, fallback: true);
  }
  return (
    encoding: _sniffUtf16(data) ?? 'utf8',
    skip: 0,
    fallback: _sniffUtf16(data) == null,
  );
}

String? _sniffUtf16(Uint8List data) {
  if (data.length < 16) return null;
  final pairs = math.min(data.length, 1024) ~/ 2;
  var little = 0, big = 0;
  bool ascii(int value) =>
      (value >= 0x20 && value < 0x7f) ||
      value == 0x0a ||
      value == 0x0d ||
      value == 0x09;
  for (var i = 0; i < pairs; i++) {
    if (data[i * 2 + 1] == 0 && ascii(data[i * 2])) little++;
    if (data[i * 2] == 0 && ascii(data[i * 2 + 1])) big++;
  }
  if (little > pairs * .9) return 'utf16le';
  if (big > pairs * .9) return 'utf16be';
  return null;
}

class _TextDecoder {
  _TextDecoder(this.encoding, this.matcher, {bool strictUtf8 = false}) {
    if (encoding == 'utf8') {
      _utf8 = Utf8Decoder(allowMalformed: !strictUtf8).startChunkedConversion(
        StringConversionSink.from(_TextSink(matcher.add)),
      );
    }
  }
  final String encoding;
  final _LiteralMatcher matcher;
  ByteConversionSink? _utf8;
  List<int> _carry = const [];
  bool valid = true;

  void add(List<int> bytes) {
    if (!valid) return;
    if (_utf8 != null) {
      try {
        _utf8!.add(bytes);
      } on FormatException {
        valid = false;
      }
      return;
    }
    if (encoding == 'latin1') {
      matcher.add(latin1.decode(bytes));
      return;
    }
    final unit = encoding.startsWith('utf32') ? 4 : 2;
    final big = encoding.endsWith('be');
    final data = _carry.isEmpty ? bytes : [..._carry, ...bytes];
    final end = data.length - data.length % unit;
    final text = StringBuffer();
    for (var offset = 0; offset < end; offset += unit) {
      var code = 0;
      for (var i = 0; i < unit; i++) {
        code = (code << 8) | data[offset + (big ? i : unit - i - 1)];
      }
      if (unit == 4 &&
          (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))) {
        code = 0xfffd;
      }
      text.writeCharCode(code);
    }
    _carry = data.sublist(end);
    matcher.add(text.toString());
  }

  void close() {
    if (!valid) return;
    try {
      _utf8?.close();
    } on FormatException {
      valid = false;
    }
    // An incomplete final UTF-16/32 code unit follows the viewer's decoder:
    // ignore only those trailing bytes, never a complete unit.
  }
}

class _TextSink implements Sink<String> {
  _TextSink(this.callback);
  final void Function(String) callback;
  @override
  void add(String data) => callback(data);
  @override
  void close() {}
}

class _LiteralMatcher {
  _LiteralMatcher(this.query)
    : expression = RegExp(
        RegExp.escape(query.contentPattern),
        caseSensitive: query.contentCaseSensitive,
        unicode: true,
      );
  final FileSearchQuery query;
  final RegExp expression;
  String _tail = '';
  String? _snippet;
  int _processed = 0;
  int _afterNeeded = 0;
  bool _prefix = false, _suffix = false;

  void add(String text) {
    if (text.isEmpty) return;
    if (_snippet != null) {
      final used = math.min(_afterNeeded, text.length);
      _snippet = '$_snippet${text.substring(0, used)}';
      _afterNeeded -= used;
      if (used < text.length) _suffix = true;
      return;
    }
    final window = '$_tail$text';
    final match = expression.firstMatch(window);
    if (match != null) {
      final start = math.max(0, match.start - 45);
      final end = math.min(window.length, match.end + 90);
      _prefix = _processed - _tail.length + start > 0;
      _snippet = window.substring(start, end);
      _afterNeeded = math.max(0, match.end + 90 - window.length);
      _suffix = end < window.length;
      _tail = '';
    } else {
      // Preserve both a cross-chunk candidate and its preceding snippet text.
      final keep = query.contentPattern.length + 45;
      _tail = window.substring(math.max(0, window.length - keep));
    }
    _processed += text.length;
  }

  String? get result {
    if (query.contentNegated) {
      return _snippet == null ? 'Content does not contain the query.' : null;
    }
    if (_snippet == null) return null;
    return '${_prefix ? '…' : ''}${_snippet!.replaceAll('\n', ' ')}${_suffix ? '…' : ''}';
  }
}
