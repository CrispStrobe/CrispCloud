import 'package:flutter/widgets.dart';

import '../models.dart';
import 'host.dart' show EbookHostSender;

Widget buildEbookHost({
  required String session,
  required void Function(EbookHostSender sender) onConnected,
  required void Function(EbookJson message) onMessage,
  required void Function(String message) onError,
}) =>
    const Center(
      child: Text('The ebook browser host is unavailable on this platform.'),
    );
