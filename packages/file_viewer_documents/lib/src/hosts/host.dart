// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
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
