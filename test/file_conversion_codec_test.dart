import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_conversion_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const codec = FileConversionCodec();
Future<Uint8List> collect(Stream<List<int>> stream) async {
  final output = BytesBuilder();
  await for (final chunk in stream) {
    output.add(chunk);
  }
  return output.takeBytes();
}

Stream<List<int>> pieces(List<int> bytes, int size) => Stream.fromIterable([
  for (var i = 0; i < bytes.length; i += size)
    bytes.sublist(i, (i + size).clamp(0, bytes.length)),
]);
const mime =
    'MIME-Version: 1.0\r\nContent-Type: application/octet-stream\r\n'
    'Content-Transfer-Encoding: base64\r\n\r\n';
Matcher problem(FileConversionCodecProblem value) =>
    isA<FileConversionCodecException>().having(
      (error) => error.problem,
      'problem',
      value,
    );

void main() {
  for (final format in FileConversionFormat.values) {
    test(
      '${format.name} round trips all byte values across arbitrary chunks',
      () async {
        final bytes = List.generate(40017, (i) => i % 256);
        final encoded = await collect(
          codec.encode(
            pieces(bytes, 37),
            format: format,
            filename: 'bytes.bin',
          ),
        );
        final decoded = await collect(
          codec.decode(pieces(encoded, 7), format: format),
        );
        expect(decoded, bytes);
        final lines = ascii.decode(encoded).split('\n');
        if (format == FileConversionFormat.mime) {
          final body = ascii.decode(encoded).split('\r\n\r\n').last;
          expect(
            body.trim().split('\r\n').every((line) => line.length <= 76),
            isTrue,
          );
          expect(base64.decode(body.replaceAll(RegExp(r'\s'), '')), bytes);
        } else {
          expect(
            lines
                .skip(1)
                .where((line) => line.length > 1 && line != 'end')
                .every((line) => line.length <= 61),
            isTrue,
          );
        }
      },
    );
    test('${format.name} empty input round trips', () async {
      final encoded = await collect(
        codec.encode(const Stream.empty(), format: format, filename: 'empty'),
      );
      expect(
        await collect(codec.decode(pieces(encoded, 1), format: format)),
        isEmpty,
      );
    });
  }

  test(
    'UUE and XXE interoperate with explicit six-bit standard vectors',
    () async {
      final expected = {
        FileConversionFormat.uue: 'begin 600 cat.txt\n#0V%T\n`\nend\n',
        FileConversionFormat.xxe: 'begin 600 cat.txt\n1Eq3o\n+\nend\n',
      };
      for (final entry in expected.entries) {
        expect(
          ascii.decode(
            await collect(
              codec.encode(
                Stream.value(ascii.encode('Cat')),
                format: entry.key,
                filename: 'cat.txt',
              ),
            ),
          ),
          entry.value,
        );
        expect(
          ascii.decode(
            await collect(
              codec.decode(
                pieces(ascii.encode(entry.value), 1),
                format: entry.key,
              ),
            ),
          ),
          'Cat',
        );
      }
    },
  );
  test('UUE accepts space zero, CRLF and a bounded preamble', () async {
    final encoded = ascii.encode(
      'A file follows\r\nbegin 644 x\r\n!30  \r\n \r\nend\r\n',
    );
    expect(
      ascii.decode(
        await collect(
          codec.decode(pieces(encoded, 1), format: FileConversionFormat.uue),
        ),
      ),
      'M',
    );
  });
  for (final body in [
    '#0V%T\nend\n',
    '#0V%T\n`\n',
    '#0V%\n`\nend\n',
    '#0V%TEXTRA\n`\nend\n',
    '#0V%T\n`\nend\nmore',
    '`\nend\nbegin 600 second\n`\nend\n',
  ]) {
    test(
      'rejects damaged, truncated, or multiple legacy blocks: $body',
      () async {
        await expectLater(
          collect(
            codec.decode(
              Stream.value(ascii.encode('begin 600 x\n$body')),
              format: FileConversionFormat.uue,
            ),
          ),
          throwsA(problem(FileConversionCodecProblem.malformed)),
        );
      },
    );
  }
  test(
    'Unicode filename is preserved in MIME filename*, and never emitted raw',
    () async {
      const filename = 'résumé-日本語.bin';
      final encoded = await collect(
        codec.encode(
          Stream.value([0, 255]),
          format: FileConversionFormat.mime,
          filename: filename,
        ),
      );
      expect(encoded.every((b) => b < 128), isTrue);
      expect(ascii.decode(encoded), contains("filename*=UTF-8''"));
      String? decodedName;
      expect(
        await collect(
          codec.decode(
            pieces(encoded, 1),
            format: FileConversionFormat.mime,
            onFilename: (name) => decodedName = name,
          ),
        ),
        [0, 255],
      );
      expect(decodedName, filename);
    },
  );
  test(
    'Unicode legacy name and header injection are rejected before output',
    () async {
      for (final name in ['日本語', 'name\r\nContent-Type: x', 'bad\x00name']) {
        await expectLater(
          collect(
            codec.encode(
              Stream.value([0]),
              format: FileConversionFormat.uue,
              filename: name,
            ),
          ),
          throwsA(problem(FileConversionCodecProblem.filename)),
        );
      }
    },
  );
  test('MIME standard padding vectors decode across one-byte chunks', () async {
    for (final entry in {
      '': '',
      'TQ==': 'M',
      'TWE=': 'Ma',
      'TWFu': 'Man',
    }.entries) {
      expect(
        ascii.decode(
          await collect(
            codec.decode(
              pieces(ascii.encode('$mime${entry.key}\r\n'), 1),
              format: FileConversionFormat.mime,
            ),
          ),
        ),
        entry.value,
      );
    }
  });
  for (final body in [
    'TQ=',
    'TQ===',
    '=AAA',
    'T=AA',
    'TQ==AA==',
    'TR==',
    'TWF=',
    'T!Fu',
    'TQ==\x00',
  ]) {
    test('MIME rejects invalid or ambiguous Base64: $body', () async {
      await expectLater(
        collect(
          codec.decode(
            Stream.value(ascii.encode('$mime$body')),
            format: FileConversionFormat.mime,
          ),
        ),
        throwsA(problem(FileConversionCodecProblem.malformed)),
      );
    });
  }
  for (final header in [
    'Content-Type: multipart/mixed; boundary=x\r\nContent-Transfer-Encoding: base64',
    'Content-Type: message/rfc822\r\nContent-Transfer-Encoding: base64',
    'Content-Type: text/plain\r\nContent-Transfer-Encoding: quoted-printable',
  ]) {
    test('MIME rejects unsupported entity: $header', () async {
      await expectLater(
        collect(
          codec.decode(
            Stream.value(ascii.encode('$header\r\n\r\nTQ==')),
            format: FileConversionFormat.mime,
          ),
        ),
        throwsA(problem(FileConversionCodecProblem.unsupportedMime)),
      );
    });
  }
  test('MIME rejects duplicate headers and incomplete headers', () async {
    for (final text in [
      'Content-Type: text/plain\nContent-Type: image/png\n\nTQ==',
      'Content-Type: text/plain\nContent-Transfer-Encoding: base64',
    ]) {
      await expectLater(
        collect(
          codec.decode(
            Stream.value(ascii.encode(text)),
            format: FileConversionFormat.mime,
          ),
        ),
        throwsA(problem(FileConversionCodecProblem.malformed)),
      );
    }
  });
  test(
    'bounded line and preamble/header input prevents unbounded accumulation',
    () async {
      for (final text in [
        'a' * 4097,
        '${'preamble\n' * 9000}begin 600 x\n`\nend\n',
      ]) {
        await expectLater(
          collect(
            codec.decode(
              pieces(ascii.encode(text), 100),
              format: FileConversionFormat.uue,
            ),
          ),
          throwsA(problem(FileConversionCodecProblem.headerLimit)),
        );
      }
    },
  );
  test('MIME exposes a safe embedded filename as optional metadata', () async {
    const input =
        'Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n'
        'Content-Disposition: attachment; filename="attachment.dat"\n\nTQ==';
    String? name;
    expect(
      await collect(
        codec.decode(
          Stream.value(ascii.encode(input)),
          format: FileConversionFormat.mime,
          onFilename: (value) => name = value,
        ),
      ),
      [77],
    );
    expect(name, 'attachment.dat');
  });
  for (final name in [
    '.',
    '..',
    '../outside',
    '/absolute',
    'folder/file',
    r'folder\file',
    'C:drive',
    r'C:\outside',
    r'\\server\share',
  ]) {
    test('every decoder rejects embedded path $name without a filename callback', () async {
      final inputs = {
        FileConversionFormat.uue: 'begin 600 $name\n#0V%T\n`\nend\n',
        FileConversionFormat.xxe: 'begin 600 $name\n1Eq3o\n+\nend\n',
        FileConversionFormat.mime:
            'Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n'
            "Content-Disposition: attachment; filename*=UTF-8''${Uri.encodeComponent(name)}\n\nQ2F0\n",
      };
      for (final entry in inputs.entries) {
        await expectLater(
          collect(
            codec.decode(
              pieces(ascii.encode(entry.value), 1),
              format: entry.key,
            ),
          ),
          throwsA(problem(FileConversionCodecProblem.malformed)),
          reason: entry.key.name,
        );
        await expectLater(
          collect(
            codec.encode(Stream.value([1]), format: entry.key, filename: name),
          ),
          throwsA(problem(FileConversionCodecProblem.filename)),
          reason: entry.key.name,
        );
      }
    });
  }
  test(
    'plain MIME filename paths are rejected without a metadata consumer',
    () async {
      const input =
          'Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n'
          'Content-Disposition: attachment; filename="../../outside"\n\nTQ==';
      await expectLater(
        collect(
          codec.decode(
            Stream.value(ascii.encode(input)),
            format: FileConversionFormat.mime,
          ),
        ),
        throwsA(problem(FileConversionCodecProblem.malformed)),
      );
    },
  );
  test(
    'RFC 2231 invalid escapes and unsupported continuations fail explicitly',
    () async {
      for (final parameter in [
        "filename*=UTF-8''bad%XX",
        "filename*=UTF-8''bad%00name",
        "filename*=UTF-8''ok; filename*1*=more",
        "filename*0*=UTF-8''a; filename*1*=b",
      ]) {
        final input =
            'Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n'
            'Content-Disposition: attachment; $parameter\n\nTQ==';
        await expectLater(
          collect(
            codec.decode(
              Stream.value(ascii.encode(input)),
              format: FileConversionFormat.mime,
            ),
          ),
          throwsA(isA<FileConversionCodecException>()),
        );
      }
    },
  );
}
