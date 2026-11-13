import 'dart:convert';
import 'dart:typed_data';

import 'email_message_service.dart';

const int kMboxPreviewMaxBytes = 64 * 1024 * 1024;
const int kMboxPreviewMaxMessages = 1000;
const int kMboxPreviewMaxMessageBytes = kEmailPreviewMaxBytes;
const int _maxHeaderBytes = 64 * 1024;
const int _maxEnvelopeBytes = 1024;

enum MboxPreviewError {
  inputLimit,
  messageCountLimit,
  invalidMailbox,
  ambiguousContentLength,
}

enum MboxMessageError { messageLimit, invalidMessage }

class MboxPreviewException implements Exception {
  const MboxPreviewException(this.code);

  final MboxPreviewError code;

  @override
  String toString() => 'MBOX preview: ${code.name}';
}

class MboxMessageException implements Exception {
  const MboxMessageException(this.code);

  final MboxMessageError code;

  @override
  String toString() => 'MBOX message: ${code.name}';
}

/// Offsets refer to the original stored mailbox, before any mboxrd unquoting.
/// [messageEnd] is exclusive. A Content-Length record excludes separator
/// padding after its body; other records retain their trailing stored newlines.
class MboxMessageEntry {
  const MboxMessageEntry({
    required this.index,
    required this.envelopeStart,
    required this.messageStart,
    required this.messageEnd,
    required this.bodyStart,
    required this.subject,
    required this.from,
    required this.date,
    required this.usesContentLength,
    required this.error,
  });

  final int index;
  final int envelopeStart;
  final int messageStart;
  final int messageEnd;
  final int? bodyStart;
  final String subject;
  final String from;
  final String date;
  final bool usesContentLength;
  final MboxMessageError? error;

  int get byteLength => messageEnd - messageStart;

  ({int start, int end}) get sourceByteRange =>
      (start: messageStart, end: messageEnd);
}

/// One immutable owned snapshot, with lazily decoded individual messages.
/// Indexing never transfer-decodes bodies, inflates data or opens attachments.
class MboxDocument {
  MboxDocument._(Uint8List bytes, List<MboxMessageEntry> messages)
    : sourceBytes = bytes.asUnmodifiableView(),
      messages = List.unmodifiable(messages);

  final Uint8List sourceBytes;
  final List<MboxMessageEntry> messages;

  /// Stored RFC message bytes, excluding the envelope line, without unquoting.
  Uint8List messageBytes(int index) {
    final entry = messages[index];
    return Uint8List.sublistView(
      sourceBytes,
      entry.messageStart,
      entry.messageEnd,
    ).asUnmodifiableView();
  }

  /// Content-Length variants retain quoted From lines: mboxcl and mboxcl2
  /// cannot be distinguished reliably. Without Content-Length the documented
  /// preview convention is mboxrd, removing exactly one '>' from >+From lines
  /// in the body only. [sourceBytes] and [messageBytes] always remain unchanged.
  EmailMessageDocument parseMessage(int index) {
    final entry = messages[index];
    final error = entry.error;
    if (error != null) throw MboxMessageException(error);
    final stored = messageBytes(index);
    final bytes = entry.usesContentLength || entry.bodyStart == null
        ? stored
        : _unquoteMboxrd(stored, entry.bodyStart! - entry.messageStart);
    try {
      return parseEmailMessage(bytes, 'message.eml');
    } on FormatException {
      throw const MboxMessageException(MboxMessageError.invalidMessage);
    }
  }
}

