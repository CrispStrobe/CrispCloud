import 'transfer_spool_contract.dart';

Future<TransferSpool> createTransferSpool(
  Stream<List<int>> source, {
  int? expectedLength,
  int? maxBytes,
  Future<void> Function()? checkpoint,
}) async => throw UnsupportedError('Temporary disk storage is unavailable.');
