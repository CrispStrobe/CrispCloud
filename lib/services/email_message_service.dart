import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:quds_office_engine/quds_office_engine.dart'
    show BoundedCfbReader, CfbfDirectoryEntry;

const int kEmailPreviewMaxBytes = 32 * 1024 * 1024;
const int _maxBodyBytes = 8 * 1024 * 1024;
const int _maxAttachmentBytes = 16 * 1024 * 1024;
const int _maxHeaderBytes = 64 * 1024;

enum EmailPreviewWarning {
  unsupportedCharset,
  malformedEncoding,
  incompleteMultipart,
  embeddedOutlookAttachment,
  richTextOnly,
}

class EmailAttachment {
  const EmailAttachment({
    required this.name,
    required this.contentType,
    required this.bytes,
    this.isInline = false,
    this.contentId,
  });

  /// A basename only. It must still pass the destination's normal save checks.
  final String name;
  final String contentType;
  final Uint8List? bytes;
  final bool isInline;
  final String? contentId;
}

class EmailMessageDocument {
  const EmailMessageDocument({
    required this.subject,
    required this.from,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.date,
    required this.plainText,
    required this.safeHtml,
    required this.attachments,
    required this.warnings,
  });

  final String subject;
  final String from;
  final String to;
  final String cc;
  final String bcc;
  final String date;
  final String plainText;

  /// Formatting-only HTML: no links, images, CSS, attributes, or active content.
  final String? safeHtml;
  final List<EmailAttachment> attachments;
  final List<EmailPreviewWarning> warnings;

  String get searchText => [
        if (subject.isNotEmpty) 'Subject: $subject',
        if (from.isNotEmpty) 'From: $from',
        if (to.isNotEmpty) 'To: $to',
        if (cc.isNotEmpty) 'Cc: $cc',
        if (bcc.isNotEmpty) 'Bcc: $bcc',
        if (date.isNotEmpty) 'Date: $date',
        '',
        plainText,
        if (attachments.isNotEmpty) '',
        ...attachments.map((attachment) => attachment.name),
      ].join('\n');
}

/// Reads saved email without fetching remote content or invoking a mail client.
///
/// EML supports MIME multipart nesting, transfer encodings, RFC 2047 encoded
/// headers and RFC 2231 filenames. MSG uses the existing MIT office engine's
/// compound-file reader. Embedded Outlook messages are listed but not flattened
/// into their parent's body, sender, or attachments.
EmailMessageDocument parseEmailMessage(Uint8List bytes, String filename) {
  if (bytes.length > kEmailPreviewMaxBytes) {
    throw const FormatException('Email exceeds the 32 MiB preview limit');
  }
  final parser = _EmailParser();
  return filename.toLowerCase().endsWith('.msg')
      ? parser.parseMsg(bytes)
      : parser.parseEml(bytes);
}

class _EmailParser {
  final Set<EmailPreviewWarning> _warnings = {};
  final List<EmailAttachment> _attachments = [];
  int _parts = 0;
  int _decodedBytes = 0;

  EmailMessageDocument parseEml(Uint8List bytes) {
    final source = latin1.decode(bytes);
    final root = _splitPart(source);
    if (root.headers.isEmpty) {
      throw const FormatException('This file has no email headers');
    }
    final content = _parsePart(root, 0);
    final html = content.html == null ? null : _safeHtml(content.html!);
    return EmailMessageDocument(
      subject: _header(root.headers['subject'] ?? ''),
      from: _header(root.headers['from'] ?? ''),
      to: _header(root.headers['to'] ?? ''),
      cc: _header(root.headers['cc'] ?? ''),
      bcc: _header(root.headers['bcc'] ?? ''),
      date: _header(root.headers['date'] ?? ''),
      plainText: content.text ?? (html == null ? '' : _htmlText(html)),
      safeHtml: html,
      attachments: List.unmodifiable(_attachments),
      warnings: List.unmodifiable(_warnings),
    );
  }