/// Indexes complete LF/CRLF mailboxes with traditional ctime From envelopes.
///
/// A valid Content-Length is a byte count from the body start, and must land at
/// EOF or a following envelope after newline padding. Invalid/duplicate lengths
/// are rejected instead of silently splitting a possibly unescaped body. Other
/// records follow mboxrd delimiter/escaping rules. An unescaped body line which
/// is itself a complete envelope remains intrinsically ambiguous in that format.
/// No partial mailbox is returned when an input/count/boundary limit is hit.
MboxDocument parseMboxDocument(Uint8List bytes) {
  if (bytes.length > kMboxPreviewMaxBytes) {
    throw const MboxPreviewException(MboxPreviewError.inputLimit);
  }
  final source = Uint8List.fromList(bytes);
  final messages = <MboxMessageEntry>[];
  if (source.isEmpty) return MboxDocument._(source, messages);

  // A UTF-8 BOM is accepted only before the first envelope. Its bytes remain
  // part of the source snapshot and therefore still count in every offset.
  var envelope =
      source.length >= 3 &&
          source[0] == 0xef &&
          source[1] == 0xbb &&
          source[2] == 0xbf
      ? 3
      : 0;
  if (!_isEnvelope(source, envelope)) {
    throw const MboxPreviewException(MboxPreviewError.invalidMailbox);
  }

  while (envelope < source.length) {
    if (messages.length >= kMboxPreviewMaxMessages) {
      throw const MboxPreviewException(MboxPreviewError.messageCountLimit);
    }
    final messageStart = _nextLine(source, envelope);
    final header = _readHeaders(source, messageStart);
    int messageEnd;
    int nextEnvelope;
    if (header.hasContentLength) {
      final length = header.contentLength;
      final body = header.bodyStart;
      if (header.invalidLength ||
          body == null ||
          length == null ||
          length > source.length - body) {
        throw const MboxPreviewException(
          MboxPreviewError.ambiguousContentLength,
        );
      }
      messageEnd = body + length;
      nextEnvelope = _afterLengthBody(source, messageEnd);
    } else {
      nextEnvelope = _findEnvelope(source, header.bodyStart ?? messageStart);
      messageEnd = nextEnvelope;
    }

    EmailMessageHeaders? summary;
    var error = messageEnd - messageStart > kMboxPreviewMaxMessageBytes
        ? MboxMessageError.messageLimit
        : null;
    if (header.bodyStart != null) {
      try {
        summary = parseEmailHeaders(
          Uint8List.sublistView(source, messageStart, header.bodyStart!),
        );
      } on FormatException {
        error ??= MboxMessageError.invalidMessage;
      }
    } else {
      error ??= MboxMessageError.invalidMessage;
    }
    messages.add(
      MboxMessageEntry(
        index: messages.length,
        envelopeStart: envelope,
        messageStart: messageStart,
        messageEnd: messageEnd,
        bodyStart: header.bodyStart,
        subject: summary?.subject ?? '',
        from: summary?.from ?? '',
        date: summary?.date ?? '',
        usesContentLength: header.hasContentLength,
        error: error,
      ),
    );
    envelope = nextEnvelope;
  }
  return MboxDocument._(source, messages);
}

class _MboxHeaders {
  const _MboxHeaders({
    required this.bodyStart,
    required this.hasContentLength,
    required this.contentLength,
    required this.invalidLength,
  });

  final int? bodyStart;
  final bool hasContentLength;
  final int? contentLength;
  final bool invalidLength;
}

_MboxHeaders _readHeaders(Uint8List bytes, int start) {
  var cursor = start;
  var hasLength = false;
  var invalidLength = false;
  var previousLength = false;
  int? length;
  int? body;
  while (cursor < bytes.length) {
    final lineEnd = _lineEnd(bytes, cursor, start + _maxHeaderBytes + 4);
    if (lineEnd - start > _maxHeaderBytes + 2 ||
        (cursor != start && _isEnvelope(bytes, cursor))) {
      break;
    }
    var contentEnd = lineEnd;
    if (contentEnd > cursor && bytes[contentEnd - 1] == 13) contentEnd--;
    final next = lineEnd < bytes.length && bytes[lineEnd] == 10
        ? lineEnd + 1
        : lineEnd;
    if (contentEnd == cursor) {
      body = next;
      break;
    }
    final continuation = bytes[cursor] == 32 || bytes[cursor] == 9;
    if (continuation) {
      // A folded numeric field is not accepted as a trustworthy body boundary.
      if (previousLength) invalidLength = true;
    } else {
      final line = latin1.decode(
        Uint8List.sublistView(bytes, cursor, contentEnd),
      );
      final colon = line.indexOf(':');
      previousLength =
          colon > 0 &&
          line.substring(0, colon).trim().toLowerCase() == 'content-length';
      if (previousLength) {
        if (hasLength) invalidLength = true;
        hasLength = true;
        final value = line.substring(colon + 1).trim();
        length = RegExp(r'^[0-9]{1,10}$').hasMatch(value)
            ? int.tryParse(value)
            : null;
        if (length == null) invalidLength = true;
      }
    }
    cursor = next;
  }
  // Header-only EML is supported, but Content-Length still requires an actual
  // blank header/body separator before its byte count can be interpreted.
  if (cursor == bytes.length && !hasLength) body = cursor;
  return _MboxHeaders(
    bodyStart: body,
    hasContentLength: hasLength,
    contentLength: length,
    invalidLength: invalidLength,
  );
}

