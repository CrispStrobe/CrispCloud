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