  _EmailBody _parsePart(
    _MimePart part,
    int depth, {
    String defaultType = 'text/plain',
  }) {
    if (++_parts > 512 || depth > 20) {
      throw const FormatException('Email has too many MIME parts');
    }
    final type = _parameters(part.headers['content-type'] ?? defaultType);
    final disposition = _parameters(part.headers['content-disposition'] ?? '');
    final name = _parameter(disposition.$2, 'filename') ??
        _parameter(type.$2, 'name');
    final isAttachment = disposition.$1 == 'attachment' || name != null;
    if (type.$1.startsWith('multipart/') && !isAttachment) {
      final boundary = type.$2['boundary'];
      if (boundary == null || boundary.isEmpty || boundary.length > 200) {
        throw const FormatException('Multipart email has no valid boundary');
      }
      final boundaryPattern = RegExp(
        '(?:^|\\n)--${RegExp.escape(boundary)}(--)?[ \\t]*\\r?(?:\\n|\$)',
      );
      final childDefaultType = type.$1 == 'multipart/digest'
          ? 'message/rfc822'
          : 'text/plain';
      final contents = <_EmailBody>[];
      int? start;
      var closed = false;
      for (final match in boundaryPattern.allMatches(part.body)) {
        if (start != null) {
          var end = match.start;
          if (end > start && part.body.codeUnitAt(end - 1) == 13) end--;
          contents.add(
            _parsePart(
              _splitPart(part.body.substring(start, end)),
              depth + 1,
              defaultType: childDefaultType,
            ),
          );
        }
        if (match.group(1) != null) {
          closed = true;
          break;
        }
        start = match.end;
      }
      if (!closed) {
        _warnings.add(EmailPreviewWarning.incompleteMultipart);
        if (start != null && start < part.body.length) {
          contents.add(
            _parsePart(
              _splitPart(part.body.substring(start)),
              depth + 1,
              defaultType: childDefaultType,
            ),
          );
        }
      }
      if (contents.isEmpty) {
        throw const FormatException('Multipart email has no readable parts');
      }
      final texts = contents.map((body) => body.text).whereType<String>();
      final htmls = contents.map((body) => body.html).whereType<String>();
      // Alternatives are different representations of the same body. Other
      // multipart containers may have several distinct text body sections.
      return type.$1 == 'multipart/alternative'
          ? _EmailBody(texts.lastOrNull, htmls.lastOrNull)
          : _EmailBody(
              texts.isEmpty ? null : texts.join('\n\n'),
              htmls.isEmpty ? null : htmls.join('<hr>'),
            );
    }

    final decoded = _transferDecode(part.body, part.headers['content-transfer-encoding']);
    final contentId = part.headers['content-id']?.replaceAll(RegExp(r'[<>]'), '').trim();
    if (isAttachment ||
        (type.$1 != 'text/plain' && type.$1 != 'text/html')) {
      _addAttachment(
        EmailAttachment(
          name: _safeName(name ?? _defaultAttachmentName(type.$1, _attachments.length + 1)),
          contentType: type.$1,
          bytes: decoded,
          isInline: disposition.$1 == 'inline' || contentId != null,
          contentId: contentId,
        ),
      );
      return const _EmailBody(null, null);
    }
    if (decoded.length > _maxBodyBytes) {
      throw const FormatException('Email body exceeds the 8 MiB preview limit');
    }
    final body = _charset(decoded, type.$2['charset']);
    return type.$1 == 'text/html'
        ? _EmailBody(null, body)
        : _EmailBody(body, null);
  }

