// SPDX-License-Identifier: MIT
// CrispCloud document-host boundary checks, shared by native and web surfaces.
import 'dart:convert';

import '../models.dart';

const documentHostMaxMessageBytes = 1024 * 1024;
const documentHostMaxErrorCharacters = 2048;
final _sessionPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');

bool isDocumentHostSession(String session) => _sessionPattern.hasMatch(session);

String encodeDocumentHostMessage(DocumentJson message, String session) {
  if (!isDocumentHostSession(session) ||
      message['channel'] != documentPreviewChannel ||
      message['session'] != session) {
    throw ArgumentError('Invalid document host message session.');
  }
  final encoded = jsonEncode(message);
  if (encoded.length > documentHostMaxMessageBytes ||
      utf8.encode(encoded).length > documentHostMaxMessageBytes) {
    throw ArgumentError('Document host message exceeds the 1 MiB limit.');
  }
  return encoded;
}

/// Engine messages use a small string-only JSON envelope. Never materialize
/// arbitrary JavaScript objects or forward unrelated bridge messages to Flutter.
DocumentJson? decodeDocumentHostMessage(Object? value, String session) {
  if (!isDocumentHostSession(session) ||
      value is! String ||
      value.length > documentHostMaxMessageBytes ||
      utf8.encode(value).length > documentHostMaxMessageBytes) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['channel'] != documentPreviewChannel ||
        decoded['session'] != session ||
        !const {'ready', 'loaded', 'error'}.contains(decoded['type'])) {
      return null;
    }
    final message = <String, dynamic>{
      'channel': documentPreviewChannel,
      'session': session,
      'type': decoded['type'],
    };
    if (decoded['type'] == 'error') {
      final error = decoded['message'];
      if (error is! String) return null;
      message['message'] = documentHostError(error);
    }
    return message;
  } on FormatException {
    return null;
  } on StackOverflowError {
    return null;
  }
}

String documentHostError(String message) =>
    message.length <= documentHostMaxErrorCharacters
    ? message
    : message.substring(0, documentHostMaxErrorCharacters);

bool isDocumentHostUrl(Uri expected, String? candidate) {
  final uri = candidate == null ? null : Uri.tryParse(candidate);
  return uri != null &&
      uri.scheme == expected.scheme &&
      uri.host == expected.host &&
      uri.port == expected.port &&
      uri.path == expected.path &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      (!uri.hasFragment || uri.fragment == expected.fragment);
}

bool isDocumentHostBlobUrl(Uri expected, String? candidate) {
  if (candidate == null || !candidate.startsWith('blob:')) return false;
  final uri = Uri.tryParse(candidate.substring(5));
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.origin == expected.origin &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path.length > 1;
}

bool allowsDocumentHostNavigation(
  Uri expected,
  String? candidate, {
  required bool isMainFrame,
}) => isMainFrame
    ? isDocumentHostUrl(expected, candidate)
    : isDocumentHostBlobUrl(expected, candidate);
