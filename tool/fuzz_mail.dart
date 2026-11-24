// Blind robustness fuzzing for saved-mail readers:
//   * EML MIME headers/bodies, transfer encodings and attachments
//   * Outlook MSG CFBF streams
//   * MBOX indexing and per-message decoding
//
// Typed format rejections are converted to a clean return inside the entry;
// any escape (RangeError, StateError, unterminated regex, etc.) is a finding.
//
// Run: dart run tool/fuzz_mail.dart [budgetMs]

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart'
    show CfbfException, CfbfWriter;

import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:crisp_cloud/services/mbox_message_service.dart';
import 'package:crisp_cloud/services/outlook_rtf_compression.dart';

Uint8List _utf16(String value) {
  final units = value.codeUnits;
  final out = Uint8List(units.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < units.length; i++) {
    view.setUint16(i * 2, units[i], Endian.little);
  }
  return out;
}

Uint8List _msgSeed() {
  final writer = CfbfWriter()
    ..addStream('__properties_version1.0', Uint8List(32))
    ..addStream('__substg1.0_0037001F', _utf16('Fuzz subject'))
    ..addStream('__substg1.0_0C1A001F', _utf16('Sender'))
    ..addStream('__substg1.0_5D01001F', _utf16('sender@example.test'))
    ..addStream('__substg1.0_1000001F', _utf16('Body text'));
  return writer.build();
}

List<Uint8List> _seeds() {
  const eml =
      'From: Sender <sender@example.test>\r\n'
      'To: Reader <reader@example.test>\r\n'
      'Subject: Hello\r\n'
      'Date: Tue, 24 Nov 2026 10:00:00 +0000\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: multipart/alternative; boundary="b"\r\n'
      '\r\n'
      '--b\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      '\r\n'
      'Hello world\r\n'
      '--b\r\n'
      'Content-Type: text/html; charset=utf-8\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      'PHA+SGVsbG8gPHN0cm9uZz53b3JsZDwvc3Ryb25nPjwvcD4=\r\n'
      '--b--\r\n';
  const mbox =
      'From sender@example.test Tue Nov 24 10:00:00 2026\n'
      'From: Sender <sender@example.test>\n'
      'To: Reader <reader@example.test>\n'
      'Subject: First\n'
      'Date: Tue, 24 Nov 2026 10:00:00 +0000\n'
      '\n'
      'Body one\n'
      '\n'
      'From sender@example.test Tue Nov 24 10:01:00 2026\n'
      'From: Sender <sender@example.test>\n'
      'Subject: Second\n'
      '\n'
      '>From escaped body\n';
  return <Uint8List>[
    Uint8List.fromList(latin1.encode(eml)),
    Uint8List.fromList(latin1.encode(eml.replaceAll('\r\n', '\n'))),
    Uint8List.fromList(latin1.encode(mbox)),
    _msgSeed(),
    Uint8List.fromList(const <int>[
      0xD0,
      0xCF,
      0x11,
      0xE0,
      0xA1,
      0xB1,
      0x1A,
      0xE1,
    ]),
  ];
}

void _parse(Uint8List bytes) {
  for (final name in const <String>['fuzz.eml', 'fuzz.msg']) {
    try {
      parseEmailMessage(bytes, name);
    } on FormatException {
      // Typed rejection.
    } on CfbfException {
      // Typed compound-file rejection.
    } on OutlookRtfException {
      // Typed compressed-RTF rejection.
    } on RangeError catch (error, stack) {
      stderr.writeln('RANGE: $error');
      stderr.writeln(stack);
      rethrow;
    }
  }
  try {
    final mailbox = parseMboxDocument(bytes);
    for (var i = 0; i < mailbox.messages.length && i < 4; i++) {
      try {
        mailbox.parseMessage(i);
      } on MboxMessageException {
        // One invalid message must not abort the mailbox.
      } on FormatException {
        // Typed message rejection.
      }
    }
  } on MboxPreviewException {
    // Typed mailbox rejection.
  }
}

void main(List<String> args) {
  final report = fuzz<Uint8List>(
    seeds: _seeds(),
    entry: _parse,
    mutate: mutateBytes,
    // The entry converts every documented rejection to a return. Any escape is
    // a parser defect, not an accepted error class.
    isClean: (_) => false,
    iterations: 50000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 20000,
    stressors: <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(latin1.encode('From: a\r\n\r\n')),
      Uint8List.fromList(latin1.encode('From a\n\n')),
    ],
  );
  exit(report.report());
}