  EmailMessageDocument parseMsg(Uint8List bytes) {
    final cfb = BoundedCfbReader(
      bytes,
      maxFileBytes: kEmailPreviewMaxBytes,
      maxStreamBytes: _maxAttachmentBytes,
      maxTotalReadBytes: 64 * 1024 * 1024,
    );
    final root = cfb.root;
    final children = cfb.childrenOf(root);
    if (!children.any((entry) => entry.name.toLowerCase() == '__properties_version1.0')) {
      throw const FormatException('This compound document is not an Outlook message');
    }
    final properties = _msgProperties(cfb, root, 32);
    final charset = _codePage(properties[0x3ffd0003] ?? properties[0x3fde0003]);
    String text(CfbfDirectoryEntry parent, int id) {
      final stem = '__substg1.0_${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      final unicode = cfb.child(parent, '${stem}001F');
      if (unicode?.isStream ?? false) {
        return _charset(cfb.readEntry(unicode!), 'utf-16le').replaceAll(RegExp(r'\x00+$'), '');
      }
      final ansi = cfb.child(parent, '${stem}001E');
      if (ansi?.isStream ?? false) {
        return _charset(cfb.readEntry(ansi!), charset).replaceAll(RegExp(r'\x00+$'), '');
      }
      return '';
    }

    final rawHeaders = text(root, 0x007d);
    final headers = rawHeaders.isEmpty
        ? const <String, String>{}
        : _splitPart('${latin1.decode(utf8.encode(rawHeaders))}\r\n\r\n').headers;
    final recipients = <int, List<String>>{1: [], 2: [], 3: []};
    for (final storage in children.where((entry) => entry.isStorage)) {
      final lower = storage.name.toLowerCase();
      if (lower.startsWith('__recip_version1.0_')) {
        final recipientProperties = _msgProperties(cfb, storage, 8);
        final name = text(storage, 0x3001);
        final smtp = text(storage, 0x39fe);
        final address = smtp.isNotEmpty ? smtp : text(storage, 0x3003);
        final recipient = _address(name, address);
        if (recipient.isNotEmpty) {
          recipients[recipientProperties[0x0c150003] ?? 1]?.add(recipient);
        }
      } else if (lower.startsWith('__attach_version1.0_')) {
        final longName = text(storage, 0x3707);
        final shortName = text(storage, 0x3704);
        final contentType = text(storage, 0x370e);
        final contentId = text(storage, 0x3712);
        final data = cfb.child(storage, '__substg1.0_37010102');
        final embedded = cfb.child(storage, '__substg1.0_3701000D');
        if (embedded != null) _warnings.add(EmailPreviewWarning.embeddedOutlookAttachment);
        _addAttachment(
          EmailAttachment(
            name: _safeName(longName.isNotEmpty ? longName : shortName.isNotEmpty
                ? shortName : 'attachment-${_attachments.length + 1}${embedded == null ? '.bin' : '.msg'}'),
            contentType: contentType.isNotEmpty ? contentType
                : embedded == null ? 'application/octet-stream' : 'application/vnd.ms-outlook',
            bytes: data?.isStream == true ? cfb.readEntry(data!) : null,
            isInline: contentId.isNotEmpty,
            contentId: contentId.isEmpty ? null : contentId,
          ),
        );
      }
    }
    var body = text(root, 0x1000);
    var html = text(root, 0x1013);
    final htmlEntry = cfb.child(root, '__substg1.0_10130102');
    if (html.isEmpty && htmlEntry?.isStream == true) {
      html = _charset(cfb.readEntry(htmlEntry!), charset);
    }
    if (body.length > _maxBodyBytes || html.length > _maxBodyBytes) {
      throw const FormatException('Email body exceeds the preview size limit');
    }
    final safeHtml = html.isEmpty ? null : _safeHtml(html);
    if (body.isEmpty && safeHtml != null) body = _htmlText(safeHtml);
    if (body.isEmpty && cfb.child(root, '__substg1.0_10090102') != null) {
      _warnings.add(EmailPreviewWarning.richTextOnly);
    }
    String recipientHeader(int type, int property, String header) {
      if (recipients[type]!.isNotEmpty) return recipients[type]!.join(', ');
      final display = text(root, property);
      return display.isNotEmpty ? display : _header(headers[header] ?? '');
    }
    final senderName = text(root, 0x0c1a);
    final senderSmtp = text(root, 0x5d01);
    final senderAddress = senderSmtp.isNotEmpty ? senderSmtp : text(root, 0x0c1f);
    final from = _address(senderName, senderAddress);
    return EmailMessageDocument(
      subject: text(root, 0x0037),
      from: from.isNotEmpty ? from : _header(headers['from'] ?? ''),
      to: recipientHeader(1, 0x0e04, 'to'),
      cc: recipientHeader(2, 0x0e03, 'cc'),
      bcc: recipientHeader(3, 0x0e02, 'bcc'),
      date: _header(headers['date'] ?? '') .trim().isNotEmpty
          ? _header(headers['date']!)
          : _msgDate(cfb, root),
      plainText: body,
      safeHtml: safeHtml,
      attachments: List.unmodifiable(_attachments),
      warnings: List.unmodifiable(_warnings),
    );
  }