int _afterLengthBody(Uint8List bytes, int end) {
  var cursor = end;
  while (cursor < bytes.length) {
    if (bytes[cursor] == 10) {
      cursor++;
    } else if (bytes[cursor] == 13 &&
        cursor + 1 < bytes.length &&
        bytes[cursor + 1] == 10) {
      cursor += 2;
    } else {
      break;
    }
  }
  if (cursor == bytes.length) return cursor;
  if ((cursor == 0 || bytes[cursor - 1] == 10) && _isEnvelope(bytes, cursor)) {
    return cursor;
  }
  throw const MboxPreviewException(MboxPreviewError.ambiguousContentLength);
}

int _findEnvelope(Uint8List bytes, int start) {
  var cursor = start;
  while (cursor < bytes.length) {
    if (_isEnvelope(bytes, cursor)) return cursor;
    cursor = _nextLine(bytes, cursor);
  }
  return bytes.length;
}

int _lineEnd(Uint8List bytes, int start, [int? limit]) {
  final end = limit != null && limit < bytes.length ? limit : bytes.length;
  var cursor = start;
  while (cursor < end && bytes[cursor] != 10) {
    cursor++;
  }
  return cursor;
}

int _nextLine(Uint8List bytes, int start) {
  final end = _lineEnd(bytes, start);
  return end < bytes.length ? end + 1 : end;
}

final _envelopePattern = RegExp(
  r'^From [^\x00-\x20\x7f]+ '
  r'(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) '
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) +'
  r'([0-9]{1,2}) ([0-9]{2}):([0-9]{2})(?::([0-9]{2}))? '
  r'(?:(?:[A-Za-z]{1,8}|[+-][0-9]{4}) )?([0-9]{4})'
  r'(?: (?:[A-Za-z]{1,8}|[+-][0-9]{4}))?'
  r'(?: remote from [^\x00-\x1f\x7f]+)?$',
);

bool _isEnvelope(Uint8List bytes, int start) {
  if (start + 5 > bytes.length ||
      bytes[start] != 70 ||
      bytes[start + 1] != 114 ||
      bytes[start + 2] != 111 ||
      bytes[start + 3] != 109 ||
      bytes[start + 4] != 32) {
    return false;
  }
  var end = _lineEnd(bytes, start, start + _maxEnvelopeBytes + 1);
  if (end - start > _maxEnvelopeBytes) return false;
  if (end > start && bytes[end - 1] == 13) end--;
  final match = _envelopePattern.firstMatch(
    latin1.decode(Uint8List.sublistView(bytes, start, end)),
  );
  if (match == null) return false;
  final day = int.parse(match[2]!);
  final hour = int.parse(match[3]!);
  final minute = int.parse(match[4]!);
  final second = int.parse(match[5] ?? '0');
  return day >= 1 && day <= 31 && hour < 24 && minute < 60 && second <= 60;
}

bool _quotedFrom(Uint8List bytes, int start) {
  if (start >= bytes.length || bytes[start] != 62) return false;
  var cursor = start + 1;
  while (cursor < bytes.length && bytes[cursor] == 62) {
    cursor++;
  }
  return cursor + 5 <= bytes.length &&
      bytes[cursor] == 70 &&
      bytes[cursor + 1] == 114 &&
      bytes[cursor + 2] == 111 &&
      bytes[cursor + 3] == 109 &&
      bytes[cursor + 4] == 32;
}

Uint8List _unquoteMboxrd(Uint8List bytes, int bodyStart) {
  var removed = 0;
  for (var cursor = bodyStart; cursor < bytes.length;) {
    if (_quotedFrom(bytes, cursor)) removed++;
    cursor = _nextLine(bytes, cursor);
  }
  if (removed == 0) return bytes;
  final output = Uint8List(bytes.length - removed);
  var copied = 0;
  var segment = 0;
  for (var cursor = bodyStart; cursor < bytes.length;) {
    if (_quotedFrom(bytes, cursor)) {
      output.setRange(copied, copied + cursor - segment, bytes, segment);
      copied += cursor - segment;
      segment = cursor + 1;
    }
    cursor = _nextLine(bytes, cursor);
  }
  output.setRange(copied, output.length, bytes, segment);
  return output;
}
