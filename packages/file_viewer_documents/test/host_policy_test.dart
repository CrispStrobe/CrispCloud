// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:file_viewer_documents/src/hosts/host_policy.dart';
import 'package:file_viewer_documents/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = '0123456789abcdef0123456789abcdef';
  final location = Uri.parse(
    'http://127.0.0.1:8123/$session/index.html#$session',
  );
  Map<String, dynamic> message(String type) => {
    'channel': documentPreviewChannel,
    'session': session,
    'type': type,
  };

  test('accepts only correctly scoped engine status messages', () {
    expect(
      decodeDocumentHostMessage(jsonEncode(message('ready')), session),
      message('ready'),
    );
    expect(
      decodeDocumentHostMessage(jsonEncode(message('loaded')), session),
      message('loaded'),
    );
    for (final value in [
      message('ready'),
      'not JSON',
      '[]',
      'null',
      jsonEncode({...message('ready'), 'channel': 'crisp-ebook-v1'}),
      jsonEncode({
        ...message('ready'),
        'session': 'fedcba9876543210fedcba9876543210',
      }),
      jsonEncode(message('open')),
      jsonEncode(message('error')),
    ]) {
      expect(decodeDocumentHostMessage(value, session), isNull);
    }
    expect(
      decodeDocumentHostMessage(
        jsonEncode({
          ...message('ready'),
          'ignored': {'url': 'https://example.invalid'},
        }),
        session,
      ),
      message('ready'),
    );
  });

  test('caps JSON bytes and user-visible errors', () {
    expect(
      decodeDocumentHostMessage(
        'x' * (documentHostMaxMessageBytes + 1),
        session,
      ),
      isNull,
    );
    final error = {...message('error'), 'message': 'x' * 9000};
    expect(
      decodeDocumentHostMessage(jsonEncode(error), session)!['message'],
      hasLength(documentHostMaxErrorCharacters),
    );
    final unicode = {...message('error'), 'message': '界' * 400000};
    expect(jsonEncode(unicode).length, lessThan(documentHostMaxMessageBytes));
    expect(decodeDocumentHostMessage(jsonEncode(unicode), session), isNull);
    expect(
      () => encodeDocumentHostMessage(unicode, session),
      throwsArgumentError,
    );
  });

  test('preserves a real maximum transfer chunk within the outbound limit', () {
    final chunk = {
      ...message('chunk'),
      'offset': 0,
      'data': base64Encode(List.filled(documentPreviewChunkBytes, 42)),
    };
    final encoded = encodeDocumentHostMessage(chunk, session);
    expect(jsonDecode(encoded), chunk);
    expect(utf8.encode(encoded).length, lessThan(documentHostMaxMessageBytes));
    expect(
      () => encodeDocumentHostMessage({...chunk, 'session': 'wrong'}, session),
      throwsArgumentError,
    );
  });

  test('rejects invalid session tokens before a bridge is created', () {
    expect(isDocumentHostSession(session), isTrue);
    for (final value in ['', 'short', 'a' * 65, '/$session', '$session\n']) {
      expect(isDocumentHostSession(value), isFalse, reason: value);
    }
  });

  test('top-level navigation stays on its exact session document', () {
    expect(
      allowsDocumentHostNavigation(
        location,
        location.toString(),
        isMainFrame: true,
      ),
      isTrue,
    );
    expect(
      allowsDocumentHostNavigation(
        location,
        location.removeFragment().toString(),
        isMainFrame: true,
      ),
      isTrue,
    );
    for (final value in [
      null,
      'about:blank',
      'about:srcdoc',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'data:text/html,content',
      'https://127.0.0.1:8123/$session/index.html',
      'http://127.0.0.1:9999/$session/index.html',
      'http://localhost:8123/$session/index.html',
      'http://user@127.0.0.1:8123/$session/index.html',
      'http://127.0.0.1:8123/$session/index.html?other=1',
      'http://127.0.0.1:8123/$session/index.html#other',
      'blob:http://127.0.0.1:8123/topic-id',
    ]) {
      expect(
        allowsDocumentHostNavigation(location, value, isMainFrame: true),
        isFalse,
        reason: '$value',
      );
    }
  });

  test('child frames accept only this host origin’s generated blob URLs', () {
    expect(
      allowsDocumentHostNavigation(
        location,
        'blob:http://127.0.0.1:8123/topic-id',
        isMainFrame: false,
      ),
      isTrue,
    );
    for (final value in [
      'blob:https://remote.invalid/topic-id',
      'blob:null/topic-id',
      'blob:file:///topic-id',
      'blob:http://127.0.0.1:8124/topic-id',
      'blob:http://user@127.0.0.1:8123/topic-id',
      location.toString(),
      'about:srcdoc',
      'about:blank',
      'https://remote.invalid',
    ]) {
      expect(
        allowsDocumentHostNavigation(location, value, isMainFrame: false),
        isFalse,
        reason: value,
      );
    }
  });
}
