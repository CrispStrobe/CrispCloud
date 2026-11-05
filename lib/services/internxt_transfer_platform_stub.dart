import 'transfer_spool_contract.dart';

TransferSpool sliceSpool(TransferSpool spool, int start, int end) =>
    throw UnsupportedError('Private transfer storage is unavailable.');

Future<void> saveDownload(
  Stream<List<int>> source,
  String path, {
  required void Function() checkCurrent,
}) async => throw UnsupportedError('Native downloads are unavailable.');
