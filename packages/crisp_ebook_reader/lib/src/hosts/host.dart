import 'package:flutter/widgets.dart';

import '../models.dart';
import 'host_stub.dart'
    if (dart.library.io) 'host_native.dart'
    if (dart.library.js_interop) 'host_web.dart' as implementation;

typedef EbookHostSender = Future<void> Function(EbookJson message);

Widget createEbookHost({
  required String session,
  required void Function(EbookHostSender sender) onConnected,
  required void Function(EbookJson message) onMessage,
  required void Function(String message) onError,
}) =>
    implementation.buildEbookHost(
      session: session,
      onConnected: onConnected,
      onMessage: onMessage,
      onError: onError,
    );
