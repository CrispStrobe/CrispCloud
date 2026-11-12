import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/bounded_cfb_reader.dart';
import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show CfbfWriter;

import 'support/outlook_rtf_fixture.dart';

Uint8List _eml(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _utf16(String value) {
  final bytes = Uint8List(value.length * 2 + 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < value.length; i++) {
    view.setUint16(i * 2, value.codeUnitAt(i), Endian.little);
  }
  return bytes;
}

Uint8List _properties(int header, Map<int, int> values) {
  final bytes = Uint8List(header + values.length * 16);
  final view = ByteData.sublistView(bytes);
  var offset = header;
  for (final entry in values.entries) {
    view.setUint32(offset, entry.key, Endian.little);
    view.setUint32(offset + 8, entry.value, Endian.little);
    offset += 16;
  }
  return bytes;
}

void main() {
  group('EML', () {
    test('decodes folded RFC 2047 headers and quoted-printable body', () {
      final email = parseEmailMessage(
        _eml(
          'From: =?UTF-8?Q?J=C3=B6rg?= <joerg@example.test>\r\n'
          'To: reader@example.test\r\n'
          'Subject: =?UTF-8?B?R3LDvMOfZQ==?=\r\n'
          ' =?UTF-8?Q?_aus_Berlin?=\r\n'
          'Content-Type: text/plain; charset=UTF-8\r\n'
          'Content-Transfer-Encoding: quoted-printable\r\n\r\n'
          'Guten=20Tag,=\r\n\r\nGr=C3=BC=C3=9Fe!',
        ),
        'message.EML',
      );
      expect(email.from, 'Jörg <joerg@example.test>');
      expect(email.subject, 'Grüße aus Berlin');
      expect(email.plainText, 'Guten Tag,\r\nGrüße!');
      expect(email.searchText, contains('To: reader@example.test'));
      expect(email.warnings, isEmpty);
    });

    test(
      'nested alternatives select one body and retain exact attachment bytes',
      () {
        final email = parseEmailMessage(
          _eml('''From: a@example.test
Subject: Multipart
Content-Type: multipart/mixed; boundary="mix"

preamble
--mix
Content-Type: multipart/alternative; boundary="alt"

--alt
Content-Type: text/plain; charset=utf-8

Hello plain
--alt
Content-Type: text/html; charset=utf-8

<p>Hello <strong>formatted</strong></p>
--alt--
--mix
Content-Type: application/octet-stream
Content-Disposition: attachment; filename*0*=utf-8''r%C3%A9;
 filename*1*=sum%C3%A9.bin
Content-Transfer-Encoding: base64

AP8BgAo=
--mix--
epilogue
'''),
          'nested.eml',
        );
        expect(email.plainText, 'Hello plain');
        expect(email.safeHtml, contains('<strong>formatted</strong>'));
        expect(email.attachments.single.name, 'résumé.bin');
        expect(
          email.attachments.single.bytes,
          orderedEquals([0, 255, 1, 128, 10]),
        );
        expect(email.warnings, isEmpty);
      },
    );

    test(
      'HTML remains readable while no resource or active attribute survives',
      () {
        final email = parseEmailMessage(
          _eml('''Subject: HTML
Content-Type: text/html; charset=utf-8

<script>hidden-script</script><style>hidden-style</style>
<div style="background:url(https://tracker.test)">
<h2 onclick="alert(1)">Invoice</h2><p>Pay <b>today</b>.</p>
<a href="https://tracker.test">Link text</a>
<img src="https://tracker.test/pixel"><iframe src="https://tracker.test">hidden-frame</iframe>
<svg onload="alert(1)">hidden-svg</svg><form>hidden-form</form>
</div>'''),
          'safe.eml',
        );
        expect(email.plainText, contains('Invoice'));
        expect(email.plainText, contains('Pay today.'));
        expect(email.plainText, contains('Link text'));
        for (final unsafe in [
          'https:',
          'src=',
          'href=',
          'style=',
          'onclick',
          '<script',
          '<svg',
          'hidden-',
        ]) {
          expect(email.safeHtml, isNot(contains(unsafe)));
        }
        expect(email.safeHtml, contains('<b>today</b>'));
      },
    );

    test(
      'attached email stays an attachment and cannot replace outer headers',
      () {
        final email = parseEmailMessage(
          _eml('''From: outer@example.test
Subject: Outer
Content-Type: multipart/mixed; boundary=b

--b
Content-Type: text/plain

Outer body
--b
Content-Type: message/rfc822

From: inner@example.test
Subject: Inner

Inner body
--b--
'''),
          'message.eml',
        );
        expect(email.from, 'outer@example.test');
        expect(email.subject, 'Outer');
        expect(email.plainText, 'Outer body');
        expect(email.attachments.single.name, 'attachment-1.eml');
        expect(
          utf8.decode(email.attachments.single.bytes!),
          contains('Subject: Inner'),
        );
      },
    );

    test('headerless MIME body and digest messages honor default types', () {
      final plain = parseEmailMessage(
        _eml(
          'Subject: Bare part\n'
          'Content-Type: multipart/mixed; boundary=b\n\n'
          '--b\n\nBody without headers\n--b--\n',
        ),
        'bare.eml',
      );
      expect(plain.plainText, 'Body without headers');
      final digest = parseEmailMessage(
        _eml(
          'Subject: Digest\n'
          'Content-Type: multipart/digest; boundary=b\n\n'
          '--b\n\nSubject: Inner\n\nInner body\n--b--\n',
        ),
        'digest.eml',
      );
      expect(digest.plainText, isEmpty);
      expect(digest.attachments.single.name, 'attachment-1.eml');
      expect(
        utf8.decode(digest.attachments.single.bytes!),
        'Subject: Inner\n\nInner body',
      );
    });

    test('attachments with path components become basenames', () {
      final email = parseEmailMessage(
        _eml('''Subject: File
Content-Type: application/pdf; name="../../secret.pdf"
Content-Disposition: attachment; filename="../../secret.pdf"
Content-Transfer-Encoding: base64

JVBERg=='''),
        'file.eml',
      );
      expect(email.attachments.single.name, 'secret.pdf');
      expect(email.plainText, isEmpty);
    });

    test(
      'mixed body sections appear in both text and formatted representations',
      () {
        final email = parseEmailMessage(
          _eml(
            'Subject: Mixed body\n'
            'Content-Type: multipart/mixed; boundary=b\n\n'
            '--b\nContent-Type: text/plain\n\nCover <note>\n'
            '--b\nContent-Type: text/html\n\n<p>Second section</p>\n--b--\n',
          ),
          'mixed.eml',
        );
        expect(email.plainText, 'Cover <note>\n\nSecond section');
        expect(email.safeHtml, contains('<pre>Cover &lt;note&gt;</pre>'));
        expect(email.safeHtml, contains('<p>Second section</p>'));
      },
    );

    test('RFC 2231 literal continuations retain percent text', () {
      final email = parseEmailMessage(
        _eml(
          'Subject: File\n'
          'Content-Type: application/octet-stream\n'
          "Content-Disposition: attachment; filename*0*=utf-8''report%20;\n"
          ' filename*1="100%2Fdone.txt"\n\ncontents',
        ),
        'name.eml',
      );
      expect(email.attachments.single.name, 'report 100%2Fdone.txt');
    });

    test('boundary prefix in body does not split a part', () {
      final email = parseEmailMessage(
        _eml('''Subject: Boundaries
Content-Type: multipart/mixed; boundary="b"

--b
Content-Type: text/plain

first
--b-extra
second
--b--
'''),
        'boundaries.eml',
      );
      expect(email.plainText, 'first\n--b-extra\nsecond');
    });

    test('missing final boundary retains available body with a warning', () {
      final email = parseEmailMessage(
        _eml('''Subject: Truncated
Content-Type: multipart/mixed; boundary="b"

--b
Content-Type: text/plain

Readable body'''),
        'truncated.eml',
      );
      expect(email.plainText, 'Readable body');
      expect(email.warnings, contains(EmailPreviewWarning.incompleteMultipart));
    });

    test(
      'malformed base64 rejects the structured preview without losing source',
      () {
        expect(
          () => parseEmailMessage(
            _eml(
              'Subject: Corrupt\nContent-Transfer-Encoding: base64\n\nnot@base64!',
            ),
            'bad.eml',
          ),
          throwsFormatException,
        );
      },
    );

    test('oversized headers and deeply nested MIME are rejected', () {
      expect(
        () => parseEmailMessage(
          _eml('Subject: ${'x' * 65536}\n\nbody'),
          'huge.eml',
        ),
        throwsFormatException,
      );
      var source = 'Content-Type: text/plain\n\nhello';
      for (var index = 0; index < 22; index++) {
        source =
            'Content-Type: multipart/mixed; boundary=b$index\n\n--b$index\n$source\n--b$index--\n';
      }
      expect(
        () => parseEmailMessage(_eml(source), 'deep.eml'),
        throwsFormatException,
      );
    });

    test('Windows-1252 and unsupported charset fallback are explicit', () {
      final bytes = Uint8List.fromList([
        ...ascii.encode(
          'Subject: Currency\nContent-Type: text/plain; charset=windows-1252\n\n',
        ),
        0x80,
      ]);
      expect(parseEmailMessage(bytes, 'currency.eml').plainText, '€');
      final unknown = parseEmailMessage(
        _eml(
          'Subject: Unknown\nContent-Type: text/plain; charset=x-unknown\n\ntext',
        ),
        'unknown.eml',
      );
      expect(
        unknown.warnings,
        contains(EmailPreviewWarning.unsupportedCharset),
      );
    });
  });

  group('Outlook MSG', () {
    test(
      'reads Unicode headers, recipient type, body and binary attachment',
      () {
        final writer = CfbfWriter()
          ..addStream('__properties_version1.0', _properties(32, {}))
          ..addStream('__substg1.0_0037001F', _utf16('Grüße 世界'))
          ..addStream('__substg1.0_0C1A001F', _utf16('Sender'))
          ..addStream('__substg1.0_5D01001F', _utf16('sender@example.test'))
          ..addStream('__substg1.0_1000001F', _utf16('Message body'))
          ..addStream(
            '__recip_version1.0_#00000000/__properties_version1.0',
            _properties(8, {0x0c150003: 2}),
          )
          ..addStream(
            '__recip_version1.0_#00000000/__substg1.0_3001001F',
            _utf16('Reader'),
          )
          ..addStream(
            '__recip_version1.0_#00000000/__substg1.0_39FE001F',
            _utf16('reader@example.test'),
          )
          ..addStream(
            '__attach_version1.0_#00000000/__substg1.0_3707001F',
            _utf16('C:\\temp\\notes.bin'),
          )
          ..addStream(
            '__attach_version1.0_#00000000/__substg1.0_370E001F',
            _utf16('application/octet-stream'),
          )
          ..addStream('__attach_version1.0_#00000000/__substg1.0_37010102', [
            0,
            255,
            128,
            1,
          ]);
        final email = parseEmailMessage(writer.build(), 'mail.MSG');
        expect(email.subject, 'Grüße 世界');
        expect(email.from, 'Sender <sender@example.test>');
        expect(email.to, isEmpty);
        expect(email.cc, 'Reader <reader@example.test>');
        expect(email.plainText, 'Message body');
        expect(email.attachments.single.name, 'notes.bin');
        expect(email.attachments.single.bytes, orderedEquals([0, 255, 128, 1]));
        expect(email.warnings, isEmpty);
      },
    );

    test('embedded message cannot supply missing outer subject or sender', () {
      final writer = CfbfWriter()
        ..addStream('__properties_version1.0', _properties(32, {}))
        ..addStream('__substg1.0_1000001F', _utf16('Outer body'))
        ..addStream(
          '__attach_version1.0_#00000000/__substg1.0_3707001F',
          _utf16('forwarded.msg'),
        )
        ..addStream(
          '__attach_version1.0_#00000000/__substg1.0_3701000D/__substg1.0_0037001F',
          _utf16('Inner subject'),
        )
        ..addStream(
          '__attach_version1.0_#00000000/__substg1.0_3701000D/__substg1.0_0C1A001F',
          _utf16('Inner sender'),
        );
      final email = parseEmailMessage(writer.build(), 'outer.msg');
      expect(email.subject, isEmpty);
      expect(email.from, isEmpty);
      expect(email.plainText, 'Outer body');
      expect(email.attachments.single.name, 'forwarded.msg');
      expect(email.attachments.single.bytes, isNull);
      expect(
        email.warnings,
        contains(EmailPreviewWarning.embeddedOutlookAttachment),
      );
    });

    test('ANSI body honors codepage and HTML is safe', () {
      final writer = CfbfWriter()
        ..addStream(
          '__properties_version1.0',
          _properties(32, {0x3ffd0003: 1252, 0x3fde0003: 65001}),
        )
        ..addStream('__substg1.0_0037001E', latin1.encode('Résumé'))
        ..addStream(
          '__substg1.0_10130102',
          utf8.encode('<p>Hello 世界</p><img src="https://tracker.test">'),
        );
      final email = parseEmailMessage(writer.build(), 'html.msg');
      expect(email.subject, 'Résumé');
      expect(email.plainText, 'Hello 世界');
      expect(email.safeHtml, isNot(contains('https:')));
    });

    test('compressed and MELA RTF-only bodies render safe searchable text', () {
      for (final raw in [false, true]) {
        final writer = CfbfWriter()
          ..addStream('__properties_version1.0', _properties(32, {}))
          ..addStream(
            '__substg1.0_10090102',
            literalOutlookRtf(
              r'{\rtf1\ansi Hello \b formatted\b0  body.\par <script>alert(1)</script>}',
              uncompressed: raw,
            ),
          );
        final email = parseEmailMessage(writer.build(), 'rtf.msg');
        expect(email.plainText, contains('Hello formatted body.'));
        expect(email.safeHtml, contains('formatted'));
        expect(email.safeHtml, isNot(contains('<script>')));
        expect(email.searchText, contains('formatted body'));
        expect(email.warnings, isEmpty);
      }
    });

    test(
      'an existing plain body does not decode an unrelated corrupt RTF part',
      () {
        final writer = CfbfWriter()
          ..addStream('__properties_version1.0', _properties(32, {}))
          ..addStream('__substg1.0_1000001F', _utf16('Preferred plain body'))
          ..addStream('__substg1.0_10090102', [1, 2, 3]);
        final email = parseEmailMessage(writer.build(), 'rtf.msg');
        expect(email.plainText, 'Preferred plain body');
        expect(email.warnings, isEmpty);
      },
    );

    test('corrupt RTF-only message explains its limitation', () {
      final writer = CfbfWriter()
        ..addStream('__properties_version1.0', _properties(32, {}))
        ..addStream('__substg1.0_10090102', [1, 2, 3]);
      final email = parseEmailMessage(writer.build(), 'rtf.msg');
      expect(email.warnings, contains(EmailPreviewWarning.richTextOnly));
    });

    test('non-message compound files are rejected', () {
      final writer = CfbfWriter()..addStream('WordDocument', [1, 2, 3]);
      expect(
        () => parseEmailMessage(writer.build(), 'wrong.msg'),
        throwsFormatException,
      );
    });

    test('recipient count is bounded before reading individual properties', () {
      final writer = CfbfWriter()
        ..addStream('__properties_version1.0', _properties(32, {}));
      for (var index = 0; index < 513; index++) {
        writer.addStorage(
          '__recip_version1.0_#${index.toRadixString(16).padLeft(8, '0')}',
        );
      }
      expect(
        () => parseEmailMessage(writer.build(), 'many.msg'),
        throwsFormatException,
      );
    });
  });

  group('bounded compound reader', () {
    test('small and regular streams retain exact contents', () {
      final regular = List<int>.generate(8192, (index) => index % 256);
      final writer = CfbfWriter()
        ..addStream('parent/small', [7, 9, 11])
        ..addStream('parent/large', regular);
      final reader = BoundedCfbReader(writer.build());
      expect(reader.readPath('parent/small'), orderedEquals([7, 9, 11]));
      expect(reader.readPath('parent/large'), orderedEquals(regular));
      expect(reader.readPath('small'), isNull);
    });

    test('duplicate FAT references fail before the parser allocates them', () {
      final bytes = (CfbfWriter()..addStream('small', [1])).build();
      final view = ByteData.sublistView(bytes);
      view.setUint32(80, view.getUint32(76, Endian.little), Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
    });

    test('shared directory children and sibling cycles are rejected', () {
      final bytes =
          (CfbfWriter()
                ..addStream('A/value', [1])
                ..addStream('B/value', [2]))
              .build();
      final reader = BoundedCfbReader(bytes);
      final first = reader.child(reader.root, 'A')!;
      final second = reader.child(reader.root, 'B')!;
      final view = ByteData.sublistView(bytes);
      final directory = (view.getUint32(48, Endian.little) + 1) * 512;
      view.setUint32(
        directory + second.index * 128 + 76,
        first.child,
        Endian.little,
      );
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
      view.setUint32(
        directory + second.index * 128 + 76,
        second.child,
        Endian.little,
      );
      view.setUint32(
        directory + first.child * 128 + 68,
        first.child,
        Endian.little,
      );
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
    });

    test(
      'invalid indices and case-insensitive duplicate names are rejected',
      () {
        final bytes = (CfbfWriter()..addStream('parent/value', [1])).build();
        final reader = BoundedCfbReader(bytes);
        final parent = reader.child(reader.root, 'parent')!;
        final view = ByteData.sublistView(bytes);
        final directory = (view.getUint32(48, Endian.little) + 1) * 512;
        view.setUint32(
          directory + parent.index * 128 + 76,
          999999,
          Endian.little,
        );
        expect(() => BoundedCfbReader(bytes), throwsFormatException);
        final duplicates =
            (CfbfWriter()
                  ..addStream('Name', [1])
                  ..addStream('NAME', [2]))
                .build();
        expect(() => BoundedCfbReader(duplicates), throwsFormatException);
      },
    );

    test('untrusted stream size and cumulative read budget are bounded', () {
      final bytes = (CfbfWriter()..addStream('small', [1, 2, 3])).build();
      final reader = BoundedCfbReader(bytes, maxTotalReadBytes: 4);
      expect(reader.readPath('small'), orderedEquals([1, 2, 3]));
      expect(() => reader.readPath('small'), throwsFormatException);
      final view = ByteData.sublistView(bytes);
      final directory = (view.getUint32(48, Endian.little) + 1) * 512;
      view.setUint32(directory + 128 + 120, 0x7fffffff, Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
      view.setUint32(directory + 128 + 120, 3, Endian.little);
      view.setUint32(directory + 128 + 124, 1, Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
    });
  });
}
