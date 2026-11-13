import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:crisp_cloud/services/mbox_message_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _envelope = 'From sender@example.test Fri Nov 13 12:34:56 2026';

Uint8List _bytes(String source) => Uint8List.fromList(utf8.encode(source));

String _record(
  String subject,
  String body, {
  String eol = '\n',
  String extraHeaders = '',
}) =>
    '$_envelope$eol'
    'Subject: $subject$eol'
    'From: sender@example.test$eol'
    'Content-Type: text/plain; charset=utf-8$eol'
    '$extraHeaders$eol$body';

Matcher _previewError(MboxPreviewError code) =>
    isA<MboxPreviewException>().having((error) => error.code, 'code', code);

Matcher _messageError(MboxMessageError code) =>
    isA<MboxMessageException>().having((error) => error.code, 'code', code);

void main() {
  test('indexes every message lazily with decoded summary fields', () {
    final source =
        _record('=?UTF-8?Q?Gr=C3=BC=C3=9Fe?=', 'first body\n') +
        _record('second', 'second body\n') +
        _record('third', 'third body');
    final document = parseMboxDocument(_bytes(source));
    expect(document.messages.map((entry) => entry.subject), [
      'Grüße',
      'second',
      'third',
    ]);
    expect(document.messages.map((entry) => entry.index), [0, 1, 2]);
    expect(document.parseMessage(2).plainText, 'third body');
    expect(document.parseMessage(0).plainText, 'first body\n');
    expect(document.parseMessage(1).from, 'sender@example.test');
  });

  test('header summaries do not decode a malformed MIME body', () {
    const source =
        '$_envelope\nSubject: Bad MIME\n'
        'From: =?UTF-8?B?SsO2cmc=?= <sender@example.test>\n'
        'Content-Type: multipart/mixed\n\nBroken\n';
    final document = parseMboxDocument(
      _bytes(source + _record('Good', 'Readable')),
    );
    expect(document.messages, hasLength(2));
    expect(document.messages.first.subject, 'Bad MIME');
    expect(document.messages.first.from, 'Jörg <sender@example.test>');
    expect(
      () => document.parseMessage(0),
      throwsA(_messageError(MboxMessageError.invalidMessage)),
    );
    expect(document.parseMessage(1).plainText, 'Readable');
  });

  test('mboxrd removes exactly one quote only at body line beginnings', () {
    final document = parseMboxDocument(
      _bytes(
        _record(
          '>From header unchanged',
          '>From original\r\n>>From quoted\n>>>From twice\n'
              '> From spaced\n>From: colon\n text >From midline\n'
              'From not a ctime envelope\n>From last',
        ),
      ),
    );
    final message = document.parseMessage(0);
    expect(message.subject, '>From header unchanged');
    expect(
      message.plainText,
      'From original\r\n>From quoted\n>>From twice\n'
      '> From spaced\n>From: colon\n text >From midline\n'
      'From not a ctime envelope\nFrom last',
    );
    expect(latin1.decode(document.messageBytes(0)), contains('>>>From twice'));
  });

  test(
    'quoted complete envelope is body content rather than another record',
    () {
      final document = parseMboxDocument(
        _bytes(_record('first', '>$_envelope\nSubject: still body\n\ntext')),
      );
      expect(document.messages, hasLength(1));
      expect(document.parseMessage(0).plainText, contains('$_envelope\n'));
    },
  );

  test(
    'byte offsets preserve BOM, CRLF, UTF-8 and a nonzero input subview',
    () {
      final first = _record('é', 'Grüße\r\n', eol: '\r\n');
      final second = _record('次', '本文', eol: '\r\n');
      final source = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(first + second),
      ]);
      final padded = Uint8List.fromList([9, 9, ...source, 8]);
      final document = parseMboxDocument(
        Uint8List.sublistView(padded, 2, 2 + source.length),
      );
      final entry = document.messages[1];
      expect(document.messages.first.envelopeStart, 3);
      expect(entry.envelopeStart, 3 + utf8.encode(first).length);
      expect(entry.messageStart, entry.envelopeStart + _envelope.length + 2);
      expect(entry.messageEnd, source.length);
      expect(entry.sourceByteRange, (
        start: entry.messageStart,
        end: source.length,
      ));
      expect(
        document.messageBytes(1),
        orderedEquals(source.sublist(entry.messageStart)),
      );
      expect(document.sourceBytes, orderedEquals(source));
      padded.fillRange(0, padded.length, 0);
      expect(document.sourceBytes, orderedEquals(source));
      expect(() => document.sourceBytes[0] = 0, throwsUnsupportedError);
      expect(
        () => document.sourceBytes.buffer.asUint8List()[0] = 0,
        throwsUnsupportedError,
      );
      expect(() => document.messageBytes(1)[0] = 0, throwsUnsupportedError);
      expect(() => document.messages.clear(), throwsUnsupportedError);
    },
  );

  test(
    'Content-Length counts bytes and protects literal envelope-like body',
    () {
      const body =
          'é\r\n$_envelope\r\nSubject: inside body\r\n\r\n'
          '>From unchanged\r\n';
      final first = _record(
        'Length-delimited',
        body,
        eol: '\r\n',
        extraHeaders: 'Content-Length: ${utf8.encode(body).length}\r\n',
      );
      final document = parseMboxDocument(
        _bytes('$first\r\n${_record('Actual second', 'Other')}'),
      );
      expect(document.messages, hasLength(2));
      expect(document.messages.first.usesContentLength, isTrue);
      expect(document.messages.first.messageEnd, utf8.encode(first).length);
      expect(document.messages[1].envelopeStart, utf8.encode(first).length + 2);
      expect(document.parseMessage(0).plainText, body);
      expect(document.parseMessage(1).subject, 'Actual second');
    },
  );

  test(
    'Content-Length permits zero body and excludes final newline padding',
    () {
      final first = _record('empty', '', extraHeaders: 'Content-Length: 0\n');
      final document = parseMboxDocument(
        _bytes(
          first + _record('last', 'x\n', extraHeaders: 'Content-Length: 1\n'),
        ),
      );
      expect(document.messages, hasLength(2));
      expect(document.parseMessage(0).plainText, '');
      expect(document.parseMessage(1).plainText, 'x');
      expect(
        document.messages.last.messageEnd,
        document.sourceBytes.length - 1,
      );
    },
  );

  for (final invalid in [
    'Content-Length: -1\n',
    'Content-Length: 1.5\n',
    'Content-Length: 999999999999999999999\n',
    'Content-Length: 100\n',
    'Content-Length: 2\nContent-Length: 2\n',
    'Content-Length: 2\n 0\n',
    'Content-Length : nope\n',
  ]) {
    test('rejects ambiguous length header $invalid', () {
      expect(
        () => parseMboxDocument(
          _bytes(_record('bad', 'ab', extraHeaders: invalid)),
        ),
        throwsA(_previewError(MboxPreviewError.ambiguousContentLength)),
      );
    });
  }

  test('does not guess a split when a length ends in a message body', () {
    final source =
        _record('bad', 'abc\n', extraHeaders: 'Content-Length: 1\n') +
        _record('next', 'hello');
    expect(
      () => parseMboxDocument(_bytes(source)),
      throwsA(_previewError(MboxPreviewError.ambiguousContentLength)),
    );
  });

  test('rejects length-counted adjacent envelopes without a line boundary', () {
    final source =
        _record('bad', 'abc', extraHeaders: 'Content-Length: 3\n') +
        _record('next', 'hello');
    expect(
      () => parseMboxDocument(_bytes(source)),
      throwsA(_previewError(MboxPreviewError.ambiguousContentLength)),
    );
  });

  test(
    'does not reinterpret an ordinary From line or invalid time as delimiter',
    () {
      const body =
          'From some prose\n'
          'From sender@example.test Fri Nov 13 99:00:00 2026\n'
          'From sender@example.test Fri Nov 0 12:00:00 2026\n';
      final document = parseMboxDocument(_bytes(_record('body', body)));
      expect(document.messages, hasLength(1));
      expect(document.parseMessage(0).plainText, body);
    },
  );

  test('accepts common envelope senders, spacing and timezone positions', () {
    for (final envelope in [
      'From - Fri Nov  6 12:34:56 2026',
      'From MAILER-DAEMON Fri Nov 13 12:34:56 UTC 2026',
      'From sender@example.test Fri Nov 13 12:34:56 2026 +0100',
      'From sender@example.test Fri Nov 13 12:34:56 2026 remote from mailhost',
    ]) {
      final document = parseMboxDocument(
        _bytes('$envelope\nSubject: test\n\nbody'),
      );
      expect(document.parseMessage(0).plainText, 'body');
    }
  });

  test('empty mailbox is valid but standalone EML and junk are rejected', () {
    expect(parseMboxDocument(Uint8List(0)).messages, isEmpty);
    for (final invalid in [
      'Subject: EML\n\ntext',
      'garbage\n$_envelope\n',
      'From prose\n',
    ]) {
      expect(
        () => parseMboxDocument(_bytes(invalid)),
        throwsA(_previewError(MboxPreviewError.invalidMailbox)),
      );
    }
  });

  test('malformed or oversized headers do not hide later valid messages', () {
    for (final headers in [
      'not an email header\n\n',
      'Subject: ${'x' * (64 * 1024)}\n\n',
    ]) {
      final document = parseMboxDocument(
        _bytes('$_envelope\n${headers}bad\n${_record('valid', 'OK')}'),
      );
      expect(document.messages, hasLength(2));
      expect(
        () => document.parseMessage(0),
        throwsA(_messageError(MboxMessageError.invalidMessage)),
      );
      expect(document.parseMessage(1).plainText, 'OK');
    }
  });

  test('header-only final message remains selectable', () {
    final document = parseMboxDocument(
      _bytes('$_envelope\nSubject: header only'),
    );
    expect(document.parseMessage(0).subject, 'header only');
    expect(document.parseMessage(0).plainText, '');
  });

  test('MIME attachments use the existing decoder and exact decoded bytes', () {
    const source =
        '$_envelope\nSubject: attachment\n'
        'Content-Type: multipart/mixed; boundary=x\n\n'
        '--x\nContent-Type: text/plain\n\nHello\n'
        '--x\nContent-Type: application/octet-stream\n'
        'Content-Disposition: attachment; filename="sample.bin"\n'
        'Content-Transfer-Encoding: base64\n\nAP8BgAo=\n--x--\n';
    final document = parseMboxDocument(_bytes(source));
    final message = document.parseMessage(0);
    expect(message.plainText, 'Hello');
    expect(message.attachments.single.name, 'sample.bin');
    expect(
      message.attachments.single.bytes,
      orderedEquals([0, 255, 1, 128, 10]),
    );
  });

  test(
    'per-message MIME attachment-count bounds do not block other entries',
    () {
      final parts = List.generate(
        129,
        (i) =>
            '--x\n'
            'Content-Type: application/octet-stream\n'
            'Content-Disposition: attachment; filename="$i.bin"\n\nX\n',
      ).join();
      final first =
          '$_envelope\nSubject: too many attachments\n'
          'Content-Type: multipart/mixed; boundary=x\n\n$parts--x--\n';
      final document = parseMboxDocument(_bytes(first + _record('good', 'OK')));
      expect(
        () => document.parseMessage(0),
        throwsA(_messageError(MboxMessageError.invalidMessage)),
      );
      expect(document.parseMessage(1).plainText, 'OK');
    },
  );

  test('oversized decoded attachment cannot bypass the existing EML limit', () {
    final first =
        '$_envelope\nSubject: large attachment\n'
        'Content-Type: application/octet-stream\n'
        'Content-Disposition: attachment; filename="large.bin"\n'
        'Content-Transfer-Encoding: 8bit\n\n'
        '${'a' * (16 * 1024 * 1024 + 1)}\n';
    final document = parseMboxDocument(_bytes(first + _record('good', 'OK')));
    expect(document.messages.first.error, isNull);
    expect(
      () => document.parseMessage(0),
      throwsA(_messageError(MboxMessageError.invalidMessage)),
    );
    expect(document.parseMessage(1).plainText, 'OK');
  });

  test('input and message-count caps reject without returning a prefix', () {
    expect(
      () => parseMboxDocument(Uint8List(kMboxPreviewMaxBytes + 1)),
      throwsA(_previewError(MboxPreviewError.inputLimit)),
    );
    final record = _record('small', 'x\n');
    final maximum = parseMboxDocument(_bytes(record * kMboxPreviewMaxMessages));
    expect(maximum.messages, hasLength(kMboxPreviewMaxMessages));
    expect(maximum.parseMessage(kMboxPreviewMaxMessages - 1).plainText, 'x\n');
    expect(
      () => parseMboxDocument(_bytes(record * (kMboxPreviewMaxMessages + 1))),
      throwsA(_previewError(MboxPreviewError.messageCountLimit)),
    );
  });

  test(
    'oversized message stays indexed without decoding and later mail opens',
    () {
      final first = _record('large', '${'x' * kMboxPreviewMaxMessageBytes}\n');
      final document = parseMboxDocument(
        _bytes(first + _record('small', 'OK')),
      );
      expect(document.messages, hasLength(2));
      expect(document.messages.first.error, MboxMessageError.messageLimit);
      expect(
        () => document.parseMessage(0),
        throwsA(_messageError(MboxMessageError.messageLimit)),
      );
      expect(document.parseMessage(1).plainText, 'OK');
    },
  );

  test('truncated and mutated input never produces out-of-range byte access', () {
    final valid = _bytes(
      _record('first', '>From body\n') + _record('next', 'OK'),
    );
    final random = Random(713);
    final inputs = <Uint8List>[
      for (var end = 0; end <= valid.length; end++)
        Uint8List.sublistView(valid, 0, end),
      for (var i = 0; i < 150; i++)
        (Uint8List.fromList(valid)
          ..[random.nextInt(valid.length)] = random.nextInt(256)),
    ];
    for (final input in inputs) {
      try {
        final document = parseMboxDocument(input);
        for (final entry in document.messages) {
          expect(entry.messageStart, inInclusiveRange(0, input.length));
          expect(
            entry.messageEnd,
            inInclusiveRange(entry.messageStart, input.length),
          );
          try {
            document.parseMessage(entry.index);
          } on MboxMessageException {
            // Malformed records are exposed as a bounded per-message failure.
          }
        }
      } on MboxPreviewException {
        // A malformed envelope/boundary is a documented whole-mailbox failure.
      }
    }
  });

  test(
    'summary helper decodes headers without entering MIME or attachment paths',
    () {
      final headers = parseEmailHeaders(
        _bytes(
          'Subject: =?UTF-8?Q?Mail_=E2=9C=93?=\r\n'
          'From: sender@example.test\r\nDate: today\r\n'
          'Content-Type: multipart/mixed\r\n\r\n',
        ),
      );
      expect(headers.subject, 'Mail ✓');
      expect(headers.from, 'sender@example.test');
      expect(headers.date, 'today');
    },
  );
}