  Map<int, int> _msgProperties(BoundedCfbReader cfb, CfbfDirectoryEntry parent, int headerSize) {
    final entry = cfb.child(parent, '__properties_version1.0');
    if (entry == null || !entry.isStream) return {};
    final bytes = cfb.readEntry(entry);
    final view = ByteData.sublistView(bytes);
    final values = <int, int>{};
    for (var offset = headerSize; offset + 16 <= bytes.length; offset += 16) {
      final tag = view.getUint32(offset, Endian.little);
      if ((tag & 0xffff) == 3) values[tag] = view.getUint32(offset + 8, Endian.little);
    }
    return values;
  }

  String _msgDate(BoundedCfbReader cfb, CfbfDirectoryEntry parent) {
    final entry = cfb.child(parent, '__properties_version1.0');
    if (entry == null || !entry.isStream) return '';
    final bytes = cfb.readEntry(entry);
    final view = ByteData.sublistView(bytes);
    for (var offset = 32; offset + 16 <= bytes.length; offset += 16) {
      final tag = view.getUint32(offset, Endian.little);
      if (tag != 0x00390040 && tag != 0x0e060040) continue;
      // Splitting the 64-bit FILETIME also works on Dart's web runtime.
      final ticks = view.getUint32(offset + 8, Endian.little) +
          view.getUint32(offset + 12, Endian.little) * 4294967296;
      final micros = ticks ~/ 10 - 11644473600000000;
      if (micros.abs() > 8640000000000000000) return '';
      return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toIso8601String();
    }
    return '';
  }

  String? _codePage(int? codePage) => switch (codePage) {
        null || 0 || 1252 => 'windows-1252',
        65001 => 'utf-8',
        1200 => 'utf-16le',
        1201 => 'utf-16be',
        20127 => 'us-ascii',
        28591 => 'iso-8859-1',
        _ => 'windows-$codePage',
      };

  void _addAttachment(EmailAttachment attachment) {
    if (_attachments.length >= 128 || (attachment.bytes?.length ?? 0) > _maxAttachmentBytes) {
      throw const FormatException('Email attachments exceed the preview limits');
    }
    _attachments.add(attachment);
  }

