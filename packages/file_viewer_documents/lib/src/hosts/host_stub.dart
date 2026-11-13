// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
import 'package:flutter/widgets.dart';

import '../models.dart';
import 'host.dart' show DocumentHostSender;

Widget buildDocumentHost({
  required String session,
  required void Function(DocumentHostSender sender) onConnected,
  required void Function(DocumentJson message) onMessage,
  required void Function(String message) onError,
}) => const Center(
  child: Text('The document browser host is unavailable on this platform.'),
);
