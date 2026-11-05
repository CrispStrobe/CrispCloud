import 'package:http/http.dart' as http;

import 'transfer_spool_contract.dart';

Future<http.Response> uploadSpooledHttpBody(
  Uri uri,
  TransferSpool spool, {
  required String operation,
  required void Function() checkCurrent,
  String method = 'PUT',
  Map<String, String> headers = const {},
  void Function(int, int)? onProgress,
}) async => throw UnsupportedError('Browser file upload is unavailable.');