  _MimePart _splitPart(String source) {
    // With no MIME headers, the first empty line alone separates the body.
    // Keep any subsequent blank lines or embedded message headers intact.
    if (source.startsWith('\r\n')) {
      return _MimePart(const {}, source.substring(2));
    }
    if (source.startsWith('\n')) {
      return _MimePart(const {}, source.substring(1));
    }
    final separator = RegExp(r'\r?\n\r?\n').firstMatch(source);
    final headerEnd = separator?.start ?? source.length;
    if (headerEnd > _maxHeaderBytes) {
      throw const FormatException('Email headers exceed the preview limit');
    }
    final headerSource = source.substring(0, headerEnd).replaceAll(RegExp(r'\r?\n[ \t]+'), ' ');
    final headers = <String, String>{};
    for (final line in headerSource.split(RegExp(r'\r?\n'))) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).toLowerCase().trim();
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) continue;
      final value = line.substring(colon + 1).trim();
      if ((name == 'to' || name == 'cc' || name == 'bcc') && headers.containsKey(name)) {
        headers[name] = '${headers[name]}, $value';
      } else {
        headers.putIfAbsent(name, () => value);
      }
    }
    return _MimePart(headers, separator == null ? '' : source.substring(separator.end));
  }

  Uint8List _transferDecode(String value, String? encoding) {
    Uint8List bytes;
    try {
      bytes = switch (encoding?.toLowerCase().trim()) {
        'base64' => base64.decode(value.replaceAll(RegExp(r'\s'), '')),
        'quoted-printable' => _quotedPrintable(value),
        _ => Uint8List.fromList(value.codeUnits),
      };
    } on FormatException {
      _warnings.add(EmailPreviewWarning.malformedEncoding);
      throw const FormatException('Email has an invalid transfer encoding');
    }
    _decodedBytes += bytes.length;
    if (_decodedBytes > kEmailPreviewMaxBytes) {
      throw const FormatException('Decoded email exceeds the preview limit');
    }
    return bytes;
  }

  String _header(String source) {
    final pattern = RegExp(r'=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?=');
    final out = StringBuffer();
    var offset = 0;
    var previousEncoded = false;
    for (final match in pattern.allMatches(source)) {
      final gap = source.substring(offset, match.start);
      if (!previousEncoded || gap.trim().isNotEmpty) {
        out.write(_charset(Uint8List.fromList(gap.codeUnits), null));
      }
      try {
        final bytes = match.group(2)!.toLowerCase() == 'b'
            ? base64.decode(match.group(3)!)
            : _quotedPrintable(match.group(3)!.replaceAll('_', ' '));
        out.write(_charset(bytes, match.group(1)));
      } on FormatException {
        _warnings.add(EmailPreviewWarning.malformedEncoding);
        out.write(match.group(0));
      }
      offset = match.end;
      previousEncoded = true;
    }
    out.write(_charset(Uint8List.fromList(source.substring(offset).codeUnits), null));
    return out.toString();
  }

  (String, Map<String, String>) _parameters(String source) {
    final parts = <String>[];
    final part = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (final code in source.codeUnits) {
      if (escaped) {
        part.writeCharCode(code);
        escaped = false;
      } else if (code == 92 && quoted) {
        escaped = true;
      } else if (code == 34) {
        quoted = !quoted;
      } else if (code == 59 && !quoted) {
        parts.add(part.toString().trim());
        part.clear();
      } else {
        part.writeCharCode(code);
      }
    }
    parts.add(part.toString().trim());
    final params = <String, String>{};
    for (final value in parts.skip(1)) {
      final equal = value.indexOf('=');
      if (equal <= 0) continue;
      params[value.substring(0, equal).trim().toLowerCase()] = value.substring(equal + 1).trim();
    }
    return (parts.first.toLowerCase(), params);
  }

  String? _parameter(Map<String, String> parameters, String name) {
    var extended = parameters['$name*'];
    if (extended == null && (parameters.containsKey('$name*0*') || parameters.containsKey('$name*0'))) {
      final value = StringBuffer();
      var encoded = false;
      for (var index = 0; index < 100; index++) {
        final segment = parameters['$name*$index*'] ?? parameters['$name*$index'];
        if (segment == null) break;
        encoded |= parameters.containsKey('$name*$index*');
        value.write(segment);
      }
      if (!encoded) return _header(value.toString());
      extended = value.toString();
    }
    if (extended != null) {
      final firstQuote = extended.indexOf("'");
      final secondQuote = firstQuote < 0 ? -1 : extended.indexOf("'", firstQuote + 1);
      final charset = firstQuote < 0 ? 'utf-8' : extended.substring(0, firstQuote);
      final encoded = secondQuote < 0 ? extended : extended.substring(secondQuote + 1);
      final bytes = <int>[];
      for (var index = 0; index < encoded.length; index++) {
        if (encoded.codeUnitAt(index) == 37 && index + 2 < encoded.length) {
          final byte = int.tryParse(encoded.substring(index + 1, index + 3), radix: 16);
          if (byte != null) {
            bytes.add(byte);
            index += 2;
            continue;
          }
        }
        bytes.add(encoded.codeUnitAt(index));
      }
      return _charset(Uint8List.fromList(bytes), charset);
    }
    final value = parameters[name];
    return value == null ? null : _header(value);
  }

  String _charset(Uint8List bytes, String? label) {
    final name = label?.toLowerCase().replaceAll('_', '-').trim();
    if (name == 'utf-16' || name == 'utf-16le' || name == 'utf-16be') {
      final big = name == 'utf-16be' || (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff);
      var start = 0;
      if (bytes.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) start = 2;
      final units = <int>[];
      for (var index = start; index + 1 < bytes.length; index += 2) {
        units.add(big ? bytes[index] * 256 + bytes[index + 1] : bytes[index] + bytes[index + 1] * 256);
      }
      if ((bytes.length - start).isOdd) {
        units.add(0xfffd);
        _warnings.add(EmailPreviewWarning.malformedEncoding);
      }
      return String.fromCharCodes(units);
    }
    if (name == 'iso-8859-1' || name == 'latin1' || name == 'latin-1') return latin1.decode(bytes);
    if (name == 'windows-1252' || name == 'cp1252') return _windows1252(bytes);
    if (name == 'us-ascii' || name == 'ascii') return ascii.decode(bytes, allowInvalid: true);
    if (name != null && name.isNotEmpty && name != 'utf-8' && name != 'utf8') {
      _warnings.add(EmailPreviewWarning.unsupportedCharset);
      return _windows1252(bytes);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      if (name != null) _warnings.add(EmailPreviewWarning.malformedEncoding);
      return name == null ? _windows1252(bytes) : utf8.decode(bytes, allowMalformed: true);
    }
  }
}

