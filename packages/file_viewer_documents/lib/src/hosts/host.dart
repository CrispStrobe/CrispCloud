import 'package:flutter/widgets.dart';

import '../models.dart';
import 'host_stub.dart'
    if (dart.library.io) 'host_native.dart'
    if (dart.library.js_interop) 'host_web.dart'
    as implementation;

typedef DocumentHostSender = Future<void> Function(DocumentJson message);

Widget createDocumentHost({
  required String session,
  required void Function(DocumentHostSender sender) onConnected,
  required void Function(DocumentJson message) onMessage,
  required void Function(String message) onError,
}) => implementation.buildDocumentHost(
  session: session,
  onConnected: onConnected,
  onMessage: onMessage,
  onError: onError,
);