class _MimePart {
  const _MimePart(this.headers, this.body);
  final Map<String, String> headers;
  final String body;
}

class _EmailBody {
  const _EmailBody(this.text, this.html);
  final String? text;
  final String? html;
}

Uint8List _quotedPrintable(String value) {
  final bytes = BytesBuilder(copy: false);
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code == 61) {
      if (index + 1 < value.length && value.codeUnitAt(index + 1) == 10) {
        index++;
        continue;
      }
      if (index + 2 < value.length && value.substring(index + 1, index + 3) == '\r\n') {
        index += 2;
        continue;
      }
      if (index + 2 < value.length) {
        final byte = int.tryParse(value.substring(index + 1, index + 3), radix: 16);
        if (byte != null) {
          bytes.addByte(byte);
          index += 2;
          continue;
        }
      }
    }
    bytes.addByte(code);
  }
  return bytes.takeBytes();
}

String _windows1252(Uint8List bytes) {
  const replacements = [
    0x20ac, 0x81, 0x201a, 0x192, 0x201e, 0x2026, 0x2020, 0x2021,
    0x2c6, 0x2030, 0x160, 0x2039, 0x152, 0x8d, 0x17d, 0x8f,
    0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
    0x2dc, 0x2122, 0x161, 0x203a, 0x153, 0x9d, 0x17e, 0x178,
  ];
  return String.fromCharCodes(bytes.map((byte) => byte >= 0x80 && byte <= 0x9f ? replacements[byte - 0x80] : byte));
}

String _address(String name, String address) => name.isEmpty
    ? address : address.isEmpty || name == address ? name : '$name <$address>';

String _safeName(String name) {
  final basename = name.replaceAll('\\', '/').split('/').last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (basename.isEmpty || basename == '.' || basename == '..') return 'attachment.bin';
  return basename.length > 240 ? basename.substring(0, 240) : basename;
}

String _defaultAttachmentName(String type, int index) =>
    'attachment-$index${switch (type) {
      'message/rfc822' => '.eml',
      'image/png' => '.png',
      'image/jpeg' => '.jpg',
      'image/gif' => '.gif',
      'application/pdf' => '.pdf',
      _ => '.bin',
    }}';

String _safeHtml(String source) {
  final fragment = html_parser.parseFragment(source);
  const allowed = {
    'p', 'div', 'span', 'br', 'hr', 'blockquote', 'pre', 'code',
    'b', 'strong', 'i', 'em', 'u', 's', 'del', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table', 'thead', 'tbody',
    'tfoot', 'tr', 'th', 'td',
  };
  const discarded = {'script', 'style', 'head', 'iframe', 'object', 'embed', 'form', 'svg', 'math', 'template'};
  final out = StringBuffer();
  void visit(dom.Node node, int depth) {
    if (depth > 64) return;
    if (node is dom.Text) {
      out.write(const HtmlEscape().convert(node.data));
      return;
    }
    final tag = node is dom.Element ? node.localName : null;
    if (discarded.contains(tag)) return;
    final keep = allowed.contains(tag);
    if (keep) out.write('<$tag>');
    for (final child in node.nodes) {
      visit(child, depth + 1);
    }
    if (keep && tag != 'br' && tag != 'hr') out.write('</$tag>');
  }
  visit(fragment, 0);
  return out.toString();
}

String _htmlText(String safeHtml) {
  final fragment = html_parser.parseFragment(safeHtml);
  final out = StringBuffer();
  const blocks = {'p', 'div', 'br', 'hr', 'blockquote', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'tr'};
  void visit(dom.Node node) {
    if (node is dom.Text) {
      out.write(node.data);
      return;
    }
    final tag = node is dom.Element ? node.localName : null;
    if (tag == 'li') out.write('• ');
    for (final child in node.nodes) {
      visit(child);
    }
    if (blocks.contains(tag)) out.write('\n');
    if (tag == 'td' || tag == 'th') out.write('\t');
  }
  visit(fragment);
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
